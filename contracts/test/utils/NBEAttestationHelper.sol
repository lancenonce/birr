// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PrimusZKTLS} from "@primuslabs/zktls-contracts/src/PrimusZKTLS.sol";
import {
    IPrimusZKTLS,
    Attestation,
    AttNetworkRequest,
    AttNetworkResponseResolve,
    Attestor
} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {NBERateOracle} from "../../src/oracle/NBERateOracle.sol";

/// @notice Shared setup: a real PrimusZKTLS verifier (behind a proxy, like production) whose attestor key we
///         control, plus helpers to build and sign NBE attestations exactly as the Primus attestor would.
abstract contract NBEAttestationHelper is Test {
    string internal constant NBE_URL = "https://api.nbe.gov.et/api/get-selected-exchange-rates";
    string internal constant PARSE_TYPE = "JSON";

    uint256 internal constant ATTESTOR_PK = 0xA77E57;
    uint256 internal constant START_TIME = 1_763_000_000; // Nov 2025

    address internal owner = makeAddr("owner");
    address internal attestor;
    PrimusZKTLS internal verifier;
    NBERateOracle internal oracle;

    function _deployVerifierAndOracle() internal {
        vm.warp(START_TIME);
        attestor = vm.addr(ATTESTOR_PK);

        Attestor[] memory attestors = new Attestor[](1);
        attestors[0] = Attestor({attestorAddr: attestor, url: "https://primuslabs.xyz"});
        PrimusZKTLS impl = new PrimusZKTLS();
        verifier = PrimusZKTLS(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeCall(PrimusZKTLS.initialize, (owner, attestors))
                )
            )
        );

        oracle = new NBERateOracle(
            owner,
            IPrimusZKTLS(address(verifier)),
            _defaultSpec(),
            1 hours,
            10e18, // min 10 ETB/USD
            10_000e18 // max 10,000 ETB/USD
        );
    }

    function _resolves() internal pure returns (AttNetworkResponseResolve[] memory r) {
        r = new AttNetworkResponseResolve[](3);
        r[0] = AttNetworkResponseResolve("code", PARSE_TYPE, "$.data[0].currency.code");
        r[1] = AttNetworkResponseResolve("selling", PARSE_TYPE, "$.data[0].selling");
        r[2] = AttNetworkResponseResolve("buying", PARSE_TYPE, "$.data[0].buying");
    }

    function _defaultSpec() internal pure returns (NBERateOracle.Spec memory) {
        return NBERateOracle.Spec({
            url: NBE_URL,
            codeKey: "code",
            sellingKey: "selling",
            buyingKey: "buying",
            resolvesHash: keccak256(abi.encode(_resolves()))
        });
    }

    function _data(string memory code, string memory selling, string memory buying)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"code":"', code, '","selling":"', selling, '","buying":"', buying, '"}'
        );
    }

    /// @notice An unsigned attestation for USD at the given rates, timestamped `tsSec` (seconds).
    function _attestation(string memory selling, string memory buying, uint256 tsSec)
        internal
        pure
        returns (Attestation memory att)
    {
        att.recipient = address(0xBEEF);
        att.request = AttNetworkRequest({url: NBE_URL, header: "", method: "GET", body: ""});
        att.reponseResolve = _resolves();
        att.data = _data("USD", selling, buying);
        att.attConditions = "";
        att.timestamp = uint64(tsSec * 1000);
        att.additionParams = "";
        att.attestors = new Attestor[](1);
        att.attestors[0] = Attestor({attestorAddr: vm.addr(ATTESTOR_PK), url: "https://primuslabs.xyz"});
    }

    function _sign(Attestation memory att, uint256 pk) internal view returns (Attestation memory) {
        bytes32 digest = verifier.encodeAttestation(att);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        att.signatures = new bytes[](1);
        att.signatures[0] = abi.encodePacked(r, s, v);
        return att;
    }

    function _signed(Attestation memory att) internal view returns (Attestation memory) {
        return _sign(att, ATTESTOR_PK);
    }

    /// @notice Convenience: submit a fresh, valid attestation at the current block time.
    function _pushRate(string memory selling, string memory buying) internal {
        oracle.submitRate(_signed(_attestation(selling, buying, block.timestamp)));
    }
}
