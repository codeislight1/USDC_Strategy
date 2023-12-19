// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";
import "forge-std/console.sol";
import "./MathUtils.sol";

library CompoundUtils {
    //
    function compAprWrapper(
        uint _apr,
        bool _isWrap
    ) internal pure returns (uint) {
        return _isWrap ? (_apr * RAY) / COMP100APR : (_apr * COMP100APR) / RAY;
    }

    function aprToAmount(
        CompoundVars memory v,
        uint _apr,
        bool isDeposit
    ) public pure returns (uint _amount) {
        // unwrap
        _apr = compAprWrapper(_apr, false);
        int _s = int(_apr);
        uint _amount0 = MathUtils.abs((v.rsl * v.tB) / (_s - v.base) - v.tS);
        uint _amount1 = MathUtils.abs(
            (int(COMP_FACTOR) * v.rsh * v.tB) /
                (v.kink * (v.rsh - v.rsl) - int(COMP_FACTOR) * (v.base - _s)) -
                v.tS
        );

        uint _sr0 = amountToSupplyRate(v, _amount0, isDeposit);
        uint _sr1 = amountToSupplyRate(v, _amount1, isDeposit);
        _amount = MathUtils.abs(_s - int(_sr0)) < MathUtils.abs(_s - int(_sr1))
            ? uint(_amount0)
            : uint(_amount1);
    }

    function amountToSupplyRate(
        CompoundVars memory _v
    ) internal pure returns (uint) {
        return amountToSupplyRate(_v, 0, true); // direction won't matter
    }

    function amountToSupplyRate(
        CompoundVars memory _v,
        uint _amount,
        bool isDeposit // if so increment otherwise decrement
    ) internal pure returns (uint _supplyRate) {
        // TBD ensure tS != _amount when withdrawing

        // utilization = totalBorrows * FACTOR / totalSupply
        uint _u = (uint(_v.tB) * COMP_FACTOR) /
            (isDeposit ? (uint(_v.tS) + _amount) : (uint(_v.tS) - _amount));
        // supplyRate
        // if(utilization <= supplyKink) supplyRate = base + mulFactor(low,utilization)
        if (_u <= uint(_v.kink)) {
            _supplyRate = uint(_v.base) + MathUtils.mulFactor(uint(_v.rsl), _u);
        } else {
            _supplyRate =
                uint(_v.base) +
                MathUtils.mulFactor(uint(_v.rsl), uint(_v.kink)) +
                MathUtils.mulFactor(uint(_v.rsh), _u - uint(_v.kink));
        }
    }
}
