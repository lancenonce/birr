// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DecimalParser} from "../src/lib/DecimalParser.sol";

contract DecimalParserHarness {
    function parse18(string memory s) external pure returns (uint256) {
        return DecimalParser.parse18(s);
    }
}

contract DecimalParserTest is Test {
    DecimalParserHarness internal h = new DecimalParserHarness();

    function test_parsesIntegersAndFractions() public view {
        assertEq(h.parse18("0"), 0);
        assertEq(h.parse18("1"), 1e18);
        assertEq(h.parse18("161.1935"), 161.1935e18);
        assertEq(h.parse18("162.8054"), 162.8054e18);
        assertEq(h.parse18("0.5"), 0.5e18);
        assertEq(h.parse18("007.50"), 7.5e18);
        assertEq(h.parse18("1.000000000000000001"), 1e18 + 1);
    }

    function test_revert_empty() public {
        vm.expectRevert(DecimalParser.EmptyDecimal.selector);
        h.parse18("");
    }

    function test_revert_missingDigits() public {
        vm.expectRevert(DecimalParser.MissingDigits.selector);
        h.parse18(".");
        vm.expectRevert(DecimalParser.MissingDigits.selector);
        h.parse18(".5");
        vm.expectRevert(DecimalParser.MissingDigits.selector);
        h.parse18("5.");
    }

    function test_revert_badChars() public {
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 0));
        h.parse18("-1");
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 0));
        h.parse18(" 1");
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 3));
        h.parse18("1.2.3");
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 1));
        h.parse18("1e18");
        vm.expectRevert(abi.encodeWithSelector(DecimalParser.InvalidDecimalChar.selector, 1));
        h.parse18("1,000");
    }

    function test_revert_tooManyFractionDigits() public {
        vm.expectRevert(DecimalParser.TooManyFractionDigits.selector);
        h.parse18("1.0000000000000000001");
    }

    function testFuzz_roundTrip(uint128 intPart, uint64 frac, uint8 fracDigitsSeed) public view {
        uint256 fracDigits = bound(fracDigitsSeed, 1, 18);
        uint256 fracValue = uint256(frac) % (10 ** fracDigits);

        string memory fracStr = Strings.toString(fracValue);
        while (bytes(fracStr).length < fracDigits) fracStr = string.concat("0", fracStr);

        string memory s = string.concat(Strings.toString(intPart), ".", fracStr);
        uint256 expected = uint256(intPart) * 1e18 + fracValue * 10 ** (18 - fracDigits);
        assertEq(h.parse18(s), expected);
    }

    function testFuzz_integers(uint128 x) public view {
        assertEq(h.parse18(Strings.toString(x)), uint256(x) * 1e18);
    }
}
