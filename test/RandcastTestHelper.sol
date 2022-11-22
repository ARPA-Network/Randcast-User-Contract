// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/interfaces/IController.sol";
import "./MockController.sol";
import "./ArpaEthOracle.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract RandcastTestHelper is Test {
    MockController mockController;
    MockOracle oracle;
    IERC20 arpa;

    address public admin = address(0xABCD);
    address public user = address(0x11);
    address public node = address(0x22);

    function fulfillRequest(bytes32 requestId) internal {
        MockController.Callback memory callback = mockController
            .getPendingRequest(requestId);
        // mock confirmation times
        vm.roll(block.number + callback.requestConfirmations);

        // mock fulfillRandomness directly
        MockController.PartialSignature[] memory mockPartialSignatures;
        uint256 actualSeed = uint256(
            keccak256(abi.encodePacked(callback.seed, callback.blockNum))
        );
        mockController.fulfillRandomness(
            0,
            requestId,
            uint256(keccak256(abi.encode(actualSeed))),
            mockPartialSignatures
        );
    }

    function prepareSubscription(address consumer, uint96 balance)
        internal
        returns (uint64)
    {
        uint64 subId = mockController.createSubscription();
        mockController.fundSubscription(subId, balance);
        mockController.addConsumer(subId, consumer);
        return subId;
    }

    function getBalance(uint64 subId) internal view returns (uint96, uint96) {
        (uint96 balance, uint96 inflightCost, , , ) = mockController
            .getSubscription(subId);
        return (balance, inflightCost);
    }
}
