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
    uint16 private constant TYPE_DRAW = 0;
    uint16 private constant TYPE_CAST = 1;

    // To be update
    uint32 private constant DRAW_CALLBACK_FEE = 100000;
    uint32 private constant CAST_CALLBACK_FEE = 100000;
    uint32 private constant FEE_OVERHEAD = 100000;
    uint32 private constant REQUEST_FEE_OVERHEAD = 100000;
    uint32 private constant GROUP_SIZE = 3;

    mapping(address => uint64) public userSubId;
    
    mapping (bytes32 => RequestData) internal requestIdToRequestData;
    // solhint-disable-next-line no-empty-blocks
    struct RequestData {
        address user;
        uint16 playType;
        uint256 totalNumber;
        uint256 winnerNumber;
    }

    event PlayResult(address user, bytes32 requestId, uint256[] result);

    constructor(address adapter) BasicRandcastConsumerBase(adapter) {}
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _getAndFundSubId(uint16 playType) internal returns (uint64 subId) {
        subId = userSubId[msg.sender];
        if (subId == 0) {
            subId = IAdapter(adapter).createSubscription();
            IAdapter(adapter).addConsumer(subId, address(this));
            userSubId[msg.sender] = subId;
        }
        uint256 fundAmount = _estimateFee(playType, subId);
        IAdapter(adapter).fundSubscription{value: uint256(fundAmount)}(subId);
    }

    function _estimateFee(uint16 playType, uint64 subId) internal view returns (uint256 requestFee) {
        uint256 subBalance;
        uint64 subReqCount;
        uint64 subFreeRequestCount;
        uint256 subLastRequestTimestamp;
        uint64 subReqCountInCurrentPeriod;
        try
            IAdapter(adapter).getSubscription(subId) returns (
            address owner,
            address[] memory consumers,
            uint256 balance,
            uint256 inflightCost,
            uint64 reqCount,
            uint64 freeRequestCount,
            uint64 referralSubId,
            uint64 reqCountInCurrentPeriod,
            uint256 lastRequestTimestamp
        ) {
            subBalance = balance;
            subReqCount = reqCount;
            subFreeRequestCount = freeRequestCount;
            subLastRequestTimestamp = lastRequestTimestamp;
            subReqCountInCurrentPeriod = reqCountInCurrentPeriod;
        }
        catch {
            subBalance = 0;
            subReqCount = 0;
            subFreeRequestCount = 1;
            subLastRequestTimestamp = block.timestamp;
            subReqCountInCurrentPeriod = 0;
        }
        
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
            uint16 flatFeePromotionGlobalPercentage,
            bool isFlatFeePromotionEnabledPermanently,
            uint256 flatFeePromotionStartTimestamp,
            uint256 flatFeePromotionEndTimestamp
        ) = IAdapter(adapter).getFlatFeeConfig();

        uint32 callbackGasLimit;
        if (playType == TYPE_DRAW) {
            callbackGasLimit = DRAW_CALLBACK_FEE;
        } else if (playType == TYPE_CAST) {
            callbackGasLimit = CAST_CALLBACK_FEE;
        }

        uint64 reqCountCalc;
        if (isFlatFeePromotionEnabledPermanently) {
            reqCountCalc = subReqCount;
        } else if (
            //solhint-disable-next-line not-rely-on-time
            flatFeePromotionStartTimestamp <= block.timestamp
            //solhint-disable-next-line not-rely-on-time
            && block.timestamp <= flatFeePromotionEndTimestamp
        ) {
            if (subLastRequestTimestamp < flatFeePromotionStartTimestamp) {
                reqCountCalc = 1;
            } else {
                reqCountCalc = subReqCountInCurrentPeriod + 1;
            }
        }
        uint32 tierFee = subFreeRequestCount > 0
            ? 0
            : (IAdapter(adapter).getFeeTier(reqCountCalc) * flatFeePromotionGlobalPercentage / 100);
        requestFee = IAdapter(adapter).estimatePaymentAmountInETH(
            callbackGasLimit, FEE_OVERHEAD, tierFee, tx.gasprice * 3, GROUP_SIZE
        ) - subBalance;
    }

    function GetEstimateFee(uint16 playType) external view returns (uint256) {
        uint64 subId = userSubId[msg.sender];
        return _estimateFee(playType, subId) + REQUEST_FEE_OVERHEAD;
    }

    function getRandomnessThenGenerateResult(
        uint256 totalNumber,
        uint256 winnerNumber,
        uint32 callbackGasLimit,
        uint16 playType,
        uint256 callbackMaxGasPrice
    ) external returns (bytes32 requestId) {
        uint64 subId = _getAndFundSubId(playType);
        bytes memory params;
        uint256 seed = 0;
        uint16 requestConfirmations = 1;
        callbackMaxGasPrice = callbackMaxGasPrice == 0 ? tx.gasprice * 3 : callbackMaxGasPrice;
        if(callbackGasLimit == 0) {
            if (playType == TYPE_DRAW) {
                callbackGasLimit = DRAW_CALLBACK_FEE;
                requestId = _rawRequestRandomness(
                    RequestType.Randomness, params, subId, seed, requestConfirmations, callbackGasLimit, callbackMaxGasPrice
                );
            } else if (playType == TYPE_CAST) {
                callbackGasLimit = CAST_CALLBACK_FEE;
                params = abi.encode(winnerNumber);
                requestId = _rawRequestRandomness(
                    RequestType.RandomWords, params, subId, seed, requestConfirmations, callbackGasLimit, callbackMaxGasPrice
                );

            }
        }

        requestIdToRequestData[requestId] = RequestData({
            user: msg.sender,
            playType: playType,
            totalNumber: totalNumber,
            winnerNumber: winnerNumber
        });
    }

    /**
     * Callback function used by Randcast Adapter
     */
    function _fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) internal override {
        RequestData memory requestData = requestIdToRequestData[requestId];
        uint256[] memory diceResults = new uint256[](randomWords.length);
        for (uint32 i = 0; i < randomWords.length; i++) {
            diceResults[i] = RandcastSDK.roll(randomWords[i], 6) + 1;
        }
        emit PlayResult(requestData.user, requestId, diceResults);
    }

    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        RequestData memory requestData = requestIdToRequestData[requestId];
        uint256[] memory tickets = new uint256[](requestData.totalNumber);
        uint256[] memory winnerResults;
        for (uint32 i = 0; i < requestData.totalNumber; i++) {
            tickets[i] = i;
        }
        winnerResults = RandcastSDK.draw(randomness, tickets, requestData.winnerNumber);
        emit PlayResult(requestData.user, requestId, winnerResults);
    }

    function cancelSubscription() external {
        uint64 subId = userSubId[msg.sender];
        (,, uint256 balance,,,,,,) = IAdapter(adapter).getSubscription(subId);
        IAdapter(adapter).cancelSubscription(subId, msg.sender);
        payable(msg.sender).transfer(balance);
        delete userSubId[msg.sender];
    }

}
