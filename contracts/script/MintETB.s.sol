// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ETB.sol";

/// Env: PRIVATE_KEY, ETB_ADDRESS, MINT_TO, MINT_AMOUNT (whole tokens, default 100000).
contract MintETB is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        ETB etb = ETB(payable(vm.envAddress("ETB_ADDRESS")));
        address to = vm.envOr("MINT_TO", vm.addr(pk));
        uint256 amount = vm.envOr("MINT_AMOUNT", uint256(100_000)) * 1e18;

        vm.startBroadcast(pk);
        etb.testMint(to, amount);
        vm.stopBroadcast();
    }
}
