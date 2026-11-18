// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ETB.sol";
import {Chains} from "./lib/Chains.sol";

/// @notice Deploys a bare ETB on the current chain (no oracle wiring; see DeployOfficialRate for that).
/// forge script script/DeployETB.s.sol --rpc-url sepolia --broadcast --verify
/// Env: PRIVATE_KEY, optional POOL_MANAGER.
contract DeployETB is Script {
    function run() external returns (ETB etb) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        etb = new ETB(IPoolManager(Chains.poolManager()), vm.addr(pk));
        vm.stopBroadcast();
        console.log("ETB deployed to:", address(etb));
    }
}
