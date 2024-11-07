// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/ETB.sol";

contract MintETB is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        address etbAddress = 0x7b230BE939C5A7795938916e4F7409B5e0880F4C; 

        ETB etb = ETB(payable(etbAddress));

        address recipient = 0xa25347e4fd683dA05C849760b753a4014265254e; 
        uint256 amount = 100000 * 10**18; 

        etb.testMint(recipient, amount);

        vm.stopBroadcast();
    }
}