// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IController.sol";

abstract contract RandcastConsumerBase is RequestTypeBase {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public arpa;

    address public immutable controller;

    uint256 public nonce;

    uint256 public requestFee = 200 * 10**18;

    constructor(address _controller, address _arpa) {
        controller = _controller;
        arpa = IERC20(_arpa);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        virtual
    {}

    function fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords)
        internal
        virtual
    {}

    function fulfillShuffledArray(
        bytes32 requestId,
        uint256[] memory shuffledArray
    ) internal virtual {}

    function requestRandomness(
        RequestType requestType,
        bytes memory params,
        uint256 seed
    ) internal returns (bytes32 requestId) {
        // mock fee charge which is extremely simple
        arpa.safeTransfer(controller, requestFee);
        nonce = nonce + 1;
        return
            IController(controller).requestRandomness(
                requestType,
                params,
                seed
            );
    }

    function rawFulfillRandomness(bytes32 requestId, uint256 randomness)
        external
    {
        require(msg.sender == controller, "Only controller can fulfill");
        fulfillRandomness(requestId, randomness);
    }

    function rawFulfillRandomWords(
        bytes32 requestId,
        uint256[] memory randomWords
    ) external {
        require(msg.sender == controller, "Only controller can fulfill");
        fulfillRandomWords(requestId, randomWords);
    }

    function rawFulfillShuffledArray(
        bytes32 requestId,
        uint256[] memory shuffledArray
    ) external {
        require(msg.sender == controller, "Only controller can fulfill");
        fulfillShuffledArray(requestId, shuffledArray);
    }
}
