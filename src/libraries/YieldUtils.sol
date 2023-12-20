// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";
import "forge-std/console.sol";

library YieldUtils {
    //
    function orderYields(YieldVar[3] memory y) internal view {
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
        if (y[0].apr < y[1].apr) (y[0], y[1]) = (y[1], y[0]);
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
        console.log(
            "## yields types ##",
            uint(y[0].stratType),
            uint(y[1].stratType),
            uint(y[2].stratType)
        );
        console.log(
            "## yields ordered ##",
            y[0].apr / 1e23,
            y[1].apr / 1e23,
            y[2].apr / 1e23
        );
    }

    function findLiquidMarket(
        YieldVar[3] memory y,
        uint _amount
    ) internal view returns (YieldVar memory _y) {
        // console.log("findLiquid amount", _amount);
        // console.log("dump 0", uint(y[0].stratType), y[0].amt, y[0].apr);
        // console.log("dump 1", uint(y[1].stratType), y[1].amt, y[1].apr);
        // console.log("dump 2", uint(y[2].stratType), y[2].amt, y[2].apr);
        for (uint i; i < 3; i++) {
            // console.log("---findLiquid", y[i].limit, y[i].amt, y[i].apr / 1e23);
            if (y[i].limit >= _amount + y[i].amt && y[i].apr != 0) {
                _y = y[i];
                break;
            }
        }
    }

    // order slower to fastest: C,v2,v3
    function getSlowest(
        YieldVar memory a,
        YieldVar memory b
    ) internal pure returns (YieldVar memory) {
        if (
            a.stratType == StrategyType.COMPOUND ||
            b.stratType == StrategyType.COMPOUND
        ) {
            return a.stratType == StrategyType.COMPOUND ? a : b;
        } else {
            return a.stratType == StrategyType.AAVE_V2 ? a : b;
        }
    }

    function getSlowest(
        YieldVar memory a,
        YieldVar memory b,
        YieldVar memory c
    ) internal pure returns (YieldVar memory) {
        return getSlowest(getSlowest(a, b), getSlowest(b, c));
    }

    // order slower to fastest: C,v2,v3
    function getFastest(
        YieldVar memory a,
        YieldVar memory b
    ) internal pure returns (YieldVar memory) {
        if (
            a.stratType == StrategyType.AAVE_V3 ||
            b.stratType == StrategyType.AAVE_V3
        ) {
            return a.stratType == StrategyType.AAVE_V3 ? a : b;
        } else {
            return a.stratType == StrategyType.AAVE_V2 ? a : b;
        }
    }

    function getFastest(
        YieldVar memory a,
        YieldVar memory b,
        YieldVar memory c
    ) internal pure returns (YieldVar memory) {
        return getFastest(getFastest(a, b), getFastest(b, c));
    }

    //add amount while being considerate tolimit
    function deployAmount(
        YieldVar[3] memory _y,
        StrategyType _strat,
        // YieldVar memory _y,
        uint _amount
    ) internal view returns (uint, bool _isHitLimit) {
        for (uint i; i < 3; i++) {
            if (_y[i].stratType == _strat) {
                uint _total = _amount + _y[i].amt;

                if (_y[i].limit >= _total) {
                    _y[i].amt += _amount;
                } else {
                    _amount = _y[i].limit - _y[i].amt;
                    _y[i].amt = _y[i].limit;
                    //
                    _y[i].apr = 0; // send it to lower order
                    _isHitLimit = true;
                }
                break;
            }
        }

        return (_amount, _isHitLimit);
    }

    function getMarkets(
        YieldVar[3] memory y
    )
        internal
        pure
        returns (YieldVar memory c, YieldVar memory v2, YieldVar memory v3)
    {
        for (uint i; i < 3; i++) {
            if (y[i].stratType == StrategyType.COMPOUND) c = y[i];
            else if (y[i].stratType == StrategyType.AAVE_V2) v2 = y[i];
            else if (y[i].stratType == StrategyType.AAVE_V3) v3 = y[i];
        }
    }
}
