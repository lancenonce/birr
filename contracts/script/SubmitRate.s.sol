// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Attestation} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {PrimusJson} from "./lib/PrimusJson.sol";

/// @notice Submits a saved Primus attestation (the JSON object returned by zktls-js-sdk startAttestation)
///         to the oracle. Useful for smoke tests and for relaying an attestation produced elsewhere.
/// forge script script/SubmitRate.s.sol --rpc-url sepolia --broadcast
/// Env: PRIVATE_KEY, ORACLE_ADDRESS, ATTESTATION_FILE.
contract SubmitRate is Script {
    function run() external {
        NBERateOracle oracle = NBERateOracle(vm.envAddress("ORACLE_ADDRESS"));
        Attestation memory att = PrimusJson.parseAttestation(vm.readFile(vm.envString("ATTESTATION_FILE")));
        console.log("Attestation data:", att.data);
        console.log("Attested at (ms):", uint256(att.timestamp));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        oracle.submitRate(att);
        vm.stopBroadcast();

        (uint256 selling, uint256 buying, uint256 updatedAt) = oracle.getRate();
        console.log("selling (1e18):", selling);
        console.log("buying  (1e18):", buying);
        console.log("updatedAt:", updatedAt);
    }
}
