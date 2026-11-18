// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {PrimusJson} from "./lib/PrimusJson.sol";

/// @notice Re-points the oracle at a (possibly edited) template spec, e.g. once the real Primus template's
///         keyNames / parseType / parsePaths are known. Edit script/config/nbe-spec.json, then run:
/// forge script script/ConfigureOracleSpec.s.sol --rpc-url sepolia --broadcast
/// Env: PRIVATE_KEY (oracle owner), ORACLE_ADDRESS, optional SPEC_FILE.
contract ConfigureOracleSpec is Script {
    function run() external {
        NBERateOracle oracle = NBERateOracle(vm.envAddress("ORACLE_ADDRESS"));
        NBERateOracle.Spec memory spec =
            PrimusJson.loadSpec(vm.envOr("SPEC_FILE", string("script/config/nbe-spec.json")));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        oracle.setSpec(spec);
        vm.stopBroadcast();

        console.log("Spec updated. url:", spec.url);
        console.logBytes32(spec.resolvesHash);
    }
}
