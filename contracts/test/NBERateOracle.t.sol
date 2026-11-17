// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IPrimusZKTLS,
    Attestation,
    AttNetworkResponseResolve
} from "@primuslabs/zktls-contracts/src/IPrimusZKTLS.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {DecimalParser} from "../src/lib/DecimalParser.sol";
import {NBEAttestationHelper} from "./utils/NBEAttestationHelper.sol";

contract NBERateOracleTest is NBEAttestationHelper {
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        _deployVerifierAndOracle();
    }

    // ------------------------------------------------------------------ happy path

    function test_submitRate_storesRate() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp));

        vm.expectEmit(address(oracle));
        emit NBERateOracle.RateUpdated(162.8054e18, 161.1935e18, uint64(block.timestamp), relayer);
        vm.prank(relayer);
        oracle.submitRate(att);

        (uint256 selling, uint256 buying, uint256 updatedAt) = oracle.getRate();
        assertEq(selling, 162.8054e18);
        assertEq(buying, 161.1935e18);
        assertEq(updatedAt, block.timestamp);
        assertEq(oracle.lastAttestationTimestampMs(), block.timestamp * 1000);
    }

    function test_submitRate_acceptsSlightlyOldAndSlightlyFuture() public {
        oracle.submitRate(_signed(_attestation("150", "149", block.timestamp - 59 minutes)));
        oracle.submitRate(_signed(_attestation("151", "150", block.timestamp + 4 minutes)));
        (uint256 selling,,) = oracle.getRate();
        assertEq(selling, 151e18);
    }

    function test_submitRate_newerAttestationOverwrites() public {
        _pushRate("162.8054", "161.1935");
        vm.warp(block.timestamp + 1 days);
        _pushRate("170", "168.5");
        (uint256 selling, uint256 buying,) = oracle.getRate();
        assertEq(selling, 170e18);
        assertEq(buying, 168.5e18);
    }

    function test_submitRate_toleratesKeyOrderSpacingAndUnquotedNumbers() public {
        // The exact `data` serialization from Primus is unconfirmed; make sure common variants parse.
        Attestation memory att = _attestation("0", "0", block.timestamp);
        att.data = '{"buying": 161.1935, "code": "USD", "selling": "162.8054"}';
        oracle.submitRate(_signed(att));
        (uint256 selling, uint256 buying,) = oracle.getRate();
        assertEq(selling, 162.8054e18);
        assertEq(buying, 161.1935e18);
    }

    // ------------------------------------------------------------------ signature

    function test_revert_unregisteredSigner() public {
        Attestation memory att = _sign(_attestation("162.8054", "161.1935", block.timestamp), 0xBAD);
        vm.expectRevert("Invalid signature");
        oracle.submitRate(att);
    }

    function test_revert_dataTamperedAfterSigning() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp));
        att.data = _data("USD", "1.0", "1.0");
        vm.expectRevert("Invalid signature");
        oracle.submitRate(att);
    }

    function test_revert_noSignature() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.signatures = new bytes[](0);
        vm.expectRevert("Invalid signature length");
        oracle.submitRate(att);
    }

    // ------------------------------------------------------------------ spec pinning (validly signed, wrong content)

    function test_revert_wrongUrl() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.request.url = "https://evil.example/api/get-selected-exchange-rates";
        att = _signed(att);
        vm.expectRevert(NBERateOracle.WrongUrl.selector);
        oracle.submitRate(att);
    }

    function test_revert_urlWithExtraQuery() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.request.url = string.concat(NBE_URL, "?date=2020-01-01");
        att = _signed(att);
        vm.expectRevert(NBERateOracle.WrongUrl.selector);
        oracle.submitRate(att);
    }

    function test_revert_wrongMethod() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.request.method = "POST";
        att = _signed(att);
        vm.expectRevert(NBERateOracle.WrongMethod.selector);
        oracle.submitRate(att);
    }

    function test_revert_wrongParsePath() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        // Points "selling" at EUR (data[1]) instead of USD.
        att.reponseResolve[1].parsePath = "$.data[1].selling";
        att = _signed(att);
        vm.expectRevert(NBERateOracle.WrongResolves.selector);
        oracle.submitRate(att);
    }

    function test_revert_extraResolve() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        AttNetworkResponseResolve[] memory r = new AttNetworkResponseResolve[](4);
        for (uint256 i; i < 3; ++i) r[i] = att.reponseResolve[i];
        r[3] = AttNetworkResponseResolve("date", PARSE_TYPE, "$.data[0].date");
        att.reponseResolve = r;
        att = _signed(att);
        vm.expectRevert(NBERateOracle.WrongResolves.selector);
        oracle.submitRate(att);
    }

    function test_revert_notUSD() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.data = _data("EUR", "190.1", "188.2");
        att = _signed(att);
        vm.expectRevert(NBERateOracle.NotUSD.selector);
        oracle.submitRate(att);
    }

    function test_revert_missingKeyInData() public {
        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.data = '{"code":"USD","selling":"162.8054"}';
        att = _signed(att);
        vm.expectRevert(DecimalParser.EmptyDecimal.selector);
        oracle.submitRate(att);
    }

    function test_revert_malformedRate() public {
        Attestation memory att = _signed(_attestation("162,8054", "161.1935", block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 3));
        oracle.submitRate(att);
    }

    // ------------------------------------------------------------------ freshness / replay

    function test_revert_stale() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp - 61 minutes));
        vm.expectRevert(NBERateOracle.StaleAttestation.selector);
        oracle.submitRate(att);
    }

    function test_revert_tooFarInFuture() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp + 6 minutes));
        vm.expectRevert(NBERateOracle.FutureAttestation.selector);
        oracle.submitRate(att);
    }

    function test_revert_replay() public {
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp));
        oracle.submitRate(att);
        vm.expectRevert(NBERateOracle.NotNewer.selector);
        oracle.submitRate(att);
    }

    function test_revert_olderThanCurrent() public {
        _pushRate("162.8054", "161.1935");
        Attestation memory older = _signed(_attestation("100", "99", block.timestamp - 10 minutes));
        vm.expectRevert(NBERateOracle.NotNewer.selector);
        oracle.submitRate(older);
    }

    // ------------------------------------------------------------------ sanity bounds

    function test_revert_rateBelowMin() public {
        Attestation memory att = _signed(_attestation("9.99", "9.5", block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(NBERateOracle.RateOutOfBounds.selector, 9.99e18));
        oracle.submitRate(att);
    }

    function test_revert_rateAboveMax() public {
        Attestation memory att = _signed(_attestation("10000.01", "160", block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(NBERateOracle.RateOutOfBounds.selector, 10_000.01e18));
        oracle.submitRate(att);
    }

    function test_revert_sellingBelowBuying() public {
        Attestation memory att = _signed(_attestation("160", "161", block.timestamp));
        vm.expectRevert(NBERateOracle.SellingBelowBuying.selector);
        oracle.submitRate(att);
    }

    // ------------------------------------------------------------------ admin

    function test_admin_onlyOwner() public {
        address stranger = makeAddr("stranger");
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setVerifier(IPrimusZKTLS(address(1)));
        NBERateOracle.Spec memory s = _defaultSpec();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setSpec(s);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setParams(1, 1, 2);
        vm.stopPrank();
    }

    function test_admin_setSpecChangesAcceptedTemplate() public {
        AttNetworkResponseResolve[] memory r = _resolves();
        r[0].parseType = "json";
        NBERateOracle.Spec memory s = _defaultSpec();
        s.resolvesHash = oracle.hashResolves(r);
        vm.prank(owner);
        oracle.setSpec(s);

        Attestation memory att = _attestation("162.8054", "161.1935", block.timestamp);
        att.reponseResolve = r;
        oracle.submitRate(_signed(att));
        (uint256 selling,,) = oracle.getRate();
        assertEq(selling, 162.8054e18);
    }

    function test_admin_setVerifierToUntrustedVerifierBlocksUpdates() public {
        // A verifier that trusts nobody we can sign for.
        Attestation memory att = _signed(_attestation("162.8054", "161.1935", block.timestamp));
        RejectAll rejectAll = new RejectAll();
        vm.prank(owner);
        oracle.setVerifier(IPrimusZKTLS(address(rejectAll)));
        vm.expectRevert("rejected");
        oracle.submitRate(att);
    }

    function test_admin_invalidParamsRevert() public {
        vm.startPrank(owner);
        vm.expectRevert(NBERateOracle.InvalidParams.selector);
        oracle.setParams(0, 1, 2);
        vm.expectRevert(NBERateOracle.InvalidParams.selector);
        oracle.setParams(1 hours, 5, 5);
        vm.expectRevert(NBERateOracle.InvalidParams.selector);
        oracle.setVerifier(IPrimusZKTLS(address(0)));
        NBERateOracle.Spec memory s = _defaultSpec();
        s.url = "";
        vm.expectRevert(NBERateOracle.InvalidParams.selector);
        oracle.setSpec(s);
        vm.stopPrank();
    }
}

contract RejectAll {
    function verifyAttestation(Attestation calldata) external pure {
        revert("rejected");
    }
}
