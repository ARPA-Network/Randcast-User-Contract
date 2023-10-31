// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRequestTypeBase} from "./IRequestTypeBase.sol";

interface ISharedConsumer {
    struct RequestData {
        PlayType playType;
        bytes param;
    }

    enum PlayType {
        Draw,
        Roll
    }

    event RollDiceRequest(
        address user,
        uint64 subId,
        bytes32 requestId,
        uint32 bunch,
        uint32 size,
        uint256 paidAmount,
        uint256 seed,
        uint16 requestConfirmations
    );

    event DrawTicketsRequest(
        address user,
        uint64 subId,
        bytes32 requestId,
        uint32 totalNumber,
        uint32 winnerNumber,
        uint256 paidAmount,
        uint256 seed,
        uint16 requestConfirmations
    );

    event RollDiceResult(bytes32 requestId, uint256[] result);
    event DrawTicketsResult(bytes32 requestId, uint256[] result);

    error InsufficientFund(uint256 fundAmount, uint256 requiredAmount);
    error InvalidSubId();
    error GasLimitTooBig(uint256 have, uint32 want);

    function estimateFee(PlayType playType, uint64 subId, bytes memory params)
        external
        view
        returns (uint256 requestFee);

    function rollDice(uint32 bunch, uint32 size, uint64 subId, uint256 seed, uint16 requestConfirmations)
        external
        payable
        returns (bytes32 requestId);

    function drawTickets(
        uint32 totalNumber,
        uint32 winnerNumber,
        uint64 subId,
        uint256 seed,
        uint16 requestConfirmations
    ) external payable returns (bytes32 requestId);

    function cancelSubscription() external;

    function setTrialSubscription(uint64 _trialSubId) external;

    function getTrialSubscription() external view returns (uint64);
}
