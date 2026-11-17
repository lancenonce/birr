// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title DecimalParser
/// @notice Strictly parses an unsigned decimal string (e.g. "161.1935") into an 18-decimal fixed-point uint.
/// @dev Accepts only `[0-9]+` or `[0-9]+.[0-9]{1,18}`. No sign, whitespace, exponent or thousands separators.
library DecimalParser {
    uint256 internal constant SCALE_DECIMALS = 18;

    error EmptyDecimal();
    error InvalidDecimalChar(uint256 index);
    error TooManyFractionDigits();
    error MissingDigits();

    /// @return value `s` scaled by 1e18.
    function parse18(string memory s) internal pure returns (uint256 value) {
        bytes memory b = bytes(s);
        uint256 len = b.length;
        if (len == 0) revert EmptyDecimal();

        uint256 intPart;
        uint256 fracPart;
        uint256 fracDigits;
        bool seenDot;
        uint256 intDigits;

        for (uint256 i; i < len; ++i) {
            bytes1 c = b[i];
            if (c == ".") {
                if (seenDot) revert InvalidDecimalChar(i);
                seenDot = true;
                continue;
            }
            if (c < "0" || c > "9") revert InvalidDecimalChar(i);
            uint8 d = uint8(c) - 48;
            if (seenDot) {
                if (++fracDigits > SCALE_DECIMALS) revert TooManyFractionDigits();
                fracPart = fracPart * 10 + d;
            } else {
                ++intDigits;
                intPart = intPart * 10 + d; // checked arithmetic reverts on absurd lengths
            }
        }

        // Reject "", ".", ".5", "5."
        if (intDigits == 0 || (seenDot && fracDigits == 0)) revert MissingDigits();

        value = intPart * 10 ** SCALE_DECIMALS + fracPart * 10 ** (SCALE_DECIMALS - fracDigits);
    }
}
