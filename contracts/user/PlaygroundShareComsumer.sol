// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {BasicRandcastConsumerBase} from "./BasicRandcastConsumerBase.sol";
import {RequestIdBase} from "../utils/RequestIdBase.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
// solhint-disable-next-line no-global-import
import "./RandcastSDK.sol" as RandcastSDK;

contract PlaygroundShareComsumerContract is
    RequestIdBase,
    BasicRandcastConsumerBase,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    // To be update
    uint32 private constant DRAW_CALLBACK_GAS = 1000000;
    uint32 private constant ROLL_CALLBACK_GAS = 1000000;
    uint32 private constant FEE_OVERHEAD = 1000000;
    uint32 private constant GROUP_SIZE = 3;

    // common subId for trial
    uint64 trialSubId;

    mapping(address => uint64) public userSubId;

    mapping(bytes32 => RequestData) public requestIdToRequestData;

    struct RequestData {
        PlayType playType;
        bytes param;
    }

    enum PlayType {
        Draw,
        Roll
    }

    event requestRollEvent(
        address user,
        uint64 subId,
        bytes32 requestId,
        uint256 paidAmount,
        uint256 bunch,
        uint256 seed,
        uint16 requestConfirmations
    );

    event requestDrawEvent(
        address user,
        uint64 subId,
        bytes32 requestId,
        uint256 paidAmount,
        uint256 totalNumber,
        uint256 winnerNumber,
        uint256 seed,
        uint16 requestConfirmations
    );

    event RollResult(bytes32 requestId, uint256[] result);
    event DrawResult(bytes32 requestId, uint256[] result);

    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);
    error InvalidSubId();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address adapter) BasicRandcastConsumerBase(adapter) {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }
    // solhint-disable-next-line no-empty-blocks

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _fundSubId(PlayType playType, uint64 subId) internal returns (uint64) {
        if (subId == trialSubId) {
            return subId;
        }
        if (subId == 0) {
            subId = userSubId[msg.sender];
            if (subId == 0) {
                subId = IAdapter(adapter).createSubscription();
                IAdapter(adapter).addConsumer(subId, address(this));
                userSubId[msg.sender] = subId;
            }
        }
        uint256 fundAmount = estimateFee(playType, subId);
        if (msg.value < fundAmount) {
            revert InsufficientFund({fundAmount: fundAmount, requiredAmount: msg.value});
        }
        if (fundAmount == 0) {
            return subId;
        }
        IAdapter(adapter).fundSubscription{value: msg.value}(subId);
        return subId;
    }

    struct Subscription {
        uint256 balance;
        uint256 inflightCost;
        uint64 reqCount;
        uint64 freeRequestCount;
        uint64 reqCountInCurrentPeriod;
        uint256 lastRequestTimestamp;
    }

    function getSubscription(uint64 subId) internal view returns (Subscription memory sub) {
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

    function estimateFee(PlayType playType, uint64 subId) public view returns (uint256 requestFee) {
        uint32 callbackGasLimit = playType == PlayType.Draw ? DRAW_CALLBACK_GAS : ROLL_CALLBACK_GAS;
        if (subId == 0) {
            subId = userSubId[msg.sender];
            if (subId == 0) {
                return IAdapter(adapter).estimatePaymentAmountInETH(
                    callbackGasLimit, FEE_OVERHEAD, 0, tx.gasprice * 3, GROUP_SIZE
                );
            }
        }
        // Get subscription details only if subId is not zero
        Subscription memory sub = getSubscription(subId);
        uint32 tierFee;
        if (sub.freeRequestCount == 0) {
            tierFee = _calculateTierFee(sub.reqCount, sub.lastRequestTimestamp, sub.reqCountInCurrentPeriod);
        }
        uint256 estimatedFee = IAdapter(adapter).estimatePaymentAmountInETH(
            callbackGasLimit, FEE_OVERHEAD, tierFee, tx.gasprice * 3, GROUP_SIZE
        );
        return estimatedFee > (sub.balance - sub.inflightCost) ? estimatedFee - (sub.balance - sub.inflightCost) : 0;
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

    struct FeeConfig {
        uint16 flatFeePromotionGlobalPercentage;
        bool isFlatFeePromotionEnabledPermanently;
        uint256 flatFeePromotionStartTimestamp;
        uint256 flatFeePromotionEndTimestamp;
    }

    function _getFlatFeeConfig() public view returns (FeeConfig memory feeConfig) {
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

    function getRandomnessThenRollDice(uint256 bunch, uint256 seed, uint16 requestConfirmations, uint64 subId)
        external
        payable
        returns (bytes32 requestId)
    {
        subId = _fundSubId(PlayType.Roll, subId);
        bytes memory params;
        params = abi.encode(bunch);
        requestId = _rawRequestRandomness(
            RequestType.RandomWords, params, subId, seed, requestConfirmations, ROLL_CALLBACK_GAS, tx.gasprice * 3
        );
        emit requestRollEvent(msg.sender, subId, requestId, msg.value, bunch, seed, requestConfirmations);
        requestIdToRequestData[requestId] = RequestData(PlayType.Roll, abi.encode(bunch));
    }

    function getRandomnessThenDrawTickects(
        uint256 totalNumber,
        uint256 winnerNumber,
        uint256 seed,
        uint16 requestConfirmations,
        uint64 subId
    ) external payable returns (bytes32 requestId) {
        subId = _fundSubId(PlayType.Draw, subId);
        bytes memory params;
        requestId = _rawRequestRandomness(
            RequestType.Randomness, params, subId, seed, requestConfirmations, DRAW_CALLBACK_GAS, tx.gasprice * 3
        );
        emit requestDrawEvent(
            msg.sender, subId, requestId, msg.value, totalNumber, winnerNumber, seed, requestConfirmations
        );
        requestIdToRequestData[requestId] = RequestData(PlayType.Draw, abi.encode(totalNumber, winnerNumber));
    }

    /**
     * Callback function used by Randcast Adapter to generate a sets of dice result
     */
    function _fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) internal override {
        RequestData memory requestData = requestIdToRequestData[requestId];
        if (requestData.playType == PlayType.Roll) {
            (uint256 bunch) = abi.decode(requestData.param, (uint256));
            uint256[] memory diceResults = new uint256[](bunch);
            for (uint32 i = 0; i < randomWords.length; i++) {
                diceResults[i] = RandcastSDK.roll(randomWords[i], 6) + 1;
            }
            emit RollResult(requestId, diceResults);
            delete requestIdToRequestData[requestId];
        }
    }

    /**
     * Callback function used by Randcast Adapter to pick winner from a set of tickets
     */

    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        RequestData memory requestData = requestIdToRequestData[requestId];
        (uint256 totalNumber, uint256 winnerNumber) = abi.decode(requestData.param, (uint256, uint256));
        uint256[] memory tickets = new uint256[](totalNumber);
        uint256[] memory winnerResults;
        for (uint32 i = 0; i < totalNumber; i++) {
            tickets[i] = i;
        }
        winnerResults = RandcastSDK.draw(randomness, tickets, winnerNumber);
        emit DrawResult(requestId, winnerResults);
        delete requestIdToRequestData[requestId];
    }

    function cancelSubscription() external {
        uint64 subId = userSubId[msg.sender];
        if (subId == 0) {
            return;
        }
        (,, uint256 balance,,,,,,) = IAdapter(adapter).getSubscription(subId);
        IAdapter(adapter).cancelSubscription(subId, msg.sender);
        delete userSubId[msg.sender];
    }

    function setTrialSubscription(uint64 _trialSubId) external onlyOwner {
        trialSubId = _trialSubId;
    }

    function getTrialSubscription() external view returns (uint64) {
        return trialSubId;
    }
}
