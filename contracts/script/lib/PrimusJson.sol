// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {
    Attestation,
    AttNetworkResponseResolve
} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {NBERateOracle} from "../../src/oracle/NBERateOracle.sol";

/// @notice JSON <-> struct helpers for Primus attestations and the oracle Spec, for scripts and tests.
/// @dev The attestation JSON is exactly what `@primuslabs/zktls-js-sdk` returns from startAttestation().
library PrimusJson {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant RESOLVE_TYPE =
        "AttNetworkResponseResolve(string keyName,string parseType,string parsePath)";

    // EIP-712-style type description: primary type, then referenced types sorted by name.
    string internal constant ATTESTATION_TYPE =
        "Attestation(address recipient,AttNetworkRequest request,AttNetworkResponseResolve[] reponseResolve,"
        "string data,string attConditions,uint64 timestamp,string additionParams,Attestor[] attestors,"
        "bytes[] signatures)"
        "AttNetworkRequest(string url,string header,string method,string body)"
        "AttNetworkResponseResolve(string keyName,string parseType,string parsePath)"
        "Attestor(address attestorAddr,string url)";

    function parseAttestation(string memory json) internal pure returns (Attestation memory) {
        return abi.decode(vm.parseJsonType(json, ATTESTATION_TYPE), (Attestation));
    }

    /// @notice Loads script/config/nbe-spec.json (or another file with the same shape) into an oracle Spec.
    function loadSpec(string memory path) internal view returns (NBERateOracle.Spec memory spec) {
        string memory json = vm.readFile(path);
        AttNetworkResponseResolve[] memory resolves = abi.decode(
            vm.parseJsonTypeArray(json, ".resolves", RESOLVE_TYPE), (AttNetworkResponseResolve[])
        );
        spec = NBERateOracle.Spec({
            url: vm.parseJsonString(json, ".url"),
            codeKey: vm.parseJsonString(json, ".codeKey"),
            sellingKey: vm.parseJsonString(json, ".sellingKey"),
            buyingKey: vm.parseJsonString(json, ".buyingKey"),
            resolvesHash: keccak256(abi.encode(resolves))
        });
    }
}
