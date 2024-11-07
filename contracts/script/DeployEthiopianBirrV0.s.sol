// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/solvent_token/EthiopianBirrV0.sol";
import "../src/solvent_token/EthiopianBirrProxy.sol";

contract DeployEthiopianBirrV0 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        EthiopianBirrV0 ethiopianBirrImplementation = new EthiopianBirrV0();

        ethiopianBirrImplementation.setOwner(deployerAddress);

        bytes memory initializeData = abi.encodeWithSignature(
            "initialize(string,string,uint8,uint256)",
            "Ethiopian Birr",
            "sETB",
            18,
            1000000000
        );

        EthiopianBirrProxy proxy = new EthiopianBirrProxy(
            address(ethiopianBirrImplementation),
            initializeData
        );

        console.log(
            "EthiopianBirrV0 Implementation deployed at:",
            address(ethiopianBirrImplementation)
        );
        console.log("EthiopianBirr Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
