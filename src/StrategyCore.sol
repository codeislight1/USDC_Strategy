// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import "forge-std/console.sol";
import "./interfaces/IAaveV2.sol";
import "./interfaces/IAaveV3.sol";
import "./interfaces/ICompound.sol";
import "./interfaces/IAaveV2InterestStrategy.sol";
import "./interfaces/IAaveV3InterestStrategy.sol";
import "./interfaces/IStableDebtToken.sol";
import "./interfaces/IVariableDebtToken.sol";
import "./libraries/Constants.sol";
import "./libraries/MathUtils.sol";
import "./libraries/YieldUtils.sol";
import "./libraries/CompoundUtils.sol";
import "./libraries/AaveUtils.sol";
import "./libraries/ReserveUtils.sol";

contract StrategyCore {
    using MathUtils for uint;
    using MathUtils for int;
    using YieldUtils for YieldVar;
    using YieldUtils for YieldVar[3];
    using CompoundUtils for uint;
    using CompoundUtils for CompoundVars;
    using AaveUtils for AaveVars;
    using ReserveUtils for ReservesVars;

    // constants
    uint constant MINIMUM = 1000 * 10 ** DECIMALS;

    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    ICompound constant COMP_USDC =
        ICompound(0xF25212E676D1F7F89Cd72fFEe66158f541246445);

    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant AAVE_V2_USDC = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address constant AAVE_V3_USDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;

    // vars
    int _comp_base;
    int _comp_rsl;
    int _comp_rsh;
    int _comp_kink;

    int _base_V2;
    int _vrs1_V2;
    int _vrs2_V2;
    int _opt_V2;
    int _exc_V2;

    int _base_V3;
    int _vrs1_V3;
    int _vrs2_V3;
    int _opt_V3;
    int _exc_V3;

    address _aaveV2Strategy;
    address _aaveV3Strategy;

    // loaders
    function _loadCompound() internal {
        // TODO: fetch only when they change,
        // if it is an upgradeable contract, check for a change in the implementation
        _comp_base = int(COMP_USDC.supplyPerSecondInterestRateBase());
        _comp_rsl = int(COMP_USDC.supplyPerSecondInterestRateSlopeLow());
        _comp_rsh = int(COMP_USDC.supplyPerSecondInterestRateSlopeHigh());
        _comp_kink = int(COMP_USDC.supplyKink());
    }

    function _loadAaveV2(address _strat) internal {
        if (_strat != _aaveV2Strategy) {
            IAaveV2InterestStrategy _interestStart = IAaveV2InterestStrategy(
                _strat
            );
            _base_V2 = int(_interestStart.baseVariableBorrowRate());
            _vrs1_V2 = int(_interestStart.variableRateSlope1());
            _vrs2_V2 = int(_interestStart.variableRateSlope2());
            _opt_V2 = int(_interestStart.OPTIMAL_UTILIZATION_RATE());
            _exc_V2 = int(_interestStart.EXCESS_UTILIZATION_RATE());
        }
    }

    function _loadAaveV3(address _strat) internal {
        if (_strat != _aaveV3Strategy) {
            IAaveV3InterestStrategy _interestStart = IAaveV3InterestStrategy(
                _strat
            );
            _base_V3 = int(_interestStart.getBaseVariableBorrowRate());
            _vrs1_V3 = int(_interestStart.getVariableRateSlope1());
            _vrs2_V3 = int(_interestStart.getVariableRateSlope2());
            _opt_V3 = int(_interestStart.OPTIMAL_USAGE_RATIO());
            _exc_V3 = int(_interestStart.MAX_EXCESS_USAGE_RATIO());
        }
    }

    // getters
    function _getCompoundVars() internal returns (CompoundVars memory vars) {
        _loadCompound();
        vars.tS = int(COMP_USDC.totalSupply());
        vars.tB = int(COMP_USDC.totalBorrow());
        vars.base = _comp_base;
        vars.rsl = _comp_rsl;
        vars.rsh = _comp_rsh;
        vars.kink = _comp_kink;
    }

    function _getAaveV2Vars() internal returns (AaveVars memory vars) {
        IAaveV2.ReserveData memory _data = aaveV2.getReserveData(USDC);
        IAaveV2InterestStrategy _interestStart = IAaveV2InterestStrategy(
            _data.interestRateStrategyAddress
        );
        _loadAaveV2(address(_interestStart));
        uint _reserveFactor = ((_data.configuration.data >> 64) & 65535);
        (uint _tsd, uint _avgSBR) = IStableDebtToken(
            _data.stableDebtTokenAddress
        ).getTotalSupplyAndAvgRate();
        (vars.tSD, vars.avgSBR) = (int(_tsd), int(_avgSBR));
        vars.tVD = int(
            IVariableDebtToken(_data.variableDebtTokenAddress)
                .scaledTotalSupply()
                .rayMul(uint(_data.variableBorrowIndex))
        );
        vars.tD = vars.tVD + vars.tSD;
        vars.aL = int(ERC20(USDC).balanceOf(_data.aTokenAddress));
        vars.subFactor = PERCENT_FACTOR - int(_reserveFactor);
        vars.base = _base_V2;
        vars.vrs1 = _vrs1_V2;
        vars.vrs2 = _vrs2_V2;
        vars.opt = _opt_V2;
        vars.exc = _exc_V2;
    }

    function _getAaveV3Vars() internal returns (AaveVars memory vars) {
        IAaveV3.ReserveData memory _data = aaveV3.getReserveData(USDC);
        IAaveV3InterestStrategy _interestStart = IAaveV3InterestStrategy(
            _data.interestRateStrategyAddress
        );
        _loadAaveV3(address(_interestStart));
        uint _reserveFactor = ((_data.configuration.data >> 64) & 65535);
        (uint _tsd, uint _avgSBR) = IStableDebtToken(
            _data.stableDebtTokenAddress
        ).getTotalSupplyAndAvgRate();
        (vars.tSD, vars.avgSBR) = (int(_tsd), int(_avgSBR));
        vars.tVD = int(
            IVariableDebtToken(_data.variableDebtTokenAddress)
                .scaledTotalSupply()
                .rayMul(uint(_data.variableBorrowIndex))
        );
        vars.tD = vars.tVD + vars.tSD;
        vars.aL = int(ERC20(USDC).balanceOf(_data.aTokenAddress));
        vars.subFactor = PERCENT_FACTOR - int(_reserveFactor);
        vars.base = _base_V3;
        vars.vrs1 = _vrs1_V3;
        vars.vrs2 = _vrs2_V3;
        vars.opt = _opt_V3;
        vars.exc = _exc_V3;
    }

    // funds adjustment
    function _adjustFor1Market(
        YieldVar[3] memory _y,
        StrategyType _strat,
        uint _amount
    ) internal view returns (uint amt) {
        console.log("## ADJUST 1", _amount / 1e6, uint(_strat));
        (amt, ) = _y.deployAmount(_strat, _amount);
    }

    function _adjustFundsFor2Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt,
        bool _isDeposit
    ) internal view returns (uint _amount) {
        console.log("### ADJUST 2", _amt / 1e6);
        _amount = _amt;
        bool _isBreak;
        while (_amount != 0 && !_isBreak) {
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = r.reachApr(
                    y[_isDeposit ? 0 : 1],
                    y,
                    _amount,
                    _amount,
                    _isDeposit
                );
                break;
            }

            if (y[1].apr.lt(y[0].apr)) {
                // console.log("ALLOC2 CHECK 1", _amount / 1e6, _isDeposit);
                // i1 < i0
                (_amount, _isBreak) = r.reachApr(
                    y[_isDeposit ? 0 : 1],
                    y[_isDeposit ? 1 : 0],
                    y,
                    _amount,
                    _isDeposit
                );
            } else {
                //

                YieldVar memory _to = _isDeposit
                    ? y[0].getSlowest(y[1])
                    : y[0].getFastest(y[1]);
                // console.log("ALLOC2 CHECK 2", _amount / 1e6, _isDeposit);
                uint _seventh = _amount / 7;
                if (_seventh == 0) _seventh = _amount;

                (_amount, _isBreak) = r.reachApr(
                    _to,
                    y,
                    _amount,
                    _seventh,
                    _isDeposit
                );
            }
        }
    }

    function _adjustFundsFor3Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt,
        bool _isDeposit
    ) internal view returns (uint _amount) {
        _amount = _amt;
        console.log("### ADJUST 3", _amount / 1e6);
        bool _isBreak = false;
        while (_amount != 0 && !_isBreak) {
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = r.reachApr(
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
                // console.log("3CHECK 1", _amount);
                // deposit  : i2 < i1 < i0 || i2 = i1 < i0
                // withdraw : i2 < i1 < i0 || i2 < i1 = i0
                // console.log("ALLOC3 CHECK 1", _amount / 1e6);
                (_amount, _isBreak) = r.reachApr(
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
                uint _a0;
                uint _a1;
                if (_isDeposit) {
                    _a0 = r.aprToAmount(y[0], y[2].apr, true);
                    _a1 = r.aprToAmount(y[1], y[2].apr, true);
                } else {
                    // _a1
                    _a0 = r.aprToAmount(y[1], y[0].apr, false);
                    // _a2
                    _a1 = r.aprToAmount(y[2], y[0].apr, false);
                }

                if (_a0 + _a1 <= _amount) {
                    // console.log("3CHECK 2_1", _amount);
                    // console.log("ALLOC3 CHECK 2_1", _amount / 1e6);
                    YieldVar memory chosen = _isDeposit
                        ? y[0].getSlowest(y[1])
                        : y[1].getFastest(y[2]);
                    (_amount, _isBreak) = r.reachApr(
                        chosen,
                        y[_isDeposit ? 2 : 0],
                        y,
                        _amount,
                        _isDeposit
                    );
                    if (_isBreak) continue;
                    (_amount, _isBreak) = r.reachApr(
                        chosen.stratType == y[1].stratType
                            ? y[_isDeposit ? 0 : 2]
                            : y[1],
                        y[_isDeposit ? 2 : 0],
                        y,
                        _amount,
                        _isDeposit
                    );
                } else if (_a0 <= _amount || _a1 <= _amount) {
                    // console.log("3CHECK 2_2", _amount);
                    // console.log("ALLOC3 CHECK 2_2", _amount / 1e6);
                    YieldVar memory chosen = _isDeposit
                        ? y[0].getSlowest(y[1])
                        : y[1].getFastest(y[2]);
                    uint _l = _a0.min(_a1);
                    uint _portion = _l / 2;
                    if (_portion == 0) _portion = _l;

                    (_amount, _isBreak) = r.reachApr(
                        // y[_a0 < _a1 ? 0 : 1],
                        chosen,
                        y,
                        _amount,
                        _portion,
                        _isDeposit
                    );
                } else {
                    // console.log("3CHECK 2_3", _amount);
                    // console.log("ALLOC3 CHECK 2_3", _amount / 1e6);
                    uint _l = _a0.min(_a1);
                    uint _third = _amount.min(_l) / 2;

                    if (_third == 0) _third = _l;
                    (_amount, _isBreak) = r.reachApr(
                        // y[_a0 < _a1 ? 0 : 1],
                        _isDeposit
                            ? y[1].getSlowest(y[2])
                            : y[1].getFastest(y[2]),
                        y,
                        _amount,
                        _third,
                        _isDeposit
                    );
                }
            } else {
                // console.log("33CHECK 3", _amount);
                //
                // console.log("ALLOC3 CHECK 3", _amount / 1e6);
                YieldVar memory chosen = _isDeposit
                    ? y[0].getSlowest(y[1], y[2])
                    : y[0].getFastest(y[1], y[2]);
                uint _portion = _amount / (_amount >= 10_000 * 1e6 ? 2 : 20); // pretty gas efficient
                // uint _portion = _amount / 20; // less gas efficient but more accurate
                if (_portion == 0) _portion = _amount;
                (_amount, _isBreak) = r.reachApr(
                    chosen,
                    y,
                    _amount,
                    _portion,
                    _isDeposit
                );
            }
        }
    }

    function _getV3SupplyCap() internal view returns (uint) {
        return
            ((aaveV3.getReserveData(USDC).configuration.data >> 116) &
                68719476735) * 10 ** DECIMALS;
    }

    function _isActive(
        StrategyType _strategy
    ) internal view returns (bool _active) {
        if (_strategy == StrategyType.COMPOUND) {
            _active = !COMP_USDC.isSupplyPaused();
        } else if (_strategy == StrategyType.AAVE_V2) {
            uint _data = aaveV2.getReserveData(USDC).configuration.data;
            _active = (((_data >> 56) & 1) == 1) && !(((_data >> 57) & 1) == 1);
        } else if (_strategy == StrategyType.AAVE_V3) {
            uint _data = aaveV3.getReserveData(USDC).configuration.data;
            uint _supplyCap = _getV3SupplyCap();
            _active = (((_data >> 56) & 1) == 1) &&
                !(((_data >> 57) & 1) == 1) &&
                !(((_data >> 60) & 1) == 1) &&
                _supplyCap == 0
                ? true
                : ERC20(AAVE_V3_USDC).totalSupply() < _supplyCap;
        }
    }

    function _getSupplyRate(
        StrategyType _strat
    ) internal view returns (uint _apr) {
        if (_strat == StrategyType.COMPOUND) {
            // adapted
            _apr = uint(COMP_USDC.getSupplyRate(COMP_USDC.getUtilization()))
                .compAprWrapper(true);
        } else if (_strat == StrategyType.AAVE_V2) {
            _apr = aaveV2.getReserveData(USDC).currentLiquidityRate;
        } else if (_strat == StrategyType.AAVE_V3) {
            _apr = aaveV3.getReserveData(USDC).currentLiquidityRate;
        }
    }

    function _balanceOfToken(T _token) internal view returns (uint) {
        return _balanceOfToken(_token, address(this));
    }

    function _balanceOfToken(
        T _token,
        address _user
    ) internal view returns (uint _balance) {
        if (_token == T.U) _balance = ERC20(USDC).balanceOf(_user);
        else if (_token == T.C)
            _balance = ERC20(address(COMP_USDC)).balanceOf(_user);
        else if (_token == T.A2)
            _balance = ERC20(AAVE_V2_USDC).balanceOf(_user);
        else if (_token == T.A3)
            _balance = ERC20(AAVE_V3_USDC).balanceOf(_user);
    }

    function _simulate(
        bool isDeposit,
        uint totalMarkets,
        uint _amount,
        ReservesVars memory r,
        YieldVar[3] memory y
    ) internal view {
        // console.log("#### TOTAL MAREKTS - amount", totalMarkets, _amount / 1e6);
        if (totalMarkets == 3) {
            _amount = _adjustFundsFor3Markets(y, r, _amount, isDeposit); // might reach cap

            if (_amount > 0)
                _amount = _adjustFundsFor2Markets(y, r, _amount, isDeposit);
            if (_amount > 0) {
                _amount = _adjustFor1Market(
                    y,
                    y.findLiquidMarket(_amount).stratType,
                    _amount
                );
            }
        } else if (totalMarkets == 2) {
            _amount = _adjustFundsFor2Markets(y, r, _amount, isDeposit); // might reach cap

            if (_amount > 0) {
                _amount = _adjustFor1Market(
                    y,
                    y.findLiquidMarket(_amount).stratType,
                    _amount
                );
            }
        } else if (totalMarkets == 1) {
            _adjustFor1Market(
                y,
                y.findLiquidMarket(_amount).stratType,
                _amount
            );
        } else {
            revert("No Markets Available");
        }
    }

    //
    function _loadDataSimulation(
        bool isDeposit
    )
        internal
        returns (uint markets, ReservesVars memory r, YieldVar[3] memory y)
    {
        //
        uint i;
        // console.log("LOADED:", isDeposit);
        if (_isActive(StrategyType.COMPOUND)) {
            r.c = _getCompoundVars();
            y[i].stratType = StrategyType.COMPOUND;
            y[i].limit = isDeposit
                ? type(uint).max
                : (
                    _balanceOfToken(T.U, address(COMP_USDC)).min(
                        _balanceOfToken(T.C)
                    )
                );

            // y[i].apr = y[i].limit == 0 ? 0 : _getSupplyRate(y[i].stratType);

            y[i].apr = isDeposit || y[i].limit != 0
                ? _getSupplyRate(y[i].stratType)
                : 0;
            console.log(
                "LOADED C:",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
            if (y[i].apr != 0) markets++;
            i++;
        }

        if (_isActive(StrategyType.AAVE_V2)) {
            r.v2 = _getAaveV2Vars();
            y[i].stratType = StrategyType.AAVE_V2;
            y[i].limit = isDeposit
                ? type(uint).max
                : (
                    _balanceOfToken(T.U, address(AAVE_V2_USDC)).min(
                        _balanceOfToken(T.A2)
                    )
                );
            // y[i].apr = y[i].limit == 0 ? 0 : _getSupplyRate(y[i].stratType);
            y[i].apr = isDeposit || y[i].limit != 0
                ? _getSupplyRate(y[i].stratType)
                : 0;
            // console.log(
            //     "LOADED V2:",
            //     uint(y[i].stratType),
            //     y[i].apr / 1e23,
            //     y[i].limit / 1e6
            // );
            if (y[i].apr != 0) markets++;

            i++;
        }

        if (_isActive(StrategyType.AAVE_V3)) {
            r.v3 = _getAaveV3Vars();
            y[i].stratType = StrategyType.AAVE_V3;
            uint supplyCap = _getV3SupplyCap();
            uint tS = ERC20(AAVE_V3_USDC).totalSupply();
            y[i].limit = isDeposit
                ? (
                    supplyCap == 0
                        ? type(uint).max
                        : (tS < supplyCap ? supplyCap - tS : 0)
                )
                : (
                    _balanceOfToken(T.U, address(AAVE_V3_USDC)).min(
                        _balanceOfToken(T.A3)
                    )
                );
            // y[i].apr = y[i].limit == 0 ? 0 : _getSupplyRate(y[i].stratType);
            y[i].apr = isDeposit || y[i].limit != 0
                ? _getSupplyRate(y[i].stratType)
                : 0;
            // console.log(
            //     "LOADED V3:",
            //     uint(y[i].stratType),
            //     y[i].apr / 1e23,
            //     y[i].limit / 1e6
            // );
            if (y[i].apr != 0) markets++;
        }

        y.orderYields();
    }

    function printAprs() external view {
        console.log(
            "RATE COMPOUND:",
            _getSupplyRate(StrategyType.COMPOUND) / 1e23
        );
        console.log(
            "RATE AAVE V2:",
            _getSupplyRate(StrategyType.AAVE_V2) / 1e23
        );
        console.log(
            "RATE AAVE V3:",
            _getSupplyRate(StrategyType.AAVE_V3) / 1e23
        );
    }
}
