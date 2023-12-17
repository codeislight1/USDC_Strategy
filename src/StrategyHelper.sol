// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";

contract StrategyHelper {
    uint constant COMP_FACTOR = 1e18;
    uint constant ACCURACY = 1e6; // safer value as usually the value is around 1e8
    uint constant COMP100APR = 317100000 * 100;
    uint constant RAY = 1e27;
    uint constant H_RAY = RAY / 2;
    uint constant R = 1e9;
    int constant PERCENT_FACTOR = 1e4;

    enum T {
        U, // USDC
        C, // Compound
        A2, // Aave V2
        A3 // Aave V3
    }

    enum StrategyType {
        COMPOUND,
        AAVE_V2,
        AAVE_V3
    }

    struct CompoundVars {
        int tS;
        int tB;
        int base;
        int rsl;
        int rsh;
        int kink;
    }

    struct AaveVars {
        int tVD;
        int tD;
        int aL;
        int tSD;
        int avgSBR;
        int subFactor; // percFacor - reserveFactor
        int base;
        int vrs1;
        int vrs2;
        int opt;
        int exc;
    }

    struct ReservesVars {
        CompoundVars c;
        AaveVars v2;
        AaveVars v3;
    }

    struct YieldVar {
        uint apr;
        uint amt; // amount to be deployed
        StrategyType stratType;
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

    function _orderYields(YieldVar[3] memory y) internal pure {
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
        if (y[0].apr < y[1].apr) (y[0], y[1]) = (y[1], y[0]);
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
    }

    function _compAprAdapter(
        uint _apr,
        bool _isWrap
    ) internal pure returns (uint) {
        return _isWrap ? (_apr * RAY) / COMP100APR : (_apr * COMP100APR) / RAY;
    }

    function _calcCompoundInterestToAmount(
        CompoundVars memory v,
        uint _apr
    ) public pure returns (uint _amount) {
        _apr = _compAprAdapter(_apr, false);
        int _s = int(_apr);
        uint _amount0 = abs((v.rsl * v.tB) / (_s - v.base) - v.tS);
        uint _amount1 = abs(
            (int(COMP_FACTOR) * v.rsh * v.tB) /
                (v.kink * (v.rsh - v.rsl) - int(COMP_FACTOR) * (v.base - _s)) -
                v.tS
        );
        // uint _sr0 = COMP_USDC.getSupplyRate(
        //     uint((v.tB * int(COMP_FACTOR)) / (v.tS + int(_amount0)))
        // );
        uint _sr0 = _compAmountToSupplyRate(v, _amount0);
        // uint _sr1 = COMP_USDC.getSupplyRate(
        //     abs((v.tB * int(COMP_FACTOR)) / (v.tS + int(_amount1)))
        // );
        uint _sr1 = _compAmountToSupplyRate(v, _amount1);
        _amount = abs(_s - int(_sr0)) < abs(_s - int(_sr1))
            ? uint(_amount0)
            : uint(_amount1);
    }

    function _compAmountToSupplyRate(
        CompoundVars memory _v
    ) internal pure returns (uint) {
        return _compAmountToSupplyRate(_v, 0);
    }

    function _compAmountToSupplyRate(
        CompoundVars memory _v,
        uint _amountToAdd
    ) internal pure returns (uint _supplyRate) {
        // utilization = totalBorrows * FACTOR / totalSupply
        uint _u = (uint(_v.tB) * COMP_FACTOR) / (uint(_v.tS) + _amountToAdd);
        // supplyRate
        // if(utilization <= supplyKink) supplyRate = base + mulFactor(low,utilization)
        if (_u <= uint(_v.kink)) {
            _supplyRate = uint(_v.base) + mulFactor(uint(_v.rsl), _u);
        } else {
            _supplyRate =
                uint(_v.base) +
                mulFactor(uint(_v.rsl), uint(_v.kink)) +
                mulFactor(uint(_v.rsh), _u - uint(_v.kink));
        }
        //
        // else supplyRate = base + mulFactor(low,supplyKink) + mulFactor(high, utilization-supplyKink)
    }

    function _calcAaveApr(
        AaveVars memory v,
        int addedAmount
    ) internal pure returns (int) {
        uint currentVariableBorrowRate;
        uint utilizationRate = v.tD == 0
            ? 0
            : rayDiv(uint(v.tD), uint(v.aL + addedAmount + v.tD));
        if (utilizationRate > uint(v.opt)) {
            uint256 excessUtilizationRateRatio = rayDiv(
                utilizationRate - uint(v.opt),
                uint(v.exc)
            );
            currentVariableBorrowRate =
                uint(v.base + v.vrs1) +
                rayMul(uint(v.vrs2), excessUtilizationRateRatio);
        } else {
            currentVariableBorrowRate =
                uint(v.base) +
                (rayDiv(rayMul(utilizationRate, uint(v.vrs1)), uint(v.opt)));
        }

        return
            int256(
                percentMul(
                    rayMul(
                        _getOverallBorrowRate(
                            uint(v.tSD),
                            uint(v.tVD),
                            currentVariableBorrowRate,
                            uint(v.avgSBR)
                        ),
                        utilizationRate
                    ),
                    uint(v.subFactor)
                )
            );
    }

    function _getOverallBorrowRate(
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 currentVariableBorrowRate,
        uint256 currentAverageStableBorrowRate
    ) internal pure returns (uint256) {
        uint256 totalDebt = totalStableDebt + totalVariableDebt;

        if (totalDebt == 0) return 0;

        uint256 weightedVariableRate = rayMul(
            totalVariableDebt * R,
            currentVariableBorrowRate
        );

        uint256 weightedStableRate = rayMul(
            totalStableDebt * R,
            currentAverageStableBorrowRate
        );

        uint256 overallBorrowRate = rayDiv(
            (weightedVariableRate + weightedStableRate),
            totalDebt * R
        );

        return overallBorrowRate;
    }

    function _calcAmount(
        AaveVars memory v,
        bool isUgtOPT,
        int lr
    ) internal pure returns (int) {
        int u;
        int iR = int(R);
        int iRa = int(RAY);
        // eqn = ( -b + math.sqrt(b**2+4*c) ) / 2*

        // aave:
        //
        // c0= tD/tVD
        // c1= 0.5 + RAY/(tD*1e9) + tSD * avgSBR / tD
        // c2= (RAY*PERC/subFactor) * (lr-(0.5+(subFactor/(2*PERC))))
        // c3= base + vrs1 + 0.5 + vrs2/(2*RAY)
        // c4= exc/vrs2
        // c5= base + 0.5 +RAY/(2*opt)
        // c6= opt/vrs1
        if (isUgtOPT) {
            // _b1= c4*(c3+c0*c1)-opt
            // _c1= c0*c2*c4
            int _b = ((v.base +
                v.vrs1 +
                (iR *
                    v.tVD *
                    (iRa + v.vrs2) +
                    iRa *
                    (iR * (v.tD + 2 * v.tSD * v.avgSBR) + 2 * iRa)) /
                (iRa * v.tVD * 2 * iR)) * v.exc) /
                v.vrs2 -
                v.opt;
            // console.log("b0", uint(_b), abs(_b));

            // int _4c = ((v.tVD * iR + 2 * iRa + 2 * iR * v.tSD * v.avgSBR) *
            // (4 * v.opt)) / (v.tVD * v.vrs1 * 2e9);
            int _4c = ((((((PERCENT_FACTOR * (2 * lr - 1) - v.subFactor) *
                2 *
                v.tD) / v.tVD) * v.exc) / v.vrs2) * iRa) / v.subFactor;
            // console.log("4c1", uint(_4c), abs(_4c));
            int _sqrt = int(sqrt(uint(_b ** 2 + _4c)));
            // console.log("sqrt0", uint(_sqrt), abs(_sqrt));
            u = (-_b + _sqrt) / 2;
        } else {
            // _b2= c6*(c5+c0*c1)
            // _c2= c0*c2*c6
            int _b = ((v.base +
                (v.tVD +
                    ((2 * v.tVD * iRa) / v.opt) +
                    ((2 * iRa) / iR) +
                    v.tD +
                    2 *
                    v.tSD *
                    v.avgSBR) /
                (2 * v.tVD)) * v.opt) / v.vrs1;
            // console.log("b1", uint(_b), abs(_b));

            int _4c = ((((((PERCENT_FACTOR * (2 * lr - 1) - v.subFactor) *
                2 *
                v.tD) / v.tVD) * v.opt) / v.vrs1) * iRa) / v.subFactor;
            // console.log("4c1", uint(_4c), abs(_4c));

            int _sqrt = int(sqrt(abs(_b ** 2 + _4c)));
            // console.log("sqrt1", uint(_sqrt), abs(_sqrt));

            u = (-_b + _sqrt) / 2;
        }
        // console.log("u", uint(u), abs(u));
        // console.log(
        //     "amt",
        //     uint((v.tD * iRa) / u - (v.aL + v.tD)),
        //     abs((v.tD * iRa) / u - (v.aL + v.tD))
        // );
        return (v.tD * iRa) / u - (v.aL + v.tD);
    }

    // simulate a deposit
    function _updateVirtualReserve(
        YieldVar memory _y,
        ReservesVars memory _r,
        uint _amount
    ) internal pure {
        //
        if (_y.stratType == StrategyType.COMPOUND) {
            //
            _r.c.tS += int256(_amount);
            _y.apr = _compAprAdapter(_compAmountToSupplyRate(_r.c), true);
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            //
            _y.apr = uint(_calcAaveApr(_r.v2, int256(_amount)));
            _r.v2.aL += int256(_amount);
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            //
            _y.apr = uint(_calcAaveApr(_r.v3, int256(_amount)));
            _r.v3.aL += int256(_amount);
        }
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function abs(int a) internal pure returns (uint) {
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
