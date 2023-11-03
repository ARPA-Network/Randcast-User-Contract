// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISharedConsumer {
    enum PlayType {
        Draw,
        Roll
    }

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
