// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap-core/interfaces/IPoolManager.sol";
import {ETB} from "../src/ETB.sol";
import {NBERateOracle} from "../src/oracle/NBERateOracle.sol";
import {NBEAttestationHelper} from "./utils/NBEAttestationHelper.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Exposes the cross-chain official payout path without standing up the VIA gateway.
contract ETBHarness is ETB {
    constructor(address initialOwner) ETB(IPoolManager(address(0)), initialOwner) {}

    function exposedOfficialPayoutOrMint(address recipient, uint256 etbAmount, address outputToken)
        external
    {
        _officialPayoutOrMint(recipient, etbAmount, outputToken);
    }
}

contract ETBTest is NBEAttestationHelper {
    ETB internal etb;
    MockUSDC internal usdc;

    address internal deployer = makeAddr("deployer"); // MESSAGE_OWNER (can testMint)
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        _deployVerifierAndOracle();
        usdc = new MockUSDC();

        vm.prank(deployer);
        etb = new ETB(IPoolManager(address(0)), owner);

        vm.startPrank(owner);
        etb.setOracle(oracle);
        etb.setUsdc(IERC20(address(usdc)));
        vm.stopPrank();

        vm.prank(deployer);
        etb.testMint(alice, 1_000_000e18);
        usdc.mint(address(etb), 100_000e6); // reserve

        _pushRate("162.8054", "161.1935");
    }

    // ------------------------------------------------------------------ math

    function test_quote_usesSellingRateAndUsdcDecimals() public view {
        (uint256 out, uint256 rate) = etb.quoteOfficial(162.8054e18);
        assertEq(rate, 162.8054e18);
        assertEq(out, 1e6); // exactly 1 USDC

        (out,) = etb.quoteOfficial(1_000e18);
        // 1000 / 162.8054 = 6.142302...
        assertEq(out, 6_142_302);
    }

    function testFuzz_quote_matchesFormula(uint96 etbAmount) public view {
        (uint256 out,) = etb.quoteOfficial(etbAmount);
        assertEq(out, uint256(etbAmount) * 1e6 / 162.8054e18);
        // Never pays more than the rate allows.
        assertLe(out * 162.8054e18, uint256(etbAmount) * 1e6);
    }

    // ------------------------------------------------------------------ swap

    function test_swap_burnsEtbAndPaysUsdc() public {
        uint256 supplyBefore = etb.totalSupply();

        vm.expectEmit(address(etb));
        emit ETB.OfficialSwap(alice, bob, 1_000e18, 6_142_302, 162.8054e18);
        vm.prank(alice);
        uint256 out = etb.swapAtOfficialRate(1_000e18, bob);

        assertEq(out, 6_142_302);
        assertEq(usdc.balanceOf(bob), 6_142_302);
        assertEq(usdc.balanceOf(address(etb)), 100_000e6 - 6_142_302);
        assertEq(etb.balanceOf(alice), 1_000_000e18 - 1_000e18);
        assertEq(etb.totalSupply(), supplyBefore - 1_000e18);
    }

    function test_swap_usesLatestRate() public {
        vm.warp(block.timestamp + 1 hours);
        _pushRate("200", "198");
        vm.prank(alice);
        uint256 out = etb.swapAtOfficialRate(200e18, alice);
        assertEq(out, 1e6);
    }

    function test_revert_swap_staleRate() public {
        (,, uint256 updatedAt) = oracle.getRate();
        vm.warp(updatedAt + 1 days + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ETB.StaleRate.selector, updatedAt));
        etb.swapAtOfficialRate(1_000e18, alice);
    }

    function test_swap_rateExactlyAtMaxAgeStillOk() public {
        (,, uint256 updatedAt) = oracle.getRate();
        vm.warp(updatedAt + 1 days);
        vm.prank(alice);
        etb.swapAtOfficialRate(1_000e18, alice);
    }

    function test_revert_swap_insufficientReserve() public {
        uint256 etbIn = 100_001e18 * 162.8054e18 / 1e18; // just over 100k USDC worth
        (uint256 needed,) = etb.quoteOfficial(etbIn);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ETB.InsufficientReserve.selector, needed, 100_000e6));
        etb.swapAtOfficialRate(etbIn, alice);
    }

    function test_revert_swap_insufficientEtb() public {
        vm.prank(bob); // has no sETB
        vm.expectRevert(); // ERC20InsufficientBalance
        etb.swapAtOfficialRate(1_000e18, bob);
    }

    function test_revert_swap_zeroAmountOrDust() public {
        vm.startPrank(alice);
        vm.expectRevert(ETB.ZeroAmount.selector);
        etb.swapAtOfficialRate(0, alice);
        vm.expectRevert(ETB.ZeroAmount.selector);
        etb.swapAtOfficialRate(1, alice); // rounds to 0 USDC
        vm.stopPrank();
    }

    function test_revert_swap_zeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(ETB.ZeroAddress.selector);
        etb.swapAtOfficialRate(1_000e18, address(0));
    }

    function test_revert_swap_notConfigured() public {
        vm.prank(deployer);
        ETB fresh = new ETB(IPoolManager(address(0)), owner);
        vm.expectRevert(ETB.OfficialRateNotConfigured.selector);
        fresh.quoteOfficial(1e18);
    }

    function test_revert_swap_noRateYet() public {
        NBERateOracle emptyOracle = new NBERateOracle(
            owner, oracle.verifier(), _defaultSpec(), 1 hours, 10e18, 10_000e18
        );
        vm.prank(owner);
        etb.setOracle(emptyOracle);
        vm.expectRevert(ETB.RateUnavailable.selector);
        etb.quoteOfficial(1e18);
    }

    // ------------------------------------------------------------------ admin

    function test_admin_onlyOwner() public {
        vm.startPrank(alice);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);
        vm.expectRevert(err);
        etb.setOracle(oracle);
        vm.expectRevert(err);
        etb.setUsdc(IERC20(address(usdc)));
        vm.expectRevert(err);
        etb.setMaxRateAge(1);
        vm.expectRevert(err);
        etb.withdrawReserve(IERC20(address(usdc)), alice, 1);
        vm.stopPrank();
    }

    function test_admin_withdrawReserve() public {
        vm.prank(owner);
        etb.withdrawReserve(IERC20(address(usdc)), owner, 40_000e6);
        assertEq(usdc.balanceOf(owner), 40_000e6);
        assertEq(usdc.balanceOf(address(etb)), 60_000e6);
    }

    function test_admin_setUsdcReadsDecimals() public view {
        assertEq(address(etb.usdc()), address(usdc));
        assertEq(etb.usdcDecimals(), 6);
    }

    function test_admin_setMaxRateAge() public {
        vm.prank(owner);
        etb.setMaxRateAge(1 hours);
        (,, uint256 updatedAt) = oracle.getRate();
        vm.warp(updatedAt + 1 hours + 1);
        vm.expectRevert(abi.encodeWithSelector(ETB.StaleRate.selector, updatedAt));
        etb.quoteOfficial(1e18);
    }

    // ------------------------------------------------------------------ cross-chain official payout

    function _harness() internal returns (ETBHarness h) {
        h = new ETBHarness(owner);
        vm.startPrank(owner);
        h.setOracle(oracle);
        h.setUsdc(IERC20(address(usdc)));
        vm.stopPrank();
        usdc.mint(address(h), 10e6);
    }

    function test_crossChain_paysUsdcWhenPossible() public {
        ETBHarness h = _harness();
        h.exposedOfficialPayoutOrMint(bob, 162.8054e18, address(usdc));
        assertEq(usdc.balanceOf(bob), 1e6);
        assertEq(h.balanceOf(bob), 0);
    }

    function test_crossChain_fallsBackToMintWhenStale() public {
        ETBHarness h = _harness();
        vm.warp(block.timestamp + 2 days);
        vm.expectEmit(address(h));
        emit ETB.OfficialSwapFallback(bob, 162.8054e18);
        h.exposedOfficialPayoutOrMint(bob, 162.8054e18, address(usdc));
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(h.balanceOf(bob), 162.8054e18);
    }

    function test_crossChain_fallsBackToMintWhenReserveShort() public {
        ETBHarness h = _harness(); // 10 USDC reserve
        h.exposedOfficialPayoutOrMint(bob, 11 * 162.8054e18, address(usdc));
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(h.balanceOf(bob), 11 * 162.8054e18);
    }

    function test_crossChain_fallsBackToMintForUnsupportedToken() public {
        ETBHarness h = _harness();
        h.exposedOfficialPayoutOrMint(bob, 1e18, makeAddr("someOtherToken"));
        assertEq(h.balanceOf(bob), 1e18);
    }
}
