// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRequestTypeBase} from "./IRequestTypeBase.sol";

interface IPlaygroundShareComsumer{

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

    function estimateFee(PlayType playType, uint64 subId, bytes memory params) external view returns (uint256 requestFee);

    function getRandomnessThenRollDice(uint32 bunch, uint16 requestConfirmations, uint64 subId, uint256 seed)
        external
        payable
        returns (bytes32 requestId);
    
    function getRandomnessThenDrawTickects(
        uint32 totalNumber,
        uint32 winnerNumber,
        uint64 subId,
        uint16 requestConfirmations,
        uint256 seed
    ) external payable returns (bytes32 requestId);

    function cancelSubscription() external;

    function setTrialSubscription(uint64 _trialSubId) external;

    function getTrialSubscription() external view returns (uint64);
}
