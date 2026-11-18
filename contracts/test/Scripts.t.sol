// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Attestation} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {PrimusZKTLS} from "@primuslabs/zktls-contracts/src/PrimusZKTLS.sol";
import {ETB} from "../src/ETB.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {PrimusJson} from "../script/lib/PrimusJson.sol";
import {Chains} from "../script/lib/Chains.sol";
import {DeployPrimusVerifier} from "../script/DeployPrimusVerifier.s.sol";
import {DeployOfficialRate} from "../script/DeployOfficialRate.s.sol";
import {NBEAttestationHelper} from "./utils/NBEAttestationHelper.sol";
import {MockUSDC} from "./ETB.t.sol";

contract ScriptsTest is NBEAttestationHelper {
    uint256 internal constant DEPLOYER_PK = 0xD3910E;

    function setUp() public {
        _deployVerifierAndOracle();
    }

    function test_specFile_matchesTestTemplate() public view {
        NBERateOracle.Spec memory s = PrimusJson.loadSpec("script/config/nbe-spec.json");
        NBERateOracle.Spec memory d = _defaultSpec();
        assertEq(s.url, d.url);
        assertEq(s.codeKey, d.codeKey);
        assertEq(s.sellingKey, d.sellingKey);
        assertEq(s.buyingKey, d.buyingKey);
        assertEq(s.resolvesHash, d.resolvesHash);
    }

    function test_attestationJson_roundTripsAndSubmits() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp));
        string memory json = _sdkJson(att);

        // Same top-level keys the Primus js-sdk returns (note Primus's "reponseResolve" spelling).
        assertTrue(vm.keyExistsJson(json, ".reponseResolve"));
        assertTrue(vm.keyExistsJson(json, ".signatures"));
        assertTrue(vm.keyExistsJson(json, ".request.url"));

        Attestation memory parsed = PrimusJson.parseAttestation(json);
        assertEq(verifier.encodeAttestation(parsed), verifier.encodeAttestation(att));
        assertEq(parsed.signatures[0], att.signatures[0]);

        oracle.submitRate(parsed);
        (uint256 selling,,) = oracle.getRate();
        assertEq(selling, 162.8054e18);
    }

    function test_deployScripts_endToEnd() public {
        MockUSDC usdc = new MockUSDC();
        address deployer = vm.addr(DEPLOYER_PK);
        usdc.mint(deployer, 500e6);

        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));
        vm.setEnv("PRIMUS_ATTESTOR", vm.toString(attestor));
        address newVerifier = new DeployPrimusVerifier().run();
        (address trusted,) = PrimusZKTLS(newVerifier)._attestors(0);
        assertEq(trusted, attestor);
        assertEq(PrimusZKTLS(newVerifier).owner(), deployer);

        vm.setEnv("PRIMUS_VERIFIER", vm.toString(newVerifier));
        vm.setEnv("USDC", vm.toString(address(usdc)));
        vm.setEnv("POOL_MANAGER", vm.toString(makeAddr("poolManager")));
        vm.setEnv("RESERVE_USDC", "300000000");
        (NBERateOracle o, ETB e) = new DeployOfficialRate().run();

        assertEq(o.owner(), deployer);
        assertEq(e.owner(), deployer);
        assertEq(address(o.verifier()), newVerifier);
        assertEq(address(e.oracle()), address(o));
        assertEq(address(e.usdc()), address(usdc));
        assertEq(e.usdcDecimals(), 6);
        assertEq(usdc.balanceOf(address(e)), 300e6);
        assertEq(o.spec().resolvesHash, _defaultSpec().resolvesHash);

        // A real-shaped attestation from the trusted attestor flows through to a swap.
        o.submitRate(_signed(_attestation("162.8054", "161.1935", block.timestamp)));
        vm.prank(e.MESSAGE_OWNER());
        e.testMint(address(this), 162.8054e18);
        e.swapAtOfficialRate(162.8054e18, address(this));
        assertEq(usdc.balanceOf(address(this)), 1e6);
    }

    /// @dev Serializes exactly like JSON.stringify() of the js-sdk Attestation object: `data`,
    ///      `attConditions` and `additionParams` are JSON *strings* (escaped), timestamp is a number.
    ///      (vm.serializeJsonType can't be used: it inlines JSON-looking strings as objects.)
    function _sdkJson(Attestation memory a) internal pure returns (string memory) {
        string memory resolves = "[";
        for (uint256 i; i < a.reponseResolve.length; ++i) {
            resolves = string.concat(
                resolves,
                i == 0 ? "" : ",",
                '{"keyName":"', a.reponseResolve[i].keyName,
                '","parseType":"', a.reponseResolve[i].parseType,
                '","parsePath":"', a.reponseResolve[i].parsePath, '"}'
            );
        }
        resolves = string.concat(resolves, "]");
        return string.concat(
            '{"recipient":"', vm.toString(a.recipient),
            '","request":{"url":"', a.request.url, '","header":"', _esc(a.request.header),
            '","method":"', a.request.method, '","body":"', _esc(a.request.body), '"}',
            ',"reponseResolve":', resolves,
            ',"data":"', _esc(a.data),
            '","attConditions":"', _esc(a.attConditions),
            '","timestamp":', vm.toString(uint256(a.timestamp)),
            ',"additionParams":"', _esc(a.additionParams),
            '","attestors":[{"attestorAddr":"', vm.toString(a.attestors[0].attestorAddr),
            '","url":"', a.attestors[0].url, '"}]',
            ',"signatures":["', vm.toString(a.signatures[0]), '"]}'
        );
    }

    function _esc(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 quotes;
        for (uint256 i; i < b.length; ++i) if (b[i] == '"') ++quotes;
        bytes memory out = new bytes(b.length + quotes);
        uint256 j;
        for (uint256 i; i < b.length; ++i) {
            if (b[i] == '"') out[j++] = "\\";
            out[j++] = b[i];
        }
        return string(out);
    }

    function test_chains_defaultPrimusAttestorIsCurrentProductionSigner() public pure {
        assertEq(Chains.PRIMUS_ATTESTOR, 0x5Ed3176045F68617B0958a61ac1868875C98C14d);
    }
}
