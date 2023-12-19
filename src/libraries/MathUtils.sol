// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";

library MathUtils {
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function abs(int256 a) internal pure returns (uint) {
        return uint(a > 0 ? a : -a);
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (H_RAY + (a * b)) / RAY;
    }

    function percentMul(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }

        // overflow check removed
        uint HALF_PERCENT = uint(PERCENT_FACTOR) / 2;

        return (value * percentage + HALF_PERCENT) / uint(PERCENT_FACTOR);
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 halfB = b / 2;
        return (halfB + a * RAY) / b;
    }

    function mulFactor(uint n, uint factor) internal pure returns (uint) {
        return (n * factor) / COMP_FACTOR;
    }

    function l(uint a) internal pure returns (uint) {
        return (a * ACCURACY) / RAY;
    }

    function lt(uint a, uint b) internal pure returns (bool) {
        return l(a) < l(b);
    }

    function eq(uint a, uint b) internal pure returns (bool) {
        return l(a) == l(b);
    }

    // include babylion source
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}
