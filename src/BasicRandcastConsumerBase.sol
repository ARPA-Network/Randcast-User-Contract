// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "./interfaces/IController.sol";
import "./RequestIdBase.sol";

/**
 * @notice Interface for contracts using VRF randomness.
 * @notice Extends this and overrides particular fulfill callback function to use randomness safely.
 */
abstract contract BasicRandcastConsumerBase is RequestTypeBase {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public arpa;

    address public immutable controller;
    // Nonce on the user's side for generating real requestId, which should be identical to the nonce on controller's side, or it will be pointless.
    uint256 public nonce;
    // TODO change this into subscription pattern to allow user to pay the gas for actually used.
    uint256 public requestFee = 200 * 10**18;
    // Ignore fulfilling from controller check during fee estimation.
    bool isEstimatingCallbackGasLimit;

    modifier calculateCallbackGasLimit() {
        isEstimatingCallbackGasLimit = true;
        _;
        isEstimatingCallbackGasLimit = false;
    }

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

    function rawRequestRandomness(
        RequestType requestType,
        bytes memory params,
        uint256 seed,
        uint16 requestConfirmations,
        uint256 callbackGasLimit
    ) internal returns (bytes32) {
        // mock fee charge which is extremely simple
        arpa.safeTransfer(controller, requestFee);
        nonce = nonce + 1;
        return
            IController(controller).requestRandomness(
                requestType,
                params,
                seed,
                requestConfirmations,
                callbackGasLimit
            );
    }

    function rawFulfillRandomness(bytes32 requestId, uint256 randomness)
        external
    {
        require(
            isEstimatingCallbackGasLimit || msg.sender == controller,
            "Only controller can fulfill"
        );
        fulfillRandomness(requestId, randomness);
    }

    function rawFulfillRandomWords(
        bytes32 requestId,
        uint256[] memory randomWords
    ) external {
        require(
            isEstimatingCallbackGasLimit || msg.sender == controller,
            "Only controller can fulfill"
        );
        fulfillRandomWords(requestId, randomWords);
    }

    function rawFulfillShuffledArray(
        bytes32 requestId,
        uint256[] memory shuffledArray
    ) external {
        require(
            isEstimatingCallbackGasLimit || msg.sender == controller,
            "Only controller can fulfill"
        );
        fulfillShuffledArray(requestId, shuffledArray);
    }
}
