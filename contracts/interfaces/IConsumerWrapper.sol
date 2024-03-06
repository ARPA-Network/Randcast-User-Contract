// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IConsumerWrapper {
    function getRandomNumber(
        uint64 subId,
        bytes32 entityId,
        uint32 gasLimit,
        address callbackAddress,
        bytes4 callbackFunctionSelector
    ) external payable returns (bytes32 requestId);

    function estimateFee(uint64 subId, uint32 callbackGasLimit) external view returns (uint256 requestFee);
}
