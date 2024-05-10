// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SharedConsumer} from "../user/SharedConsumer.sol";
import {ISharedConsumer} from "../interfaces/ISharedConsumer.sol";
import "forge-std/console.sol";

// solhint-disable-next-line max-states-count
contract CreateAndFundSubId is Script {
    uint256 internal _deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
    address internal _adapterAddress = vm.envAddress("OP_ADAPTER_ADDRESS");

    function run() external {
        vm.startBroadcast(_deployerPrivateKey);

        IAdapter _adapter = IAdapter(_adapterAddress);
        console.log("SubId: ", _adapter.getCurrentSubId());
        uint64 _subId = _adapter.createSubscription();
        console.log("SubId: ", _subId);
        _adapter.fundSubscription{value: 0.2 ether}(_subId);
        vm.stopBroadcast();
    }
}

