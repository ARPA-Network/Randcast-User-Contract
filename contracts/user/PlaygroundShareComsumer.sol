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
    uint32 private constant DRAW_CALLBACK_FEE = 100000;
    uint32 private constant ROLL_CALLBACK_FEE = 100000;
    uint32 private constant FEE_OVERHEAD = 100000;
    uint32 private constant GROUP_SIZE = 3;

    // common subId for trial
    uint64 trialSubId;

    mapping(address => uint64) public userSubId;

    mapping(bytes32 => DrawRequestData) internal requestIdToDrawRequestData;
    mapping(bytes32 => RollRequestData) internal requestIdToRollRequestData;

    struct DrawRequestData {
        address user;
        uint256 totalNumber;
        uint256 winnerNumber;
    }

    struct RollRequestData {
        address user;
        uint256 rollNumber;
    }

    enum PlayType {
        Draw,
        Roll
    }

    event requestRollEvent(
        address user,
        uint64 subId,
        PlayType playType,
        bytes32 requestId,
        uint256 paidAmount,
        uint256 rollNumber,
        uint256 seed,
        uint16 requestConfirmations
    );

    event requestDrawEvent(
        address user,
        uint64 subId,
        PlayType playType,
        bytes32 requestId,
        uint256 paidAmount,
        uint256 totalNumber,
        uint256 winnerNumber,
        uint256 seed,
        uint16 requestConfirmations
    );

    event RollResult(address user, bytes32 requestId, uint256[] result);
    event DrawResult(address user, bytes32 requestId, uint256[] result);

    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);

    constructor(address adapter) BasicRandcastConsumerBase(adapter) {}
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
        if (msg.value >= fundAmount) {
            revert InsufficientFund({fundAmount: fundAmount, requiredAmount: msg.value});
        }
        IAdapter(adapter).fundSubscription{value: msg.value}(subId);
        return subId;
    }

    function estimateFee(PlayType playType, uint64 subId) internal view returns (uint256 requestFee) {
        IAdapter adapterInstance = IAdapter(adapter);

        uint32 callbackGasLimit = playType == PlayType.Draw ? DRAW_CALLBACK_FEE : ROLL_CALLBACK_FEE;

        // Get subscription details only if subId is not zero
        uint256 balance;
        uint64 reqCount;
        uint64 freeRequestCount = 1;
        uint64 reqCountInCurrentPeriod;
        uint256 lastRequestTimestamp;
        if (subId != 0) {
            (,, balance,, reqCount, freeRequestCount,, reqCountInCurrentPeriod, lastRequestTimestamp) =
                adapterInstance.getSubscription(subId);
        }

        uint32 tierFee = _calculateTierFee(reqCount, lastRequestTimestamp, reqCountInCurrentPeriod, freeRequestCount);

        requestFee = adapterInstance.estimatePaymentAmountInETH(
            callbackGasLimit, FEE_OVERHEAD, tierFee, tx.gasprice * 3, GROUP_SIZE
        ) - balance;
    }

    struct FeeConfig {
        bool isFlatFeePromotionEnabledPermanently;
        uint256 flatFeePromotionStartTimestamp;
        uint256 flatFeePromotionEndTimestamp;
        uint16 flatFeePromotionGlobalPercentage;
    }

    function _getFlatFeeConfig() internal view returns (FeeConfig memory feeConfig) {
        IAdapter adapterInstance = IAdapter(adapter);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            feeConfig.flatFeePromotionGlobalPercentage,
            feeConfig.isFlatFeePromotionEnabledPermanently,
            feeConfig.flatFeePromotionStartTimestamp,
            feeConfig.flatFeePromotionEndTimestamp
        ) = adapterInstance.getFlatFeeConfig();
    }

    function _calculateTierFee(
        uint64 reqCount,
        uint256 lastRequestTimestamp,
        uint64 reqCountInCurrentPeriod,
        uint64 freeRequestCount
    ) internal view returns (uint32 tierFee) {
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

        if (freeRequestCount == 0) {
            tierFee = IAdapter(adapter).getFeeTier(reqCountCalc) * feeConfig.flatFeePromotionGlobalPercentage / 100;
        }
        tierFee = 0;
    }

    function getRandomnessThenRollDice(uint256 rollNumber, uint256 seed, uint16 requestConfirmations, uint64 subId)
        external
        payable
        returns (bytes32 requestId)
    {
        _fundSubId(PlayType.Roll, subId);
        bytes memory params;
        params = abi.encode(rollNumber);
        requestId = _rawRequestRandomness(
            RequestType.RandomWords, params, subId, seed, requestConfirmations, ROLL_CALLBACK_FEE, tx.gasprice * 3
        );
        requestIdToRollRequestData[requestId] = RollRequestData(msg.sender, rollNumber);
        emit requestRollEvent(
            msg.sender, subId, PlayType.Roll, requestId, msg.value, rollNumber, seed, requestConfirmations
        );
    }

    function getRandomnessThenDrawTickects(
        uint256 totalNumber,
        uint256 winnerNumber,
        uint256 seed,
        uint16 requestConfirmations,
        uint64 subId
    ) external payable returns (bytes32 requestId) {
        _fundSubId(PlayType.Draw, subId);
        bytes memory params;
        requestId = _rawRequestRandomness(
            RequestType.Randomness, params, subId, seed, requestConfirmations, DRAW_CALLBACK_FEE, tx.gasprice * 3
        );
        requestIdToDrawRequestData[requestId] = DrawRequestData(msg.sender, totalNumber, winnerNumber);
        emit requestDrawEvent(
            msg.sender,
            subId,
            PlayType.Draw,
            requestId,
            msg.value,
            totalNumber,
            winnerNumber,
            seed,
            requestConfirmations
        );
    }

    /**
     * Callback function used by Randcast Adapter to generate a sets of dice result
     */
    function _fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) internal override {
        RollRequestData memory requestData = requestIdToRollRequestData[requestId];
        uint256[] memory diceResults = new uint256[](randomWords.length);
        for (uint32 i = 0; i < randomWords.length; i++) {
            diceResults[i] = RandcastSDK.roll(randomWords[i], 6) + 1;
        }
        emit RollResult(requestData.user, requestId, diceResults);
    }
    /**
     * Callback function used by Randcast Adapter to pick winner from a set of tickets
     */

    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        DrawRequestData memory requestData = requestIdToDrawRequestData[requestId];
        uint256[] memory tickets = new uint256[](requestData.totalNumber);
        uint256[] memory winnerResults;
        for (uint32 i = 0; i < requestData.totalNumber; i++) {
            tickets[i] = i;
        }
        winnerResults = RandcastSDK.draw(randomness, tickets, requestData.winnerNumber);
        emit DrawResult(requestData.user, requestId, winnerResults);
    }

    function cancelSubscription() external {
        uint64 subId = userSubId[msg.sender];
        if (subId == 0) {
            return;
        }
        (,, uint256 balance,,,,,,) = IAdapter(adapter).getSubscription(subId);
        IAdapter(adapter).cancelSubscription(subId, msg.sender);
        payable(msg.sender).transfer(balance);
        delete userSubId[msg.sender];
    }

    function setTrialSubscription(uint64 _trialSubId) external onlyOwner {
        trialSubId = _trialSubId;
        IAdapter(adapter).addConsumer(trialSubId, address(this));
    }
}
