// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "openzeppelin-contracts/contracts/utils/Create2.sol";
import {ConsumerWrapper} from "../user/ConsumerWrapper.sol";
import {IConsumerWrapper} from "../interfaces/IConsumerWrapper.sol";
import "forge-std/console.sol";

// solhint-disable-next-line max-states-count
contract DeployConsumerWrapperScript is Script {
    uint256 internal _deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
    address internal _adapterAddress = vm.envAddress("OP_ADAPTER_ADDRESS");
    address internal _deployerAdress = vm.envAddress("ADMIN_ADDRESS");

    function run() external {
        vm.startBroadcast(_deployerPrivateKey);
        bytes32 implSalt = keccak256(abi.encode("ComsumerWrapper"));
        // Deploy the ConsumerWrapper contract using Create2
        ConsumerWrapper consumerImpl = new ConsumerWrapper{salt: implSalt}();
        // comsumerImpl.setAdapterAddress(_adapterAddress);
        console.log(address(consumerImpl));

        // Compute a new unique salt for the ERC1967Proxy contract
        bytes32 proxySalt = keccak256(abi.encodePacked("ComsumerWrapperProxy"));

        // Deploy the ERC1967Proxy contract using Create2
        bytes memory data;
        ERC1967Proxy porxy = new ERC1967Proxy{salt: proxySalt}(address(consumerImpl), data);
        console.log(address(porxy));
        address(porxy).call(abi.encodeWithSignature("initialize()"));
        address(porxy).call(abi.encodeWithSignature("disableInitializers()"));
        address(porxy).call(abi.encodeWithSignature("setAdapterAddress(address)", _adapterAddress));
        vm.stopBroadcast();
    }
}
