// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";

library MathUtils {
    function diff(uint a, uint b) internal view returns (uint) {
        return a > b ? a - b : b - a;
    }

    function getMinIndex(
        uint[3] memory nums
    ) internal pure returns (uint index) {
        for (uint i = 1; i < nums.length; i++) {
            index = nums[index] < nums[i] ? index : i;
        }
    }

    function getMaxIndex(
        uint[3] memory nums
    ) internal pure returns (uint index) {
        for (uint i = 1; i < nums.length; i++) {
            index = nums[index] > nums[i] ? index : i;
        }
    }

    function getMinIndex(
        uint[] memory nums
    ) internal pure returns (uint index) {
        for (uint i = 1; i < nums.length; i++) {
            index = nums[index] < nums[i] ? index : i;
        }
    }

    function getMaxIndex(
        uint[] memory nums
    ) internal pure returns (uint index) {
        for (uint i = 1; i < nums.length; i++) {
            index = nums[index] > nums[i] ? index : i;
        }
    }

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

    // getApr has 8 digits accuracy, there are cases where might return 8399999999.. instead of 8400000000.. thus a 1 difference considered equal
    function lt(uint a, uint b) internal view returns (bool) {
        a = l(a);
        b = l(b);
        return a < b && diff(a, b) > 1;
    }

    // accept 1 difference considered as equal
    function eq(uint a, uint b) internal view returns (bool) {
        a = l(a);
        b = l(b);
        return a == b || diff(a, b) == 1;
    }

    // source: https://github.com/Uniswap/solidity-lib/blob/c01640b0f0f1d8a85cba8de378cc48469fcfd9a6/contracts/libraries/Babylonian.sol#L10
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

    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp
    ) internal view returns (uint256) {
        return
            calculateCompoundedInterest(
                rate,
                lastUpdateTimestamp,
                block.timestamp
            );
    }

    //TODO add source
    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) internal pure returns (uint256) {
        //solium-disable-next-line
        uint256 exp = currentTimestamp - uint256(lastUpdateTimestamp);

        if (exp == 0) {
            return RAY;
        }

        uint256 expMinusOne;
        uint256 expMinusTwo;
        uint256 basePowerTwo;
        uint256 basePowerThree;
        unchecked {
            expMinusOne = exp - 1;

            expMinusTwo = exp > 2 ? exp - 2 : 0;

            basePowerTwo =
                rayMul(rate, rate) /
                (SECONDS_PER_YEAR * SECONDS_PER_YEAR);
            basePowerThree = rayMul(basePowerTwo, rate) / SECONDS_PER_YEAR;
        }

        uint256 secondTerm = exp * expMinusOne * basePowerTwo;
        unchecked {
            secondTerm /= 2;
        }
        uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree;
        unchecked {
            thirdTerm /= 6;
        }

        return RAY + (rate * exp) / SECONDS_PER_YEAR + secondTerm + thirdTerm;
    }
}
