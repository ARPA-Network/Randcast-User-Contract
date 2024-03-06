// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {BasicRandcastConsumerBase} from "./BasicRandcastConsumerBase.sol";
import {RequestIdBase} from "../utils/RequestIdBase.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
// solhint-disable-next-line no-global-import

contract ConsumerWrapper is RequestIdBase, BasicRandcastConsumerBase, UUPSUpgradeable, OwnableUpgradeable {

    uint32 private constant _FEE_OVERHEAD = 700000;
    uint32 private constant _GROUP_SIZE = 3;
    uint32 private constant _MAX_GAS_LIMIT = 2000000;

    struct RequestData {
        bytes32 entityId;
        address callbackAddress;
        bytes4 callbackFunctionSelector;
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
    
    event RandomNumberRequest(
        address indexed user,
        bytes32 indexed requestId,
        bytes32 entityId
    );
    
    event RandomNumberResult(bytes32 indexed requestId, uint256 result);
    
    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);
    error InvalidSubId();
    error GasLimitTooBig(uint256 have, uint32 want);
    error CallbackFailed(bytes32 requestId);

    mapping(address => uint64) public userSubIds;
    mapping(bytes32 => RequestData) public pendingRequests;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address adapter) BasicRandcastConsumerBase(adapter) {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }
    // solhint-disable-next-line no-empty-blocks

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function estimateFee(uint64 subId, uint32 callbackGasLimit)
        public
        view
        returns (uint256 requestFee)
    {
        uint32 overhead = _FEE_OVERHEAD;
        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                return IAdapter(adapter).estimatePaymentAmountInETH(
                    callbackGasLimit, overhead, 0, tx.gasprice * 3, _GROUP_SIZE
                );
            }
        }
        // Get subscription details only if subId is not zero
        Subscription memory sub = _getSubscription(subId);
        uint32 tierFee;
        if (sub.freeRequestCount == 0) {
            tierFee = _calculateTierFee(sub.reqCount, sub.lastRequestTimestamp, sub.reqCountInCurrentPeriod);
        }
        uint256 estimatedFee = IAdapter(adapter).estimatePaymentAmountInETH(
            callbackGasLimit, overhead, tierFee, tx.gasprice * 3, _GROUP_SIZE
        );
        return estimatedFee > (sub.balance - sub.inflightCost) ? estimatedFee - (sub.balance - sub.inflightCost) : 0;
    }

    function cancelSubscription() external {
        uint64 subId = userSubIds[msg.sender];
        if (subId == 0) {
            return;
        }
        IAdapter(adapter).cancelSubscription(subId, msg.sender);
        delete userSubIds[msg.sender];
    }

    function _fundSubId(uint64 subId, uint32 callbackGasLimit) internal returns (uint64) {

        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                subId = IAdapter(adapter).createSubscription();
                IAdapter(adapter).addConsumer(subId, address(this));
                userSubIds[msg.sender] = subId;
            }
        }
        uint256 requiredAmount = estimateFee(subId, callbackGasLimit);
        if (msg.value < requiredAmount) {
            revert InsufficientFund({fundAmount: msg.value, requiredAmount: requiredAmount});
        }
        if (requiredAmount == 0) {
            return subId;
        }
        IAdapter(adapter).fundSubscription{value: msg.value}(subId);
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
        ) = IAdapter(adapter).getSubscription(subId);
    }

    function _getFlatFeeConfig() internal view returns (FeeConfig memory feeConfig) {
        {
            (, bytes memory point) =
            // solhint-disable-next-line avoid-low-level-calls
             address(adapter).staticcall(abi.encodeWithSelector(IAdapter.getFlatFeeConfig.selector));
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
        return IAdapter(adapter).getFeeTier(reqCountCalc) * feeConfig.flatFeePromotionGlobalPercentage / 100;
    }

    function getRandomNumber(
        uint64 subId,
        bytes32 entityId,
        uint32 gasLimit,
        address callbackAddress,
        bytes4 callbackFunctionSelector)
        external payable returns (bytes32 requestId)
    {
        if (gasLimit > _MAX_GAS_LIMIT) {
            revert GasLimitTooBig(gasLimit, _MAX_GAS_LIMIT);
        }
        subId = _fundSubId(subId, gasLimit);
        (uint16 requestConfirmations,,,,,,) = IAdapter(adapter).getAdapterConfig();
        bytes memory params;
        requestId = _rawRequestRandomness(
            RequestType.Randomness, params, subId, 0, requestConfirmations, gasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData({
            entityId: entityId,
            callbackAddress: callbackAddress,
            callbackFunctionSelector: callbackFunctionSelector // Store the selector in the request data
        });
        emit RandomNumberRequest(callbackAddress, requestId, entityId);
    }

    // Modify the _fulfillRandomness function to use the stored callback function selector
    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        RequestData memory requestData = pendingRequests[requestId];
        // Using the callbackFunctionSelector to call the function on the requesting contract
        (bool success,) = requestData.callbackAddress.call(
            abi.encodeWithSelector(
                requestData.callbackFunctionSelector,
                requestId,
                randomness,
                requestData.entityId
            )
        );
        if (!success) {
            revert CallbackFailed(requestId);
        }
        delete pendingRequests[requestId];
        emit RandomNumberResult(requestId, randomness);
    }

}
