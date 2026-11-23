// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPrimusZKTLS} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {IPoolManager} from "@uniswap-core/interfaces/IPoolManager.sol";
import {ETB} from "../src/ETB.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {Chains} from "./lib/Chains.sol";
import {PrimusJson} from "./lib/PrimusJson.sol";

/// @notice Deploys NBERateOracle + ETB, wires them together and optionally funds the USDC reserve.
///
/// forge script script/DeployOfficialRate.s.sol --rpc-url sepolia --broadcast --verify
/// Env:
///   PRIVATE_KEY          deployer; becomes owner of both contracts
///   PRIMUS_VERIFIER      IPrimusZKTLS address (see DeployPrimusVerifier)
///   SPEC_FILE            optional, default script/config/nbe-spec.json
///   MAX_ATTESTATION_AGE  optional seconds, default 3600
///   MIN_RATE / MAX_RATE  optional, 1e18-scaled ETB per USD, default 10e18 / 10_000e18
///   USDC                 optional, default Circle Sepolia USDC
///   RESERVE_USDC         optional amount (USDC base units) to transfer from deployer into ETB
///   POOL_MANAGER         optional Uniswap v4 PoolManager override
contract DeployOfficialRate is Script {
    function run() external returns (NBERateOracle oracle, ETB etb) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        IPrimusZKTLS verifier = IPrimusZKTLS(vm.envAddress("PRIMUS_VERIFIER"));
        NBERateOracle.Spec memory spec =
            PrimusJson.loadSpec(vm.envOr("SPEC_FILE", string("script/config/nbe-spec.json")));
        IERC20 usdc = IERC20(Chains.usdc());
        uint256 reserve = vm.envOr("RESERVE_USDC", uint256(0));

        vm.startBroadcast(pk);
        oracle = new NBERateOracle(
            deployer,
            verifier,
            spec,
            vm.envOr("MAX_ATTESTATION_AGE", uint256(1 hours)),
            vm.envOr("MIN_RATE", uint256(10e18)),
            vm.envOr("MAX_RATE", uint256(10_000e18))
        );
        etb = new ETB(IPoolManager(Chains.poolManager()), deployer);
        etb.setOracle(oracle);
        etb.setUsdc(usdc);
        if (reserve > 0) usdc.transfer(address(etb), reserve);
        vm.stopBroadcast();

        console.log("NBERateOracle:", address(oracle));
        console.log("ETB:", address(etb));
        console.log("Verifier:", address(verifier));
        console.log("USDC reserve funded:", reserve);
    }
}
