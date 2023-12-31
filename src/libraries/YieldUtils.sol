// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";
import "forge-std/console.sol";

library YieldUtils {
    //
    function orderYields(YieldVars[3] memory y) internal view {
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
        if (y[0].apr < y[1].apr) (y[0], y[1]) = (y[1], y[0]);
        if (y[1].apr < y[2].apr) (y[1], y[2]) = (y[2], y[1]);
        console.log(
            "## yields id ##",
            uint(y[0].id),
            uint(y[1].id),
            uint(y[2].id)
        );
        console.log(
            "## yields ordered ##",
            y[0].apr / 1e23,
            y[1].apr / 1e23,
            y[2].apr / 1e23
        );
    }

    function findLiquidMarket(
        YieldVars[3] memory y,
        uint _amount
    ) internal pure returns (YieldVars memory _y) {
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
        YieldVars memory a,
        YieldVars memory b,
        uint priority // index => priority
    ) internal pure returns (YieldVars memory) {
        uint _a = (priority >> (BYTE * a.id)) & BYTE;
        uint _b = (priority >> (BYTE * b.id)) & BYTE;
        return _a > _b ? b : a;
    }

    function getSlowest(
        YieldVars memory a,
        YieldVars memory b,
        YieldVars memory c,
        uint priority
    ) internal pure returns (YieldVars memory) {
        uint _a = (priority >> (BYTE * a.id)) & BYTE;
        uint _b = (priority >> (BYTE * b.id)) & BYTE;
        uint _c = (priority >> (BYTE * c.id)) & BYTE;
        (YieldVars memory slowest, uint slowestOrder) = _a < _b
            ? (a, _a)
            : (b, _b);
        slowest = slowestOrder < _c ? slowest : c;
        return slowest;
    }

    // order slower to fastest: C,v2,v3
    function getFastest(
        YieldVars memory a,
        YieldVars memory b,
        uint priority
    ) internal pure returns (YieldVars memory) {
        uint _a = (priority >> (BYTE * a.id)) & BYTE;
        uint _b = (priority >> (BYTE * b.id)) & BYTE;
        return _a < _b ? b : a;
    }

    function getFastest(
        YieldVars memory a,
        YieldVars memory b,
        YieldVars memory c,
        uint priority
    ) internal pure returns (YieldVars memory) {
        uint _a = (priority >> (BYTE * a.id)) & BYTE;
        uint _b = (priority >> (BYTE * b.id)) & BYTE;
        uint _c = (priority >> (BYTE * c.id)) & BYTE;
        (YieldVars memory fastest, uint fastestOrder) = _a > _b
            ? (a, _a)
            : (b, _b);
        fastest = fastestOrder > _c ? fastest : c;
        return fastest;
    }

    function getTotalAmounts(
        YieldVars[3] memory y
    ) internal pure returns (uint total) {
        for (uint i; i < 3; i++) {
            total += y[i].amt;
        }
    }

    //add amount while being considerate tolimit
    function deployAmount(
        YieldVars memory _y,
        uint _amount
    ) internal pure returns (uint, bool _isHitLimit) {
        uint _total = _amount + _y.amt;

        if (_y.limit >= _total) {
            _y.amt += _amount;
        } else {
            _amount = _y.limit - _y.amt;
            _y.amt = _y.limit;
            _y.apr = 0; // send it to lower order
            _isHitLimit = true;
        }

        return (_amount, _isHitLimit);
    }
}
