// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import "./libraries/Constants.sol";
import "./libraries/MathUtils.sol";
import "./libraries/YieldUtils.sol";
import "./interfaces/IStrategyImplementation.sol";
import "./LendingAllocatorStrategy.sol";
import "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

/** @author codeislight
 *  @notice contract used by a keeper to run calculations to derive the allocation percentages needed,
 *  to achieve an optimal rate, where we are able to get the best yield on all the funds deployed.
 */
contract AllocatorDataProvider {
    using MathUtils for uint;
    using MathUtils for int;
    using MathUtils for uint[3];
    using MathUtils for uint[];
    using YieldUtils for YieldVars;
    using YieldUtils for YieldVars[3];

    LendingAllocatorStrategy public immutable s;
    uint public immutable TOTAL_MARKETS;
    ERC20 public immutable asset;
    uint8 public priority; //TODO add a setter
    uint public MINIMUM; // TODO add a setter
    uint public aprThreshold = 50; // TODO add a setter
    uint constant BP = 10000;

    constructor(
        LendingAllocatorStrategy _strat,
        uint8[] memory _priority,
        address _asset,
        uint _minimum
    ) {
        uint total = _strat.TOTAL_MARKETS();
        require(_priority.length == total, "!len");
        s = _strat;
        TOTAL_MARKETS = total;
        asset = ERC20(_asset);
        // check for no dups
        if (total == 2) require(_priority[0] != _priority[1], "!p0");
        else {
            require(_priority[0] != _priority[1], "!p1");
            require(_priority[1] != _priority[2], "!p2");
            require(_priority[0] != _priority[2], "!p3");
        }
        for (uint8 i; i < total; i++) {
            priority = (_priority[i] << (i * 8)) & priority;
        }
        MINIMUM = _minimum;
    }

    /** @notice provides current apr achieved by the strategy
     * @return current apr where 1e27 representing 100%.
     */
    function getCurrentStrategyApr() public view returns (uint) {
        uint totalAmounts;
        uint nominator;
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            IStrategyImplementation _impl = impl(i);
            uint _deployedAmount = _impl.getStrategyReceiptBalance();
            if (_deployedAmount == 0) continue;

            uint _apr = _impl.getCurrentApr();
            nominator += _apr * _deployedAmount;
            totalAmounts += _deployedAmount;
        }
        return totalAmounts != 0 ? nominator / totalAmounts : 0;
    }

    function getKeepDataIDLE() public view returns (KeepData[] memory data) {
        console.log("---KEEPDATA_IDLE---");
        uint _amount = asset.balanceOf(address(s));
        require(_amount > 0, "nothing to withdraw!");

        (uint _totalMarkets, YieldVars[3] memory y) = _loadDataSimulation(true);
        _simulate(true, _totalMarkets, _amount, y);

        uint totalAmount;
        uint keepNumber;
        for (uint i; i < TOTAL_MARKETS; i++) {
            totalAmount += y[i].amt;
            console.log(
                "KeepIDLE amount",
                y[i].id,
                y[i].amt,
                impl(y[i].id).getDepositLimit()
            );
            if (y[i].amt > 0) keepNumber++;
        }
        uint totalPercentages;
        data = new KeepData[](keepNumber);
        uint keepIndex;
        for (uint i; i < TOTAL_MARKETS; i++) {
            if (y[i].amt > 0) {
                data[keepIndex].id = y[i].id;
                data[keepIndex].percent = uint128(
                    (1 ether * y[i].amt) / totalAmount
                );
                console.log(
                    "id-percent",
                    data[keepIndex].id,
                    data[keepIndex].percent,
                    y[i].limit
                );
                totalPercentages += data[keepIndex].percent;
                keepIndex++;
            }
        }

        // in case of any left over
        if (1 ether - 10 <= totalPercentages && totalPercentages < 1 ether) {
            uint diff = 1 ether - totalPercentages;
            totalPercentages += diff;
            data[0].percent += uint128(diff);
        }
        require(1 ether == totalPercentages, "!TotalPercentages");
    }

    /** @notice called by keeper to maintain the strategy
     * @return data array of ids and percentages to be allocated
     */
    function getKeepData()
        public
        view
        returns (KeepData[] memory data, uint toBeApr)
    {
        // loading data to withdraw from all markets

        uint total = s.availableWithdrawLimit(address(0)) -
            asset.balanceOf(address(s));
        console.log("---KEEPDATA---", total);
        require(total > 0, "nothing to withdraw!");
        (uint _totalMarkets, YieldVars[3] memory y) = _loadDataSimulation(
            false
        );
        _simulate(false, _totalMarkets, total, y);
        (, YieldVars[3] memory y1) = _loadDataSimulation(true);
        total = asset.balanceOf(address(s));
        for (uint i; i < TOTAL_MARKETS; i++) {
            YieldVars memory y0 = getId(y, y1[i].id);
            if (y0.amt == 0) continue; // skip invalid markets
            total += y0.amt;
            y1[i].r = y0.r;
            y1[i].apr = y0.cacheApr;
            console.log("amt_simulate_w", y0.id, y0.amt, y0.cacheApr);
            // y1[i].limit += (y1[i].limit == type(uint248).max) ? 0 : y0.amt; // TODO adjust the limit
        }
        _simulate(true, _totalMarkets, total, y1);
        total = 0;
        uint keepNumber;
        for (uint i; i < TOTAL_MARKETS; i++) {
            if (y1[i].amt > 0) keepNumber++;
            else continue;
            total += y1[i].amt;
            toBeApr += y1[i].amt * y1[i].cacheApr;
            console.log("amt_simulate_d", y1[i].id, y1[i].amt, y1[i].cacheApr);
        }
        toBeApr = total != 0 ? toBeApr / total : 0;
        uint totalPercentages;
        data = new KeepData[](keepNumber);
        uint keepIndex;
        for (uint i; i < TOTAL_MARKETS; i++) {
            if (y1[i].amt > 0) {
                data[keepIndex].id = y1[i].id;
                data[keepIndex].percent = uint128(
                    (1 ether * y1[i].amt) / total
                );
                totalPercentages += data[keepIndex].percent;
                keepIndex++;
            }
        }

        // TODO redo, in case markets are 2 or any other, there is no left over
        if (1 ether - 10 <= totalPercentages && totalPercentages < 1 ether) {
            uint diff = 1 ether - totalPercentages;
            totalPercentages += diff;
            data[0].percent += uint128(diff);
        }

        require(1 ether == totalPercentages, "!TotalPercentages");
    }

    function check()
        external
        view
        returns (bool isCheck, bytes memory execPayload)
    {
        // deposited assets
        // change in apr from current
        uint currentApr = getCurrentStrategyApr();
        uint _deployed = s.availableWithdrawLimit(address(0)) -
            asset.balanceOf(address(s));
        console.log("DEPLOYED:", _deployed);
        if (_deployed > 0) {
            (KeepData[] memory data, uint newApr) = getKeepData();
            isCheck =
                currentApr != 0 &&
                (newApr.diff(currentApr) * BP) / currentApr >= aprThreshold;
            console.log(
                "DEPLOYED details:",
                currentApr,
                newApr,
                (newApr.diff(currentApr) * BP) / currentApr
            );

            if (isCheck) {
                console.log("KEEP maintain");
                execPayload = abi.encodeCall(
                    LendingAllocatorStrategy.keep,
                    (data)
                );
                return (isCheck, execPayload);
            }
        }
        // TODO add a threshold, 1 token or something
        isCheck = asset.balanceOf(address(s)) > 0;
        if (isCheck) {
            console.log("KEEP deployIDLE");
            KeepData[] memory data = getKeepDataIDLE();
            execPayload = abi.encodeCall(
                LendingAllocatorStrategy.keepIDLE,
                (data)
            );
            return (isCheck, execPayload);
        }
    }

    function getId(
        YieldVars[3] memory y,
        uint _id
    ) internal pure returns (YieldVars memory) {
        for (uint i; i < 3; i++) {
            if (y[i].id == _id) return y[i];
        }
        revert("end");
    }

    function impl(
        uint8 id
    ) internal view returns (IStrategyImplementation impl_) {
        (impl_, ) = s.markets(id);
    }

    function reachApr(
        YieldVars memory _from,
        YieldVars[3] memory _y,
        uint _amt,
        uint _a, // amount to deploy
        bool _isDeposit,
        bool _isOrder
    ) internal view returns (uint _amount, bool _isLimit) {
        _amount = _amt;
        (_amt, _isLimit) = _from.deployAmount(_a.min(_amount));
        _amount -= _amt;
        (_from.r, _from.apr) = impl(_from.id).updateVirtualReserve(
            _from,
            _amt,
            _isDeposit,
            !_isLimit
        );
        if (!_isLimit) {
            _from.cacheApr = _from.apr;
        }
        if (_isOrder) _y.orderYields();
    }

    function reachApr(
        YieldVars memory _from,
        YieldVars[3] memory _y,
        uint _amount,
        uint _a, // amount to deploy
        bool _isDeposit
    ) internal view returns (uint _amt, bool _isLimit) {
        (_amt, _isLimit) = reachApr(
            _from,
            _y,
            _amount,
            _a, // amount to deploy
            _isDeposit,
            true
        );
    }

    function reachApr(
        YieldVars memory _from,
        YieldVars memory _to,
        YieldVars[3] memory _y,
        uint _amount,
        bool _isDeposit
    ) internal view returns (uint, bool) {
        uint _amt = impl(_from.id).getAmount(_from.r, _to.apr, _isDeposit);
        return reachApr(_from, _y, _amount, _amt, _isDeposit);
    }

    // funds adjustment
    function _adjustFor1Market(
        YieldVars memory _y,
        uint _amount
    ) internal view returns (uint amt) {
        console.log("1M", _amount / 1e6);
        (amt, ) = _y.deployAmount(_amount);
    }

    function _adjustFundsFor2Markets(
        YieldVars[3] memory y,
        uint _amt,
        bool _isDeposit
    ) internal view returns (uint _amount) {
        console.log("2M", _amt / 1e6);
        _amount = _amt;
        bool _isBreak;
        while (_amount != 0 && !_isBreak) {
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = reachApr(
                    y[_isDeposit ? 0 : 1],
                    y,
                    _amount,
                    _amount,
                    _isDeposit
                );
                break;
            }
            if (y[1].apr.lt(y[0].apr)) {
                // i0 > i1
                console.log("2B1", _amount / 1e6);
                (_amount, _isBreak) = reachApr(
                    y[_isDeposit ? 0 : 1],
                    y[_isDeposit ? 1 : 0],
                    y,
                    _amount,
                    _isDeposit
                );
            } else {
                // i0 = i1
                console.log("2B2", _amount / 1e6);

                (_amount, _isBreak) = _adjustEqual(y, _amount, _isDeposit, 2);
            }
        }
    }

    function _adjustFundsFor3Markets(
        YieldVars[3] memory y,
        uint _amt,
        bool _isDeposit
    ) internal view returns (uint _amount) {
        console.log("3M", _amt / 1e6);
        _amount = _amt;
        uint _p = priority;
        bool _isBreak = false;
        while (_amount != 0 && !_isBreak) {
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = reachApr(
                    y[_isDeposit ? 0 : 2],
                    y,
                    _amount,
                    _amount,
                    _isDeposit
                );
                break;
            }

            if (
                (y[2].apr.lt(y[1].apr) && y[1].apr.lt(y[0].apr)) ||
                (y[_isDeposit ? 2 : 1].apr.eq(y[_isDeposit ? 1 : 0].apr) &&
                    y[_isDeposit ? 1 : 2].apr.lt(y[_isDeposit ? 0 : 1].apr))
            ) {
                // deposit  : i2 < i1 < i0 || i2 = i1 < i0
                // withdraw : i2 < i1 < i0 || i2 < i1 = i0
                console.log("3B1", _amount / 1e6);
                (_amount, _isBreak) = reachApr(
                    y[_isDeposit ? 0 : 2],
                    y[1], // the one after either ends
                    y,
                    _amount,
                    _isDeposit
                );
            } else if (
                y[_isDeposit ? 2 : 1].apr.lt(y[_isDeposit ? 1 : 0].apr) &&
                y[_isDeposit ? 1 : 2].apr.eq(y[_isDeposit ? 0 : 1].apr)
            ) {
                // deposit  : i2 < i1 = i0
                // withdraw : i2 = i1 < i0
                uint _a0;
                uint _a1;
                if (_isDeposit) {
                    // amount of m0 to reach m2
                    _a0 = impl(y[0].id).getAmount(y[0].r, y[2].apr, _isDeposit);
                    // amount of m1 to reach m2
                    _a1 = impl(y[1].id).getAmount(y[1].r, y[2].apr, _isDeposit);
                } else {
                    // amount of m1 to reach m0
                    _a0 = impl(y[1].id).getAmount(y[1].r, y[0].apr, _isDeposit);
                    // amount of m2 to reach m0
                    _a1 = impl(y[2].id).getAmount(y[2].r, y[0].apr, _isDeposit);
                }

                if (_a0 + _a1 <= _amount) {
                    // attempt to allocate in one, deploy any left over in the other
                    console.log("3B2_1", _amount / 1e6);
                    YieldVars memory chosen = _isDeposit
                        ? y[0].getSlowest(y[1], _p)
                        : y[1].getFastest(y[2], _p);
                    (_amount, _isBreak) = reachApr(
                        chosen,
                        y[_isDeposit ? 2 : 0],
                        y,
                        _amount,
                        _isDeposit
                    );
                    if (_isBreak) continue;
                    chosen = chosen.id == y[1].id
                        ? y[_isDeposit ? 0 : 2]
                        : y[1];
                    (_amount, _isBreak) = reachApr(
                        chosen,
                        y[_isDeposit ? 2 : 0],
                        y,
                        _amount,
                        _isDeposit
                    );
                } else if (_a0 <= _amount || _a1 <= _amount) {
                    // allocate half of the funds in one of the markets
                    console.log("3B2_2", _amount / 1e6);
                    YieldVars memory chosen = _isDeposit
                        ? y[0].getSlowest(y[1], _p)
                        : y[1].getFastest(y[2], _p);
                    uint _l = _a0.min(_a1);
                    uint _portion = _l / 2;
                    if (_portion == 0) _portion = _l;

                    (_amount, _isBreak) = reachApr(
                        chosen,
                        y,
                        _amount,
                        _portion,
                        _isDeposit
                    );
                } else {
                    // allocate half of the funds in one of the markets
                    console.log("3B2_3", _amount / 1e6);
                    uint _l = _a0.min(_a1);
                    uint _third = _amount.min(_l) / 2;
                    if (_third == 0) _third = _l;
                    YieldVars memory chosen = _isDeposit
                        ? y[1].getSlowest(y[2], _p)
                        : y[1].getFastest(y[2], _p);
                    (_amount, _isBreak) = reachApr(
                        chosen,
                        y,
                        _amount,
                        _third,
                        _isDeposit
                    );
                }
            } else {
                // i0 = i1 = i2
                console.log("3B3", _amount / 1e6);
                (_amount, _isBreak) = _adjustEqual(y, _amount, _isDeposit, 3);
            }
        }
    }

    function _adjustEqual(
        YieldVars[3] memory y,
        uint _amt,
        bool _isDeposit,
        uint _m // either 2 or 3
    ) internal view returns (uint _amount, bool _isBreak) {
        //
        console.log("ADJUST_EQ", _amt / 1e6);
        _amount = _amt;
        bool _break;
        if (_amount >= MINIMUM) {
            console.log("P1", _amount / 1e6);
            uint _portion = _amount / _m;
            uint[] memory aprs = new uint[](_m);
            uint[] memory amounts = new uint[](_m);

            for (uint i; i < _m; i++) {
                aprs[i] = impl(y[i].id).getApr(y[i].r, _portion, _isDeposit);
            }

            // uint chosenIndex = _isDeposit
            //     ? aprs.getMaxIndex()
            //     : aprs.getMinIndex();
            uint chosenIndex = aprs.getMaxIndex();

            amounts[chosenIndex] = _portion;

            for (uint i = 0; i < _m; i++) {
                if (i != chosenIndex) {
                    amounts[i] = impl(y[i].id).getAmount(
                        y[i].r,
                        aprs[chosenIndex],
                        _isDeposit
                    );
                }
                (_amount, _break) = reachApr(
                    y[i],
                    y,
                    _amount,
                    amounts[i],
                    _isDeposit,
                    i == _m - 1
                );
                if (!_isBreak) _isBreak = _break;
            }
        } else {
            console.log("P2", _amount / 1e6);
            uint total = y.getTotalAmounts();
            if (total != 0) {
                for (uint i; i < _m; i++) {
                    (_amount, _break) = reachApr(
                        y[i],
                        y,
                        _amount,
                        (i == _m - 1) ? _amount : (y[i].amt * _amount) / total,
                        _isDeposit,
                        i == _m - 1
                    );
                    if (!_isBreak) _isBreak = _break;
                }
            } else {
                (_amount, _break) = reachApr(
                    _m == 3
                        ? y[0].getSlowest(y[1], y[2], priority)
                        : y[0].getSlowest(y[1], priority),
                    y,
                    _amount,
                    _amount / _m,
                    _isDeposit
                );
                if (!_isBreak) _isBreak = _break;
            }
        }
        console.log("postAmount", _amount);
    }

    function _simulate(
        bool isDeposit,
        uint totalMarkets,
        uint _amount,
        YieldVars[3] memory y
    ) internal view {
        if (totalMarkets == 3) {
            _amount = _adjustFundsFor3Markets(y, _amount, isDeposit); // might reach cap

            if (_amount > 0)
                _amount = _adjustFundsFor2Markets(y, _amount, isDeposit);
            if (_amount > 0)
                _adjustFor1Market(y.findLiquidMarket(_amount), _amount);
        } else if (totalMarkets == 2) {
            _amount = _adjustFundsFor2Markets(y, _amount, isDeposit); // might reach cap

            if (_amount > 0)
                _adjustFor1Market(y.findLiquidMarket(_amount), _amount);
        } else if (totalMarkets == 1) {
            _adjustFor1Market(y.findLiquidMarket(_amount), _amount);
        } else {
            revert("No Markets Available");
        }
    }

    function _loadDataSimulation(
        bool isDeposit
    ) internal view returns (uint markets_, YieldVars[3] memory y) {
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            IStrategyImplementation _impl = impl(i);
            if (_impl.isActive()) {
                y[i] = _impl.loadMarket(i, isDeposit);
                if (y[i].apr != 0) markets_++;
            }
        }
        console.log("TOTAL_MARKETS:", markets_);
        y.orderYields();
    }

    function printAprs() external view {
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            console.log("RATE:", i, impl(i).getCurrentApr() / 1e23);
        }
    }
}
