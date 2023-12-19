// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import "./Constants.sol";
import "./CompoundUtils.sol";
import "./AaveUtils.sol";
import "./YieldUtils.sol";

library ReserveUtils {
    //
    // update reserve simulating a deposit/withdraw
    function updateVirtualReserve(
        ReservesVars memory _r,
        YieldVar memory _y,
        uint _amount,
        bool isDeposit
    ) internal view {
        //
        console.log(
            "// updateVirtualReserve: reserveAmt amount isDeposit:",
            _y.amt / 1e6,
            _amount / 1e6,
            isDeposit
        );
        if (_y.stratType == StrategyType.COMPOUND) {
            if (isDeposit) _r.c.tS += int256(_amount);
            else _r.c.tS -= int256(_amount);

            _y.apr = CompoundUtils.compAprWrapper(
                CompoundUtils.compAmountToSupplyRate(_r.c),
                true
            );
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            //
            _y.apr = uint(
                AaveUtils.calcAaveApr(_r.v2, int256(_amount), isDeposit)
            );
            if (isDeposit) _r.v2.aL += int256(_amount);
            else _r.v2.aL -= int256(_amount);
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            //
            _y.apr = uint(
                AaveUtils.calcAaveApr(_r.v3, int256(_amount), isDeposit)
            );
            if (isDeposit) _r.v3.aL += int256(_amount);
            else _r.v3.aL -= int256(_amount);
        }
    }

    function reachApr(
        ReservesVars memory _r,
        YieldVar memory _from,
        YieldVar[3] memory _y,
        uint _amount,
        uint _a, // amount to deploy
        bool _isDeposit
    ) internal view returns (uint _amt, bool _isLimit) {
        uint _deployedAmount;
        (_deployedAmount, _isLimit) = YieldUtils.deployAmount(
            _from,
            _a >= _amount ? _amount : _a
        );
        _amount -= _deployedAmount;
        updateVirtualReserve(_r, _from, _deployedAmount, _isDeposit);
        YieldUtils.orderYields(_y);
        _amt = _amount;
    }

    function reachApr(
        ReservesVars memory _r,
        YieldVar memory _from,
        YieldVar memory _to,
        YieldVar[3] memory _y,
        uint _amount,
        bool _isDeposit
    ) internal view returns (uint, bool) {
        return
            reachApr(
                _r,
                _from,
                _y,
                _amount,
                aprToAmount(_r, _from, _to.apr, _isDeposit),
                _isDeposit
            );
    }

    function amountToApr(
        ReservesVars memory _r,
        YieldVar memory _y,
        uint _amount,
        bool _isDeposit
    ) public pure returns (uint _apr) {
        if (_y.stratType == StrategyType.COMPOUND) {
            _apr = CompoundUtils.compAprWrapper(
                CompoundUtils.compAmountToSupplyRate(_r.c, _amount, _isDeposit),
                true
            );
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            _apr = uint(
                AaveUtils.calcAaveApr(_r.v2, int256(_amount), _isDeposit)
            );
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            _apr = uint(
                AaveUtils.calcAaveApr(_r.v3, int256(_amount), _isDeposit)
            );
        }
    }

    function aprToAmount(
        ReservesVars memory _r,
        YieldVar memory _y,
        uint _apr,
        bool _isDeposit
    ) public pure returns (uint _amount) {
        if (_y.stratType == StrategyType.COMPOUND) {
            _amount = CompoundUtils.calcCompoundInterestToAmount(
                _r.c,
                _apr,
                _isDeposit
            );
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            _amount = AaveUtils.calcAaveInterestToAmount(
                _r.v2,
                int(_apr),
                _isDeposit
            );
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            _amount = AaveUtils.calcAaveInterestToAmount(
                _r.v3,
                int(_apr),
                _isDeposit
            );
        }
        // console.log("input rate:", _apr / 1e23, _amount / 1e6);
    }
}
