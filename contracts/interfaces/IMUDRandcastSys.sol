// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRandcastSys {
     function fulfillRandomness(bytes32 requestId, uint256 randomness, bytes32 entityId) external;
}
