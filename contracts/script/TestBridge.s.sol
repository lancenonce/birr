// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ETB.sol";

/// Env: PRIVATE_KEY, ETB_ADDRESS, DEST_CHAIN_ID, BRIDGE_AMOUNT (wei),
///      optional BRIDGE_RECIPIENT, DESIRED_OUTPUT_TOKEN, OFFICIAL_RATE.
contract TestBridge is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        ETB etb = ETB(payable(vm.envAddress("ETB_ADDRESS")));

        vm.startBroadcast(pk);
        etb.bridge(
            vm.envUint("DEST_CHAIN_ID"),
            vm.envOr("BRIDGE_RECIPIENT", vm.addr(pk)),
            vm.envUint("BRIDGE_AMOUNT"),
            vm.envOr("DESIRED_OUTPUT_TOKEN", address(etb)),
            vm.envOr("OFFICIAL_RATE", false)
        );
        vm.stopBroadcast();
    }
}
