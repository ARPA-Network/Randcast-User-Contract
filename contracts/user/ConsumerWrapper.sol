// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {RequestIdBase} from "../utils/RequestIdBase.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IRequestTypeBase} from "../interfaces/IRequestTypeBase.sol";
// solhint-disable-next-line no-global-import

contract ConsumerWrapper is RequestIdBase, IRequestTypeBase, UUPSUpgradeable, OwnableUpgradeable {
    uint32 private constant _FEE_OVERHEAD = 700000;
    uint32 private constant _GROUP_SIZE = 3;
    uint32 private constant _RANDOMNESS_CALLBACK_GAS_BASE = 10000;
    uint32 private constant _RANDOMWORDS_CALLBACK_GAS_BASE = 36000;
    uint32 private constant _RANDOMWORDS_CALLBACK_BUNCH_FACTOR = 700;
    uint32 private constant _SHUFFLE_CALLBACK_GAS_BASE = 36000;
    uint32 private constant _SHUFFLE_CALLBACK_UPPER_FACTOR = 700;
    uint32 private constant _FEE_OVERHEAD_FACTOR = 500;
    bytes32 private constant _ADAPTER_SLOT = 0x360894a13aa1a3210667c824492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct RequestData {
        bytes32 entityId;
        address callbackAddress;
    }

    struct Subscription {
        uint256 balance;
        uint256 inflightCost;
        uint64 reqCount;
        uint64 freeRequestCount;
        uint64 reqCountInCurrentPeriod;
        uint256 lastRequestTimestamp;
    }

    struct FeeConfig {
        uint16 flatFeePromotionGlobalPercentage;
        bool isFlatFeePromotionEnabledPermanently;
        uint256 flatFeePromotionStartTimestamp;
        uint256 flatFeePromotionEndTimestamp;
    }

    event RandomnessRequest(address indexed user, bytes32 indexed requestId, bytes32 entityId);

    event RandomWordsRequest(address indexed user, bytes32 indexed requestId, bytes32 entityId, uint32 size);

    event ShuffleArrayRequest(address indexed user, bytes32 indexed requestId, bytes32 entityId, uint32 upper);

    event RandomnessResult(bytes32 indexed requestId, uint256 result, bool callBackSuccess);
    event RandomWordsResult(bytes32 indexed requestId, uint256[] results, bool callBackSuccess);

    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);
    error InvalidSubId();
    error GasLimitTooBig(uint256 have, uint32 want);
    error CallbackFailed(bytes32 requestId);

    mapping(address => uint64) public userSubIds;
    mapping(bytes32 => RequestData) public pendingRequests;
    mapping(uint64 => uint256) /* subId */ /* nonce */ private nonces;

    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {}

    function initialize() public initializer {
        __Ownable_init();
    }

    function disableInitializers() public onlyOwner {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setAdapterAddress(address adpater) external onlyOwner {
        assembly {
            sstore(_ADAPTER_SLOT, adpater)
        }
    }

    function getRandomness(uint64 subId, bytes32 entityId, uint32 callbackGasLimit, address callbackAddress)
        external
        payable
        returns (bytes32 requestId)
    {
        (uint16 requestConfirmations, uint32 maxGasLimit,,,,,) = IAdapter(_adapterAddress()).getAdapterConfig();
        if (callbackGasLimit > maxGasLimit) {
            revert GasLimitTooBig(callbackGasLimit, maxGasLimit);
        }
        bytes memory params;
        subId = _fundSubId(RequestType.Randomness, subId, params, callbackGasLimit);
        requestId = _rawRequestRandomness(
            RequestType.Randomness, params, subId, 0, requestConfirmations, callbackGasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData({entityId: entityId, callbackAddress: callbackAddress});
        emit RandomnessRequest(msg.sender, requestId, entityId);
    }

    function getRandomWords(
        uint64 subId,
        bytes32 entityId,
        uint32 size,
        uint32 callbackGasLimit,
        address callbackAddress
    ) external payable returns (bytes32 requestId) {
        (uint16 requestConfirmations, uint32 maxGasLimit,,,,,) = IAdapter(_adapterAddress()).getAdapterConfig();
        if (callbackGasLimit > maxGasLimit) {
            revert GasLimitTooBig(callbackGasLimit, maxGasLimit);
        }
        bytes memory requestParams = abi.encode(size);
        subId = _fundSubId(RequestType.RandomWords, subId, requestParams, callbackGasLimit);
        requestId = _rawRequestRandomness(
            RequestType.RandomWords, requestParams, subId, 0, requestConfirmations, callbackGasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData({entityId: entityId, callbackAddress: callbackAddress});
        emit RandomWordsRequest(msg.sender, requestId, entityId, size);
    }

    function getShuffleArray(
        uint64 subId,
        bytes32 entityId,
        uint32 upper,
        uint32 callbackGasLimit,
        address callbackAddress
    ) external payable returns (bytes32 requestId) {
        (uint16 requestConfirmations, uint32 maxGasLimit,,,,,) = IAdapter(_adapterAddress()).getAdapterConfig();
        if (callbackGasLimit > maxGasLimit) {
            revert GasLimitTooBig(callbackGasLimit, maxGasLimit);
        }
        bytes memory params = abi.encode(upper);
        subId = _fundSubId(RequestType.Shuffling, subId, params, callbackGasLimit);
        requestId = _rawRequestRandomness(
            RequestType.Shuffling, params, subId, 0, requestConfirmations, callbackGasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData({entityId: entityId, callbackAddress: callbackAddress});
        emit ShuffleArrayRequest(msg.sender, requestId, entityId, upper);
    }

    function cancelSubscription() external {
        uint64 subId = userSubIds[msg.sender];
        if (subId == 0) {
            return;
        }
        IAdapter(_adapterAddress()).cancelSubscription(subId, msg.sender);
        delete userSubIds[msg.sender];
    }

    function estimateFee(RequestType requestType, uint64 subId, bytes memory params, uint32 callbackGasLimit)
        public
        view
        returns (uint256 requestFee)
    {
        uint32 totalGasLimit = _calculateGasLimit(requestType, params) + callbackGasLimit;
        uint32 overhead = _calculateFeeOverhead(requestType, params);
        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                return IAdapter(_adapterAddress()).estimatePaymentAmountInETH(
                    totalGasLimit, overhead, 0, tx.gasprice * 3, _GROUP_SIZE
                );
            }
        }
        // Get subscription details only if subId is not zero
        Subscription memory sub = _getSubscription(subId);
        uint32 tierFee;
        if (sub.freeRequestCount == 0) {
            tierFee = _calculateTierFee(sub.reqCount, sub.lastRequestTimestamp, sub.reqCountInCurrentPeriod);
        }
        uint256 estimatedFee = IAdapter(_adapterAddress()).estimatePaymentAmountInETH(
            totalGasLimit, overhead, tierFee, tx.gasprice * 3, _GROUP_SIZE
        );
        return estimatedFee > (sub.balance - sub.inflightCost) ? estimatedFee - (sub.balance - sub.inflightCost) : 0;
    }

    function getSubscription(address user) external view returns (Subscription memory sub) {
        uint64 subId = userSubIds[user];
        if (subId == 0) {
            return sub;
        }
        return _getSubscription(subId);
    }

    function _adapterAddress() internal view returns (address r) {
        assembly {
            r := sload(_ADAPTER_SLOT)
        }
    }

    function _fundSubId(RequestType requestType, uint64 subId, bytes memory params, uint32 callbackGasLimit)
        internal
        returns (uint64)
    {
        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                subId = IAdapter(_adapterAddress()).createSubscription();
                IAdapter(_adapterAddress()).addConsumer(subId, address(this));
                userSubIds[msg.sender] = subId;
            }
        }
        uint256 requiredAmount = estimateFee(requestType, subId, params, callbackGasLimit);
        if (msg.value < requiredAmount) {
            revert InsufficientFund({fundAmount: msg.value, requiredAmount: requiredAmount});
        }
        if (requiredAmount == 0) {
            return subId;
        }
        IAdapter(_adapterAddress()).fundSubscription{value: msg.value}(subId);
        return subId;
    }

    function _getSubscription(uint64 subId) internal view returns (Subscription memory sub) {
        (
            ,
            ,
            sub.balance,
            sub.inflightCost,
            sub.reqCount,
            sub.freeRequestCount,
            ,
            sub.reqCountInCurrentPeriod,
            sub.lastRequestTimestamp
        ) = IAdapter(_adapterAddress()).getSubscription(subId);
    }

    function _getFlatFeeConfig() internal view returns (FeeConfig memory feeConfig) {
        {
            (, bytes memory point) =
            // solhint-disable-next-line avoid-low-level-calls
             address(_adapterAddress()).staticcall(abi.encodeWithSelector(IAdapter.getFlatFeeConfig.selector));
            uint16 flatFeePromotionGlobalPercentage;
            bool isFlatFeePromotionEnabledPermanently;
            uint256 flatFeePromotionStartTimestamp;
            uint256 flatFeePromotionEndTimestamp;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                flatFeePromotionGlobalPercentage := mload(add(point, 320))
                isFlatFeePromotionEnabledPermanently := mload(add(point, 352))
                flatFeePromotionStartTimestamp := mload(add(point, 384))
                flatFeePromotionEndTimestamp := mload(add(point, 416))
            }
            feeConfig = FeeConfig(
                flatFeePromotionGlobalPercentage,
                isFlatFeePromotionEnabledPermanently,
                flatFeePromotionStartTimestamp,
                flatFeePromotionEndTimestamp
            );
        }
    }

    function _calculateTierFee(uint64 reqCount, uint256 lastRequestTimestamp, uint64 reqCountInCurrentPeriod)
        internal
        view
        returns (uint32 tierFee)
    {
        // Use the new struct here.
        FeeConfig memory feeConfig = _getFlatFeeConfig();
        uint64 reqCountCalc;
        if (feeConfig.isFlatFeePromotionEnabledPermanently) {
            reqCountCalc = reqCount;
        } else if (
            feeConfig
                //solhint-disable-next-line not-rely-on-time
                .flatFeePromotionStartTimestamp <= block.timestamp
            //solhint-disable-next-line not-rely-on-time
            && block.timestamp <= feeConfig.flatFeePromotionEndTimestamp
        ) {
            if (lastRequestTimestamp < feeConfig.flatFeePromotionStartTimestamp) {
                reqCountCalc = 1;
            } else {
                reqCountCalc = reqCountInCurrentPeriod + 1;
            }
        }
        return IAdapter(_adapterAddress()).getFeeTier(reqCountCalc) * feeConfig.flatFeePromotionGlobalPercentage / 100;
    }

    function _calculateGasLimit(RequestType requestType, bytes memory params) internal pure returns (uint32 gasLimit) {
        if (requestType == RequestType.Randomness) {
            gasLimit = _RANDOMNESS_CALLBACK_GAS_BASE;
        } else if (requestType == RequestType.RandomWords) {
            uint32 size = abi.decode(params, (uint32));
            gasLimit = _RANDOMWORDS_CALLBACK_GAS_BASE + size * _RANDOMWORDS_CALLBACK_BUNCH_FACTOR;
        } else if (requestType == RequestType.Shuffling) {
            uint32 upper = abi.decode(params, (uint32));
            gasLimit = _SHUFFLE_CALLBACK_GAS_BASE + upper * _SHUFFLE_CALLBACK_UPPER_FACTOR;
        }
    }

    function _calculateFeeOverhead(RequestType requestType, bytes memory params)
        internal
        pure
        returns (uint32 overhead)
    {
        if (requestType == RequestType.Randomness) {
            overhead = _FEE_OVERHEAD;
        } else if (requestType == RequestType.RandomWords) {
            uint32 size = abi.decode(params, (uint32));
            overhead = (_FEE_OVERHEAD + size * _FEE_OVERHEAD_FACTOR);
        } else if (requestType == RequestType.Shuffling) {
            uint32 upper = abi.decode(params, (uint32));
            overhead = (_FEE_OVERHEAD + upper * _FEE_OVERHEAD_FACTOR);
        }
    }

    // Modify the _fulfillRandomness function to use the stored callback function selector
    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal {
        RequestData memory requestData = pendingRequests[requestId];
        // Using the callbackFunctionSelector to call the function on the requesting contract
        (bool success,) = requestData.callbackAddress.call(
            abi.encodeWithSignature(
                "fulfillRandomness(bytes32,bytes32,uint256)", requestData.entityId, requestId, randomness
            )
        );
        delete pendingRequests[requestId];
        emit RandomnessResult(requestId, randomness, success);
    }

    function _fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) internal {
        RequestData memory requestData = pendingRequests[requestId];
        // Using the callbackFunctionSelector to call the function on the requesting contract
        (bool success,) = requestData.callbackAddress.call(
            abi.encodeWithSignature(
                "fulfillRandomWords(bytes32,bytes32,uint256[])", requestData.entityId, requestId, randomWords
            )
        );
        delete pendingRequests[requestId];
        emit RandomWordsResult(requestId, randomWords, success);
    }

    function _fulfillShuffledArray(bytes32 requestId, uint256[] memory shuffledArray) internal {
        RequestData memory requestData = pendingRequests[requestId];
        // Using the callbackFunctionSelector to call the function on the requesting contract
        (bool success,) = requestData.callbackAddress.call(
            abi.encodeWithSignature(
                "fulfillShuffledArray(bytes32,bytes32,uint256[])", requestData.entityId, requestId, shuffledArray
            )
        );
        delete pendingRequests[requestId];
        emit RandomWordsResult(requestId, shuffledArray, success);
    }

    function _rawRequestRandomness(
        RequestType requestType,
        bytes memory params,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint256 callbackMaxGasPrice
    ) internal returns (bytes32) {
        nonces[subId] += 1;

        IAdapter.RandomnessRequestParams memory p = IAdapter.RandomnessRequestParams(
            requestType, params, subId, seed, requestConfirmations, callbackGasLimit, callbackMaxGasPrice
        );

        return IAdapter(_adapterAddress()).requestRandomness(p);
    }

    function rawFulfillRandomness(bytes32 requestId, uint256 randomness) external {
        require(msg.sender == _adapterAddress(), "Only adapter can fulfill");
        _fulfillRandomness(requestId, randomness);
    }

    function rawFulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) external {
        require(msg.sender == _adapterAddress(), "Only adapter can fulfill");
        _fulfillRandomWords(requestId, randomWords);
    }

    function rawFulfillShuffledArray(bytes32 requestId, uint256[] memory shuffledArray) external {
        require(msg.sender == _adapterAddress(), "Only adapter can fulfill");
        _fulfillShuffledArray(requestId, shuffledArray);
    }

    /**
     * Initialized nonce starts from 1.
     * It can't be used to check whether this contract is bound to the subscription id.
     */
    function getNonce(uint64 subId) public view returns (uint256) {
        return nonces[subId] + 1;
    }
}
