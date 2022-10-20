// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "./RequestTypeBase.sol";

interface IController is RequestTypeBase {
    struct PartialSignature {
        uint256 nodeAddress;
        uint256 partialSignature;
    }

    event RandomnessRequest(
        uint256 seed,
        uint256 indexed groupIndex,
        bytes32 requestID,
        address sender
    );

    event RandomnessRequestFulfilled(bytes32 requestId, uint256 output);

    function requestRandomness(
        RequestType requestType,
        bytes memory params,
        uint256 seed
    ) external returns (bytes32);

    function fulfillRandomness(
        uint256 groupIndex,
        bytes32 requestId,
        uint256 signature,
        PartialSignature[] calldata partialSignatures
    ) external;
}
