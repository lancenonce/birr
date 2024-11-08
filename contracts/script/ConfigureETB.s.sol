// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/ETB.sol";

contract ConfigureETB is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        string[] memory networks = new string[](2);
        networks[0] = "ethereum";
        networks[1] = "unichain";

        address[] memory addresses = new address[](networks.length);
        uint256[] memory chainIds = new uint256[](networks.length);
        uint16[] memory confirmations = new uint16[](networks.length);

        for (uint256 i = 0; i < networks.length; i++) {
            string memory etbPath = string(
                abi.encodePacked("deployments/", networks[i], "/ETB.json")
            );
            string memory chainIdPath = string(
                abi.encodePacked("deployments/", networks[i], "/.chainId")
            );

            // Read the ETB address and chain ID from the file system
            string memory etbJson = vm.readFile(etbPath);
            string memory chainIdStr = vm.readFile(chainIdPath);

            // Parse the JSON to get the ETB address
            address etbAddress = abi.decode(
                vm.parseJson(etbJson, ".address"),
                (address)
            );
            addresses[i] = etbAddress;

            chainIds[i] = vm.parseUint(chainIdStr);

            confirmations[i] = 1;

            // is this another contract?
            address messageGateway = etbAddress;

            // Get the ETB contract instance
            ETB etb = ETB(payable(etbAddress));

            etb.configureClient(
                messageGateway,
                chainIds,
                addresses,
                confirmations
            );
        }


        vm.stopBroadcast();
    }
}
