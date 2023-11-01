// SPDX-License-Identifier: MITlength
pragma solidity ^0.8.18;

import {GeneralRandcastConsumerBase, BasicRandcastConsumerBase} from "../GeneralRandcastConsumerBase.sol";
// solhint-disable-next-line no-global-import
import "../RandcastSDK.sol" as RandcastSDK;

contract DrawIndicesExample is GeneralRandcastConsumerBase {
    mapping(bytes32 => bytes) public drawRequests;
    mapping(bytes32 => uint256[]) public winningResults;

    event DrawIndicesRequest(bytes32 indexed requestId, uint32 totalSize, uint32 winningSize);
    event DrawIndicesResult(bytes32 indexed requestId, uint256[] winningResults);

    error TotalSizeMustBeGreaterThanOrEqualToWinningSize();
    error WinningSizeMustBeGreaterThanZero();

    // solhint-disable-next-line no-empty-blocks
    constructor(address adapter) BasicRandcastConsumerBase(adapter) {}

    /**
     * Requests randomness
     */
    function drawIndices(uint32 totalSize, uint32 winningSize) external returns (bytes32 requestId) {
        if (totalSize < winningSize) {
            revert TotalSizeMustBeGreaterThanOrEqualToWinningSize();
        }
        if (winningSize == 0) {
            revert WinningSizeMustBeGreaterThanZero();
        }

        bytes memory params;
        requestId = _requestRandomness(RequestType.Randomness, params);

        bytes memory requestParams = abi.encode(totalSize, winningSize);
        drawRequests[requestId] = requestParams;

        emit DrawIndicesRequest(requestId, totalSize, winningSize);
    }

    /**
     * Callback function used by Randcast Adapter
     */
    function _fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        bytes memory requestData = drawRequests[requestId];
        (uint32 totalSize, uint32 winningSize) = abi.decode(requestData, (uint32, uint32));
        uint256[] memory indices = new uint256[](totalSize);
        for (uint32 i = 0; i < totalSize; i++) {
            indices[i] = i;
        }
        winningResults[requestId] = RandcastSDK.draw(randomness, indices, winningSize);

        emit DrawIndicesResult(requestId, winningResults[requestId]);
    }

    function getWinningResults(bytes32 requestId) external view returns (uint256[] memory) {
        return winningResults[requestId];
    }
}
