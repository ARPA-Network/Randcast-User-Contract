// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {IRequestTypeBase} from "./IRequestTypeBase.sol";

interface IConsumerWrapper is IRequestTypeBase {
    function getRandomness(
        uint64 subId,
        bytes32 entityId,
        uint32 gasLimit,
        address callbackAddress
    ) external payable returns (bytes32 requestId);
    
    function getRandomWords( 
        uint64 subId,
        bytes32 entityId,
        uint32 size,
        uint32 callbackGasLimit,
        address callbackAddress
    ) external payable returns (bytes32 requestId);

    function getShuffleArray(
        uint64 subId,
        bytes32 entityId,
        uint32 upper,
        uint32 callbackGasLimit,
        address callbackAddress
    ) external payable returns (bytes32 requestId);

    function estimateFee(
        RequestType requestType,
        uint64 subId,
        bytes memory params,
        uint32 callbackGasLimit
    ) external view returns (uint256 requestFee);
}
