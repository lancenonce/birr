// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/EthiopianBirrV0.sol";
import "../src/EthiopianBirrProxy.sol";

contract DeployEthiopianBirrV0 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        EthiopianBirrV0 ethiopianBirrImplementation = new EthiopianBirrV0();

        bytes memory initializeData = abi.encodeWithSignature(
            "initialize(string,string,uint8,uint256,address)",
            "Ethiopian Birr",   
            "sETB",             
            18,                 
            1000000000,        
            msg.sender         
        );

        EthiopianBirrProxy proxy = new EthiopianBirrProxy(
            address(ethiopianBirrImplementation),
            initializeData
        );

        console.log("EthiopianBirrV0 Implementation deployed at:", address(ethiopianBirrImplementation));
        console.log("EthiopianBirr Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}