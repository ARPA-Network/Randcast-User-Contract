// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SharedConsumerContract} from "../user/SharedConsumer.sol";
import {ISharedConsumer} from "../interfaces/ISharedConsumer.sol";

// solhint-disable-next-line max-states-count
contract DeploySharedConsumerScript is Script {
    uint256 internal _deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
    address internal _adapterAddress = vm.envAddress("OP_ADAPTER_ADDRESS");
    uint256 internal _userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    uint64 internal _subId = uint64(vm.envUint("TRIAL_SUB_ID"));

    function run() external {
        vm.startBroadcast(_deployerPrivateKey);
        SharedConsumerContract _shareConsumerImpl = new SharedConsumerContract(address(_adapterAddress));

        ERC1967Proxy _shareConsumer =
            new ERC1967Proxy(address(_shareConsumerImpl),abi.encodeWithSignature("initialize()"));

        IAdapter _adapter = IAdapter(_adapterAddress);
        _adapter.addConsumer(_subId, address(_shareConsumer));

        ISharedConsumer consumerInstance = ISharedConsumer(address(_shareConsumer));
        consumerInstance.setTrialSubscription(_subId);
        vm.stopBroadcast();

        vm.broadcast(_userPrivateKey);
        consumerInstance.rollDice(1, 6, _subId, 0, 6);
        
    }
}
