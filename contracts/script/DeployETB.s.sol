// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ETB.sol";

/// @notice Deploys ETB on the current chain.
/// forge script script/DeployETB.s.sol --rpc-url sepolia --broadcast --verify
/// Env: PRIVATE_KEY, optional POOL_MANAGER (overrides the per-chain default).
contract DeployETB is Script {
    function poolManagerFor(uint256 chainId) internal view returns (address) {
        address fromEnv = vm.envOr("POOL_MANAGER", address(0));
        if (fromEnv != address(0)) return fromEnv;
        if (chainId == 11155111) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; // Ethereum Sepolia
        if (chainId == 1301) return 0x00B036B58a818B1BC34d502D3fE730Db729e62AC; // Unichain Sepolia
        revert("DeployETB: no PoolManager for this chain; set POOL_MANAGER");
    }

    function run() external returns (ETB etb) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        IPoolManager poolManager = IPoolManager(poolManagerFor(block.chainid));

        vm.startBroadcast(pk);
        etb = new ETB(poolManager, deployer);
        vm.stopBroadcast();

        console.log("ETB deployed to:", address(etb));
    }
}
