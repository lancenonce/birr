// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ETB.sol";
import "./TestBridge.s.sol";

contract TestBridgeScript is Script {
    ETB etbContract;

    constructor(address _bridgeContractAddress) {
        etbContract = ETB(payable(_bridgeContractAddress));
    }

    function testBridge() public {
        uint destChainId = 11155111;
        address recipient = 0xa25347e4fd683dA05C849760b753a4014265254e; 
        uint amount = 22;
        address desiredOutputToken = 0x7b230BE939C5A7795938916e4F7409B5e0880F4C; 
        bool officialRate = false;

        etbContract.bridge(destChainId, recipient, amount, desiredOutputToken, officialRate);
    }

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        // Address of the deployed ETB contract
        address etbAddress = 0x7b230BE939C5A7795938916e4F7409B5e0880F4C;

        // Deploy the TestBridge contract with the ETB contract address as the constructor parameter
        etbContract = ETB(payable(etbAddress));

        // Call the testBridge function
        testBridge();

        vm.stopBroadcast();
    }
}