// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConsumerWrapper} from "../user/ConsumerWrapper.sol";
import {IConsumerWrapper} from "../interfaces/IConsumerWrapper.sol";

// solhint-disable-next-line max-states-count
contract DeploySharedConsumerScript is Script {
    uint256 internal _deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
    address internal _adapterAddress = vm.envAddress("OP_ADAPTER_ADDRESS");

    function run() external {
        vm.startBroadcast(_deployerPrivateKey);
        ConsumerWrapper _consumerWrapper = new ConsumerWrapper(address(_adapterAddress));

        new ERC1967Proxy(address(_consumerWrapper),abi.encodeWithSignature("initialize()"));

        vm.stopBroadcast();
    }
}
