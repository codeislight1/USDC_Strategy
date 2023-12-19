// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";
import "forge-std/console.sol";
import "./MathUtils.sol";

library AaveUtils {
    //
    function calcAaveApr(
        AaveVars memory v,
        int adjAmount,
        bool isDeposit // if so increment otherwise decrement
    ) internal pure returns (int) {
        // TBD ensure addedAmount != v.tD + v.aL when withdrawing
        uint currentVariableBorrowRate;
        uint utilizationRate = v.tD == 0
            ? 0
            : MathUtils.rayDiv(
                uint(v.tD),
                uint(
                    v.aL + (isDeposit ? (v.tD + adjAmount) : (v.tD - adjAmount))
                )
            );
        if (utilizationRate > uint(v.opt)) {
            uint256 excessUtilizationRateRatio = MathUtils.rayDiv(
                (utilizationRate - uint(v.opt)),
                uint(v.exc)
            );
            currentVariableBorrowRate =
                uint(v.base + v.vrs1) +
                MathUtils.rayMul(uint(v.vrs2), excessUtilizationRateRatio);
        } else {
            currentVariableBorrowRate =
                uint(v.base) +
                MathUtils.rayDiv(
                    MathUtils.rayMul(utilizationRate, uint(v.vrs1)),
                    uint(v.opt)
                );
        }

        return
            int256(
                MathUtils.percentMul(
                    MathUtils.rayMul(
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
    ) private pure returns (uint256) {
        uint256 totalDebt = totalStableDebt + totalVariableDebt;

        if (totalDebt == 0) return 0;

        uint256 weightedVariableRate = MathUtils.rayMul(
            (totalVariableDebt * R),
            currentVariableBorrowRate
        );

        uint256 weightedStableRate = MathUtils.rayMul(
            (totalStableDebt * R),
            currentAverageStableBorrowRate
        );

        uint256 overallBorrowRate = MathUtils.rayDiv(
            (weightedVariableRate + weightedStableRate),
            totalDebt * R
        );

        return overallBorrowRate;
    }

    function calcAmount(
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

            // int _4c = ((v.tVD * iR + 2 * iRa + 2 * iR * v.tSD * v.avgSBR) *
            // (4 * v.opt)) / (v.tVD * v.vrs1 * 2e9);
            int _4c = ((((((PERCENT_FACTOR * (2 * lr - 1) - v.subFactor) *
                2 *
                v.tD) / v.tVD) * v.exc) / v.vrs2) * iRa) / v.subFactor;
            int _sqrt = int(MathUtils.sqrt(MathUtils.abs((_b ** 2 + _4c))));
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

            int _4c = ((((((PERCENT_FACTOR * (2 * lr - 1) - v.subFactor) *
                2 *
                v.tD) / v.tVD) * v.opt) / v.vrs1) * iRa) / v.subFactor;

            int _sqrt = int(MathUtils.sqrt(MathUtils.abs((_b ** 2 + _4c))));

            u = (-_b + _sqrt) / 2;
        }
        return (v.tD * iRa) / u - (v.aL + v.tD);
    }

    function calcAaveInterestToAmount(
        AaveVars memory v,
        int _apr,
        bool _isDeposit
    ) public pure returns (uint _amount) {
        int _amount0 = int(MathUtils.abs(calcAmount(v, true, _apr)));
        int _amount1 = int(MathUtils.abs(calcAmount(v, false, _apr)));
        int sr0 = calcAaveApr(v, _amount0, _isDeposit);
        int sr1 = calcAaveApr(v, _amount1, _isDeposit);

        _amount = MathUtils.abs(_apr - sr0) < MathUtils.abs(_apr - sr1)
            ? uint(_amount0)
            : uint(_amount1);
    }
}
