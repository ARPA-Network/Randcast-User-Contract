// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {BasicRandcastConsumerBase} from "./BasicRandcastConsumerBase.sol";
import {RequestIdBase} from "../utils/RequestIdBase.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
// solhint-disable-next-line no-global-import
import "./RandcastSDK.sol" as RandcastSDK;

contract SharedConsumer is RequestIdBase, BasicRandcastConsumerBase, UUPSUpgradeable, OwnableUpgradeable {
    uint32 private constant DRAW_CALLBACK_GAS_BASE = 40000;
    uint32 private constant ROLL_CALLBACK_GAS_BASE = 36000;
    uint32 private constant DRAW_CALLBACK_TOTAL_FACTOR = 371;
    uint32 private constant DRAW_CALLBACK_WINNER_FACTOR = 868;
    uint32 private constant ROLL_CALLBACK_BUNCH_FACTOR = 700;
    uint32 private constant FEE_OVERHEAD = 550000;
    uint32 private constant FEE_OVERHEAD_FACTOR = 500;
    uint32 private constant GROUP_SIZE = 3;
    uint32 private constant MAX_GAS_LIMIT = 2000000;

    // common subId for trial
    uint64 private trialSubId;

    mapping(address => uint64) public userSubIds;

    mapping(bytes32 => RequestData) public pendingRequests;

    struct RequestData {
        PlayType playType;
        bytes param;
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

    enum PlayType {
        Draw,
        Roll,
        Gacha
    }

    /// @notice Emitted when a roll dice randomness request is made
    /// @param user The address of the user making the request
    /// @param subId The subscription ID of the user making the request
    /// @param requestId The request ID of the request
    /// @param bunch The count of rolls
    /// @param size The size of each roll
    /// @param paidAmount The amount of ETH paid for the request
    /// @param seed The seed for the request
    /// @param requestConfirmations The number of confirmations for the request
    /// @param message The message for the request, usually the merkle root of the draw list
    event RollDiceRequest(
        address indexed user,
        uint64 indexed subId,
        bytes32 indexed requestId,
        uint32 bunch,
        uint32 size,
        uint256 paidAmount,
        uint256 seed,
        uint16 requestConfirmations,
        bytes message
    );

    /// @notice Emitted when a draw tickets randomness request is made
    event DrawTicketsRequest(
        address indexed user,
        uint64 indexed subId,
        bytes32 indexed requestId,
        uint32 totalNumber,
        uint32 winnerNumber,
        uint256 paidAmount,
        uint256 seed,
        uint16 requestConfirmations,
        bytes message
    );

    /// @notice Emitted when a gacha request is made
    event GachaRequest(
        address indexed user,
        uint64 indexed subId,
        bytes32 indexed requestId,
        uint32 count,
        uint256[] weights,
        uint256[] upperLimits,
        uint256 paidAmount,
        uint256 seed,
        uint16 requestConfirmations,
        bytes message
    );

    /// @notice Emitted when a roll dice result is generated
    event RollDiceResult(bytes32 indexed requestId, uint256[] result);

    /// @notice Emitted when a draw tickets result is generated
    event DrawTicketsResult(bytes32 indexed requestId, uint256[] result);

    /// @notice Emitted when a gacha result is generated
    event GachaResult(bytes32 indexed requestId, uint256[] weightResults, uint256[] indexResults);

    error InvalidParameters();
    error InvalidRequestData();
    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);
    error InvalidSubId();
    error GasLimitTooBig(uint256 have, uint32 want);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address adapter) BasicRandcastConsumerBase(adapter) {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }
    // solhint-disable-next-line no-empty-blocks

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function estimateFee(PlayType playType, uint64 subId, bytes memory params)
        public
        view
        returns (uint256 requestFee)
    {
        uint32 callbackGasLimit = _calculateGasLimit(playType, params);
        uint32 overhead = _calculateFeeOverhead(playType, params);
        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                return IAdapter(adapter)
                    .estimatePaymentAmountInETH(callbackGasLimit, overhead, 0, tx.gasprice * 3, GROUP_SIZE);
            }
        }
        // Get subscription details only if subId is not zero
        Subscription memory sub = _getSubscription(subId);
        uint32 tierFee;
        if (sub.freeRequestCount == 0) {
            tierFee = _calculateTierFee(sub.reqCount, sub.lastRequestTimestamp, sub.reqCountInCurrentPeriod);
        }
        uint256 estimatedFee = IAdapter(adapter)
            .estimatePaymentAmountInETH(callbackGasLimit, overhead, tierFee, tx.gasprice * 3, GROUP_SIZE);
        return estimatedFee > (sub.balance - sub.inflightCost) ? estimatedFee - (sub.balance - sub.inflightCost) : 0;
    }

    function gacha(
        uint32 count,
        uint256[] memory weights,
        uint256[] memory upperLimits,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations,
        bytes calldata message
    ) external payable returns (bytes32 requestId) {
        if (
            count > 100 || count == 0 || weights.length == 0 || upperLimits.length == 0
                || weights.length != upperLimits.length
        ) {
            revert InvalidParameters();
        }
        bytes memory requestParams = abi.encode(count, weights, upperLimits);
        uint32 gasLimit = _calculateGasLimit(PlayType.Gacha, requestParams);
        if (gasLimit > MAX_GAS_LIMIT) {
            revert GasLimitTooBig(gasLimit, MAX_GAS_LIMIT);
        }
        if (requestConfirmations == 0) {
            (requestConfirmations,,,,,,) = IAdapter(adapter).getAdapterConfig();
        }
        subId = _fundSubId(PlayType.Gacha, subId, requestParams);
        bytes memory params;
        params = abi.encode(count, weights, upperLimits);
        requestId = _rawRequestRandomness(
            RequestType.RandomWords, params, subId, seed, requestConfirmations, gasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData(PlayType.Gacha, requestParams);
        emit GachaRequest(
            msg.sender, subId, requestId, count, weights, upperLimits, msg.value, seed, requestConfirmations, message
        );
    }

    function rollDice(
        uint32 bunch,
        uint32 size,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations,
        bytes calldata message
    ) external payable returns (bytes32 requestId) {
        if (bunch > 100 || bunch == 0 || size == 0) {
            revert InvalidParameters();
        }
        bytes memory requestParams = abi.encode(bunch, size);
        uint32 gasLimit = _calculateGasLimit(PlayType.Roll, requestParams);
        if (gasLimit > MAX_GAS_LIMIT) {
            revert GasLimitTooBig(gasLimit, MAX_GAS_LIMIT);
        }
        if (requestConfirmations == 0) {
            (requestConfirmations,,,,,,) = IAdapter(adapter).getAdapterConfig();
        }
        subId = _fundSubId(PlayType.Roll, subId, requestParams);
        bytes memory params;
        params = abi.encode(bunch);
        requestId = _rawRequestRandomness(
            RequestType.RandomWords, params, subId, seed, requestConfirmations, gasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData(PlayType.Roll, requestParams);
        emit RollDiceRequest(msg.sender, subId, requestId, bunch, size, msg.value, seed, requestConfirmations, message);
    }

    function drawTickets(
        uint32 totalNumber,
        uint32 winnerNumber,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations,
        bytes calldata message
    ) external payable returns (bytes32 requestId) {
        if (totalNumber > 1000 || totalNumber < winnerNumber || totalNumber == 0 || winnerNumber == 0) {
            revert InvalidParameters();
        }
        bytes memory requestParams = abi.encode(totalNumber, winnerNumber);
        uint32 gasLimit = _calculateGasLimit(PlayType.Draw, requestParams);

        if (gasLimit > MAX_GAS_LIMIT) {
            revert GasLimitTooBig(gasLimit, MAX_GAS_LIMIT);
        }
        if (requestConfirmations == 0) {
            (requestConfirmations,,,,,,) = IAdapter(adapter).getAdapterConfig();
        }
        subId = _fundSubId(PlayType.Draw, subId, requestParams);
        bytes memory params;
        requestId = _rawRequestRandomness(
            RequestType.Randomness, params, subId, seed, requestConfirmations, gasLimit, tx.gasprice * 3
        );
        pendingRequests[requestId] = RequestData(PlayType.Draw, requestParams);
        emit DrawTicketsRequest(
            msg.sender, subId, requestId, totalNumber, winnerNumber, msg.value, seed, requestConfirmations, message
        );
    }

    function cancelSubscription() external {
        uint64 subId = userSubIds[msg.sender];
        if (subId == 0) {
            return;
        }
        IAdapter(adapter).cancelSubscription(subId, msg.sender);
        delete userSubIds[msg.sender];
    }

    function setTrialSubscription(uint64 _trialSubId) external onlyOwner {
        trialSubId = _trialSubId;
    }

    function getTrialSubscription() external view returns (uint64) {
        return trialSubId;
    }

    function _fundSubId(PlayType playType, uint64 subId, bytes memory params) internal returns (uint64) {
        if (subId == trialSubId) {
            return subId;
        }
        if (subId == 0) {
            subId = userSubIds[msg.sender];
            if (subId == 0) {
                subId = IAdapter(adapter).createSubscription();
                IAdapter(adapter).addConsumer(subId, address(this));
                userSubIds[msg.sender] = subId;
            }
        }
        uint256 requiredAmount = estimateFee(playType, subId, params);
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
            (
                ,
                bytes memory point
                // solhint-disable-next-line avoid-low-level-calls
            ) = address(adapter).staticcall(abi.encodeWithSelector(IAdapter.getFlatFeeConfig.selector));
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
            feeConfig.
                    //solhint-disable-next-line not-rely-on-time
                    flatFeePromotionStartTimestamp <= block.timestamp
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

    function _calculateGasLimit(PlayType playType, bytes memory params) internal pure returns (uint32 gasLimit) {
        if (playType == PlayType.Draw) {
            (uint32 totalNumber, uint32 winnerNumber) = abi.decode(params, (uint32, uint32));
            gasLimit = (DRAW_CALLBACK_GAS_BASE
                    + totalNumber
                    * DRAW_CALLBACK_TOTAL_FACTOR
                    + winnerNumber
                    * DRAW_CALLBACK_WINNER_FACTOR) * 4 / 3;
        } else if (playType == PlayType.Roll) {
            (uint32 bunch,) = abi.decode(params, (uint32, uint32));
            gasLimit = (ROLL_CALLBACK_GAS_BASE + bunch * ROLL_CALLBACK_BUNCH_FACTOR) * 4 / 3;
        } else if (playType == PlayType.Gacha) {
            gasLimit = MAX_GAS_LIMIT;
        }
    }

    function _calculateFeeOverhead(PlayType playType, bytes memory params) internal pure returns (uint32 overhead) {
        if (playType == PlayType.Draw) {
            overhead = FEE_OVERHEAD * 4 / 3;
        } else if (playType == PlayType.Roll) {
            (uint32 bunch,) = abi.decode(params, (uint32, uint32));
            overhead = (FEE_OVERHEAD + bunch * FEE_OVERHEAD_FACTOR) * 4 / 3;
        } else if (playType == PlayType.Gacha) {
            (uint32 count,,) = abi.decode(params, (uint32, uint32[], uint32[]));
            overhead = (FEE_OVERHEAD + count * FEE_OVERHEAD_FACTOR) * 4 / 3;
        }
    }

    /**
     * Callback function used by Randcast Adapter to generate a sets of dice result
     */
    function _fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) internal override {
        RequestData memory requestData = pendingRequests[requestId];
        // revert if requestData is empty
        if (requestData.param.length == 0) {
            revert InvalidRequestData();
        }
        if (requestData.playType == PlayType.Roll) {
            (uint32 bunch, uint32 size) = abi.decode(requestData.param, (uint32, uint32));
            uint256[] memory diceResults = new uint256[](bunch);
            for (uint32 i = 0; i < randomWords.length; i++) {
                diceResults[i] = RandcastSDK.roll(randomWords[i], size) + 1;
            }
            delete pendingRequests[requestId];
            emit RollDiceResult(requestId, diceResults);
        } else if (requestData.playType == PlayType.Gacha) {
            (uint32 count, uint256[] memory weights, uint256[] memory upperLimits) =
                abi.decode(requestData.param, (uint32, uint256[], uint256[]));
            uint256[] memory weightResults = new uint256[](count);
            uint256[] memory indexResults = new uint256[](count);
            for (uint32 i = 0; i < count; i++) {
                weightResults[i] = RandcastSDK.pickByWeights(randomWords[i], weights);
                indexResults[i] =
                    RandcastSDK.roll(uint256(keccak256(abi.encode(randomWords[i]))), upperLimits[weightResults[i]]) + 1;
            }
            delete pendingRequests[requestId];
            emit GachaResult(requestId, weightResults, indexResults);
        }
    }

    /**
     * Callback function used by Randcast Adapter to pick winner from a set of tickets
     */

    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        RequestData memory requestData = pendingRequests[requestId];
        // revert if requestData is empty
        if (requestData.param.length == 0) {
            revert InvalidRequestData();
        }
        if (requestData.playType == PlayType.Draw) {
            (uint32 totalNumber, uint32 winnerNumber) = abi.decode(requestData.param, (uint32, uint32));
            uint256[] memory tickets = new uint256[](totalNumber);
            for (uint32 i = 0; i < totalNumber; i++) {
                tickets[i] = i;
            }
            uint256[] memory winnerResults = RandcastSDK.drawWithOffset(randomness, tickets, winnerNumber, 1);
            delete pendingRequests[requestId];
            emit DrawTicketsResult(requestId, winnerResults);
        }
    }
}
