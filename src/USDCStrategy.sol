// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./StrategyHelper.sol";
import "./interfaces/IAaveV2.sol";
import "./interfaces/IAaveV3.sol";
import "./interfaces/ICompound.sol";
import "./interfaces/IAaveV2InterestStrategy.sol";
import "./interfaces/IAaveV3InterestStrategy.sol";
import "./interfaces/IStableDebtToken.sol";
import "./interfaces/IVariableDebtToken.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract USDCStrategy is BaseStrategy, StrategyHelper {
    using SafeERC20 for ERC20;

    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    ICompound constant COMP_USDC =
        ICompound(0xF25212E676D1F7F89Cd72fFEe66158f541246445);

    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant AAVE_V2_USDC = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address constant AAVE_V3_USDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    uint constant DECIMALS = 6;
    uint constant MINIMUM = 1000 * 10 ** DECIMALS;

    bool _isKeeperActive;
    uint public lastExecuted;

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

    constructor() BaseStrategy(USDC, "USDC strategy") {
        ERC20(USDC).approve(address(aaveV2), type(uint).max);
        ERC20(USDC).approve(address(aaveV3), type(uint).max);
        ERC20(USDC).approve(address(COMP_USDC), type(uint).max);

        _loadAaveV2(aaveV2.getReserveData(USDC).interestRateStrategyAddress);
        _loadAaveV3(aaveV3.getReserveData(USDC).interestRateStrategyAddress);

        lastExecuted = block.timestamp;
        _isKeeperActive = true;
        _loadConstants();
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        _deposit(_amount);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        _withdraw(_amount);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        view
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = _totalAmounts();
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
     */

    function _tend(uint256 _totalIdle) internal override {
        //
    }

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
     */

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
     */

    function availableDepositLimit(
        address
    ) public view override returns (uint256) {
        // C active ? third max : 0
        // V2 active ? third max : 0
        // V3 active ? limit - supply : 0
        uint thirdMax = type(uint).max / 3; // uint.max / number of markets
        uint v3_tS = ERC20(AAVE_V3_USDC).totalSupply();
        uint v3_cap = _getV3SupplyCap();
        uint v3Limit = v3_cap == 0
            ? thirdMax
            : (v3_cap > v3_tS ? v3_cap - v3_tS : 0);
        return
            (_isActive(StrategyType.COMPOUND) ? thirdMax : 0) +
            (_isActive(StrategyType.AAVE_V2) ? thirdMax : 0) +
            (_isActive(StrategyType.AAVE_V3) ? v3Limit : 0);
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn,
     *  we take into account the amount of tokens available to withdraw in the lending pool.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     *
     */

    function availableWithdrawLimit(
        address
    ) public view override returns (uint256) {
        return
            _balanceOfToken(T.U) +
            (
                _isActive(StrategyType.COMPOUND)
                    ? min(
                        _balanceOfToken(T.C),
                        _balanceOfToken(T.U, address(COMP_USDC))
                    )
                    : 0
            ) +
            (
                _isActive(StrategyType.AAVE_V2)
                    ? min(
                        _balanceOfToken(T.A2),
                        _balanceOfToken(T.U, AAVE_V2_USDC)
                    )
                    : 0
            ) +
            (
                _isActive(StrategyType.AAVE_V3)
                    ? min(
                        _balanceOfToken(T.A3),
                        _balanceOfToken(T.U, AAVE_V3_USDC)
                    )
                    : 0
            );
    }

    /* @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _withdraw(_amount);
    }

    function freeFromMarket(T _token) external onlyManagement {
        uint _amount = _balanceOfToken(_token);
        if (_amount > 0) _withdraw(_amount);
    }

    function deployToMarket(StrategyType _strategy) external onlyManagement {
        uint _amount = _balanceOfToken(T.U);
        if (_amount > 0) _deposit(_strategy, _amount);
    }

    function recoverERC20(address _token, address _to) external onlyManagement {
        require(
            _token != USDC &&
                _token != address(COMP_USDC) &&
                _token != AAVE_V2_USDC &&
                _token != AAVE_V3_USDC,
            "!token"
        );
        ERC20(_token).transfer(_to, ERC20(_token).balanceOf(address(this)));
    }

    function switchKepperActive(bool _active) external onlyManagement {
        require(_isKeeperActive != _active);
        _isKeeperActive = _active;
    }

    function _getV3SupplyCap() internal view returns (uint) {
        return
            ((aaveV3.getReserveData(USDC).configuration.data >> 116) &
                68719476735) * 10 ** DECIMALS;
    }

    function _deposit(uint _amount) internal {
        // 1
        bool _isC = _isActive(StrategyType.COMPOUND);
        bool _isV2 = _isActive(StrategyType.AAVE_V2);
        bool _isV3 = _isActive(StrategyType.AAVE_V3);

        uint _totalMarkets;
        if (_isC) _totalMarkets++;
        if (_isV2) _totalMarkets++;
        if (_isV3) _totalMarkets++;

        // 2
        YieldVar[3] memory y;
        ReservesVars memory r;
        // TBD check compound vars that might need to be updated through a load,
        // if they update the implemenatation
        uint i;
        // load them up
        if (_isC) {
            r.c = _getCompoundVars();
            y[i].stratType = StrategyType.COMPOUND;
            y[i].apr = _getSupplyRate(y[i].stratType);
            y[i].limit = type(uint).max; // no limit
            console.log(
                "vars deposit C",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
            i++;
        }
        if (_isV2) {
            r.v2 = _getAaveV2Vars();
            y[i].stratType = StrategyType.AAVE_V2;
            y[i].apr = _getSupplyRate(y[i].stratType);
            y[i].limit = type(uint).max; // no limit
            console.log(
                "vars deposit V2",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
            i++;
        }

        if (_isV3) {
            r.v3 = _getAaveV3Vars();
            y[i].stratType = StrategyType.AAVE_V3;
            y[i].apr = _getSupplyRate(y[i].stratType);
            uint supplyCap = _getV3SupplyCap();
            uint tS = ERC20(AAVE_V3_USDC).totalSupply();
            y[i].limit = supplyCap == 0
                ? type(uint).max
                : (tS < supplyCap ? supplyCap - tS : 0);
            console.log(
                "vars deposit V3",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
        }
        // ordering
        _orderYields(y);
        // console.log("order 0 type apr", uint(y[0].stratType), y[0].apr / 1e23);
        // console.log("order 1 type apr", uint(y[1].stratType), y[1].apr / 1e23);
        // console.log("order 2 type apr", uint(y[2].stratType), y[2].apr / 1e23);
        // 3
        if (_totalMarkets == 3) {
            // console.log("3Markets");
            // 3 can turn into 2
            _amount = _allocateFundsTo3Markets(y, r, _amount); // might reach cap
            if (_amount != 0) _allocateFundsTo2Markets(y, r, _amount);
        } else if (_totalMarkets == 2) {
            // console.log("2Markets");
            // 2 can turn into 1
            _amount = _allocateFundsTo2Markets(y, r, _amount); // might reach cap
            if (_amount != 0)
                _allocateFundsTo1Market(y, y[0].stratType, _amount);
        } else if (_totalMarkets == 1) {
            // console.log("1Market");
            // 1 is a 1
            _allocateFundsTo1Market(y, y[0].stratType, _amount);
        } else {
            revert("No Markets Available");
        }

        // deploy respective amounts for each market
        for (i = 0; i < 3; i++) {
            uint _amt = y[i].amt;
            if (_amt > 0) {
                console.log(
                    "allocate type amt:",
                    uint(y[i].stratType),
                    _amt / 1e6
                );
                _deposit(y[i].stratType, _amt);
            }
        }
    }

    //add amount while being considerate tolimit
    function _addAmt(
        YieldVar[3] memory _y,
        StrategyType _strat,
        uint _amount
    ) internal view returns (uint _deployedAmount, bool _isHitLimit) {
        uint _amt;
        uint limit;
        for (uint i; i < 3; i++) {
            if (_y[i].stratType == _strat) {
                uint _total = _amount + _y[i].amt;
                limit = _y[i].limit;
                if (limit >= _total) {
                    _amt = _amount;
                    _y[i].amt += _amt;
                } else {
                    // console.log("else reached", limit, _y[i].amt);
                    _amt = limit - _y[i].amt;
                    _y[i].amt = limit;
                    //
                    _y[i].apr = 0; // TBD send it to index 2 or 1
                    _isHitLimit = true;
                }
                // console.log("// add amt:");
                // console.log("type", uint(_strat));
                // console.log("total", _total / 1e6);
                // console.log("amount", _amount / 1e6);
                // console.log("amt", _amt / 1e6);
                // console.log("limit", limit / 1e6);
                break;
            }
        }
        return (_amt, _isHitLimit);
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

    function _withdraw(uint _amount) internal {
        // 1
        bool _isC = _isActive(StrategyType.COMPOUND);
        bool _isV2 = _isActive(StrategyType.AAVE_V2);
        bool _isV3 = _isActive(StrategyType.AAVE_V3);

        uint _totalMarkets;
        if (_isC) _totalMarkets++;
        if (_isV2) _totalMarkets++;
        if (_isV3) _totalMarkets++;

        // 2
        YieldVar[3] memory y;
        ReservesVars memory r;
        uint i;

        if (_isC) {
            //
            r.c = _getCompoundVars();
            y[i].stratType = StrategyType.COMPOUND;
            y[i].apr = _getSupplyRate(y[i].stratType);
            y[i].limit = min(
                _balanceOfToken(T.U, address(COMP_USDC)),
                _balanceOfToken(T.C)
            );
            console.log(
                "vars withdraw C",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
            i++;
        }

        if (_isV2) {
            //
            r.v2 = _getAaveV2Vars();
            y[i].stratType = StrategyType.AAVE_V2;
            y[i].apr = _getSupplyRate(y[i].stratType);
            y[i].limit = min(
                _balanceOfToken(T.U, address(AAVE_V2_USDC)),
                _balanceOfToken(T.A2)
            );
            console.log(
                "vars withdraw V2",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
            i++;
        }

        if (_isV3) {
            //
            r.v3 = _getAaveV3Vars();
            y[i].stratType = StrategyType.AAVE_V3;
            y[i].apr = _getSupplyRate(y[i].stratType);
            y[i].limit = min(
                _balanceOfToken(T.U, address(AAVE_V3_USDC)),
                _balanceOfToken(T.A3)
            );
            console.log(
                "vars withdraw V3",
                uint(y[i].stratType),
                y[i].apr / 1e23,
                y[i].limit / 1e6
            );
        }

        // ordering
        _orderYields(y);
        // console.log("order 0 type apr", uint(y[0].stratType), y[0].apr / 1e23);
        // console.log("order 1 type apr", uint(y[1].stratType), y[1].apr / 1e23);
        // console.log("order 2 type apr", uint(y[2].stratType), y[2].apr / 1e23);

        // 3
        if (_totalMarkets == 3) {
            //
            _amount = _disallocateFundsFrom3Markets(y, r, _amount);
            if (_amount > 0)
                _amount = _disallocateFundsFrom2Markets(y, r, _amount);
            if (_amount > 0)
                _disallocateFundsFrom1Market(y, y[0].stratType, _amount);
        } else if (_totalMarkets == 2) {
            //
            _amount = _disallocateFundsFrom2Markets(y, r, _amount);
            _disallocateFundsFrom1Market(y, y[0].stratType, _amount);
        } else if (_totalMarkets == 1) {
            // withdraw
            _disallocateFundsFrom1Market(y, y[0].stratType, _amount);
        } else {
            revert("No Markets Available");
        }

        // deploy respective amounts for each market
        for (i = 0; i < 3; i++) {
            uint _amt = y[i].amt;
            if (_amt > 0) {
                console.log(
                    "disallocate type amt:",
                    uint(y[i].stratType),
                    _amt / 1e6
                );
                _withdraw(y[i].stratType, _amt);
            }
        }
    }

    function _deposit(StrategyType _strategy, uint _amount) internal {
        if (_strategy == StrategyType.COMPOUND) {
            COMP_USDC.supply(USDC, _amount);
        } else if (_strategy == StrategyType.AAVE_V2) {
            aaveV2.deposit(USDC, _amount, address(this), 0);
        } else if (_strategy == StrategyType.AAVE_V3) {
            aaveV3.supply(USDC, _amount, address(this), 0);
        }
    }

    function _withdraw(StrategyType _strategy, uint _amount) internal {
        if (_strategy == StrategyType.COMPOUND) {
            COMP_USDC.withdraw(USDC, _amount);
        } else if (_strategy == StrategyType.AAVE_V2) {
            aaveV2.withdraw(USDC, _amount, address(this));
        } else if (_strategy == StrategyType.AAVE_V3) {
            aaveV3.withdraw(USDC, _amount, address(this));
        }
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

    function _totalAmounts() internal view returns (uint256 _totalAssets) {
        _totalAssets =
            _balanceOfToken(T.U) +
            _balanceOfToken(T.C) +
            _balanceOfToken(T.A2) +
            _balanceOfToken(T.A3);
    }

    function _getSupplyRate(
        StrategyType _strat
    ) internal view returns (uint _apr) {
        if (_strat == StrategyType.COMPOUND) {
            // adapted
            _apr = _compAprAdapter(
                COMP_USDC.getSupplyRate(COMP_USDC.getUtilization()),
                true
            );
        } else if (_strat == StrategyType.AAVE_V2) {
            _apr = aaveV2.getReserveData(USDC).currentLiquidityRate;
        } else if (_strat == StrategyType.AAVE_V3) {
            _apr = aaveV3.getReserveData(USDC).currentLiquidityRate;
        }
    }

    function _loadConstants() internal {
        // compound
        _comp_base = int(COMP_USDC.supplyPerSecondInterestRateBase());
        _comp_rsl = int(COMP_USDC.supplyPerSecondInterestRateSlopeLow());
        _comp_rsh = int(COMP_USDC.supplyPerSecondInterestRateSlopeHigh());
        _comp_kink = int(COMP_USDC.supplyKink());
    }

    function _getCompoundVars()
        internal
        view
        returns (CompoundVars memory vars)
    {
        vars.tS = int(COMP_USDC.totalSupply());
        vars.tB = int(COMP_USDC.totalBorrow());
        vars.base = _comp_base;
        vars.rsl = _comp_rsl;
        vars.rsh = _comp_rsh;
        vars.kink = _comp_kink;
    }

    function _loadAaveV2(address _strat) internal {
        // aave v2
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
        // aave v3
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
            rayMul(
                IVariableDebtToken(_data.variableDebtTokenAddress)
                    .scaledTotalSupply(),
                uint(_data.variableBorrowIndex)
            )
        );
        vars.tD = vars.tVD + vars.tSD;
        vars.aL = int(ERC20(USDC).balanceOf(_data.aTokenAddress));
        vars.subFactor = PERCENT_FACTOR - int(_reserveFactor);
        vars.base = _base_V2;
        vars.vrs1 = _vrs1_V2;
        vars.vrs2 = _vrs2_V2;
        vars.opt = _opt_V2;
        vars.exc = _exc_V2;

        // console.log(">------V2---------");
        // console.log("tSD", uint(vars.tSD));
        // console.log("avgSBR", uint(vars.avgSBR));
        // console.log("tVD", uint(vars.tVD));
        // console.log("subFactor", uint(vars.subFactor));
        // console.log("tD", uint(vars.tD));
        // console.log("aL", uint(vars.aL));
        // console.log("base", uint(vars.base));
        // console.log("vrs1", uint(vars.vrs1));
        // console.log("vrs2", uint(vars.vrs2));
        // console.log("opt", uint(vars.opt));
        // console.log("exc", uint(vars.exc));
        // console.log(">------V2---------");
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
            rayMul(
                IVariableDebtToken(_data.variableDebtTokenAddress)
                    .scaledTotalSupply(),
                uint(_data.variableBorrowIndex)
            )
        );
        vars.tD = vars.tVD + vars.tSD;
        vars.aL = int(ERC20(USDC).balanceOf(_data.aTokenAddress));
        vars.subFactor = PERCENT_FACTOR - int(_reserveFactor);
        vars.base = _base_V3;
        vars.vrs1 = _vrs1_V3;
        vars.vrs2 = _vrs2_V3;
        vars.opt = _opt_V3;
        vars.exc = _exc_V3;

        // console.log(">------V3---------");
        // console.log("tD", uint(vars.tD));
        // console.log("aL", uint(vars.aL));
        // console.log("reserveFactor", _reserveFactor);
        // console.log("base", uint(vars.base));
        // console.log("vrs1", uint(vars.vrs1));
        // console.log("vrs2", uint(vars.vrs2));
        // console.log("opt", uint(vars.opt));
        // console.log("exc", uint(vars.exc));
        // console.log(">------V3---------");
    }

    function _reachApr(
        YieldVar memory _from,
        YieldVar memory _to,
        ReservesVars memory _r,
        YieldVar[3] memory _y,
        uint _amount,
        bool _isDeposit
    ) internal view returns (uint, bool) {
        return
            _reachApr(
                _from,
                _r,
                _y,
                _amount,
                _aprToAmount(_from, _r, _to.apr, _isDeposit),
                _isDeposit
            );
    }

    function _reachApr(
        YieldVar memory _from,
        ReservesVars memory _r,
        YieldVar[3] memory _y,
        uint _amount,
        uint _a, // amount to deploy
        bool _isDeposit
    ) internal view returns (uint _amt, bool _isLimit) {
        // console.log("## REACH APR");
        uint _deployedAmount;
        if (_a >= _amount) {
            (_deployedAmount, _isLimit) = _addAmt(_y, _from.stratType, _amount);
            _amount -= _deployedAmount;
        } else {
            (_deployedAmount, _isLimit) = _addAmt(_y, _from.stratType, _a);
            _amount -= _deployedAmount;
        }
        // console.log("amts _a _amount", _a / 1e6, _amount / 1e6);
        // update apr for 1st and info, simulate a deposit
        _updateVirtualReserve(_from, _r, _deployedAmount, _isDeposit);
        // order for safety
        _orderYields(_y);
        // console.log(
        //     "checkmark type apr amount",
        //     uint(_from.stratType),
        //     _from.apr / 1e23,
        //     _amount
        // );
        _amt = _amount;
    }

    function _disallocateFundsFrom1Market(
        YieldVar[3] memory y,
        StrategyType _strat,
        uint _amount
    ) internal {
        console.log("## DISALLOCATE 1", _amount / 1e6);
        if (_strat == StrategyType.COMPOUND) {
            _addAmt(y, StrategyType.COMPOUND, _amount);
        } else if (_strat == StrategyType.AAVE_V2) {
            _addAmt(y, StrategyType.AAVE_V2, _amount);
        } else if (_strat == StrategyType.AAVE_V3) {
            _addAmt(y, StrategyType.AAVE_V3, _amount);
        }
    }

    function _allocateFundsTo1Market(
        YieldVar[3] memory y,
        StrategyType _strat,
        uint _amount
    ) internal {
        console.log("## ALLOCATE 1", _amount / 1e6);
        if (_strat == StrategyType.COMPOUND) {
            _addAmt(y, StrategyType.COMPOUND, _amount);
        } else if (_strat == StrategyType.AAVE_V2) {
            _addAmt(y, StrategyType.AAVE_V2, _amount);
        } else if (_strat == StrategyType.AAVE_V3) {
            _addAmt(y, StrategyType.AAVE_V3, _amount);
        }
    }

    function _allocateFundsTo2Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt
    ) internal returns (uint _amount) {
        // console.log("## ALLOCATE 2");
        _amount = _amt;
        bool _isBreak = false;
        while (_amount != 0 && !_isBreak) {
            console.log("ALOC2 AMOUNT", _amount / 1e6);
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    r,
                    y,
                    _amount,
                    _amount,
                    true
                );
                break;
            }

            if (lt(y[1].apr, y[0].apr)) {
                console.log("ALLOC2 CHECK 1");
                // i1 < i0
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    y[1],
                    r,
                    y,
                    _amount,
                    true
                );
            } else {
                // pick slowest
                console.log("ALLOC2 CHECK 2");
                // i1 = i0
                uint _seventh = _amount / 7;
                if (_seventh == 0) _seventh = _amount;

                (_amount, _isBreak) = _reachApr(
                    y[0],
                    r,
                    y,
                    _amount,
                    _seventh,
                    true
                );
            }
        }
    }

    // TBD assigning by reference or value

    // amount to be dpeloyed, should be current balance of USDC
    function _allocateFundsTo3Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt
    ) internal returns (uint _amount) {
        // console.log("## ALLOCATE 3");
        _amount = _amt;
        // attempt to bring 0 to 1 rate
        // TBD consider v3 supply cap
        bool _isBreak = false;
        while (_amount != 0 && !_isBreak) {
            console.log("ALLOC3 AMOUNT", _amount / 1e6);
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    r,
                    y,
                    _amount,
                    _amount,
                    true
                );
                break;
            }

            if (lt(y[2].apr, y[1].apr) && lt(y[1].apr, y[0].apr)) {
                console.log("ALLOC3 CHECK 1");
                // i2 < i1 < i0
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    y[1],
                    r,
                    y,
                    _amount,
                    true
                );
            } else if (lt(y[2].apr, y[1].apr) && eq(y[1].apr, y[0].apr)) {
                // console.log("CHECK 2");
                // i2 < i1 = i0
                uint _a0 = _aprToAmount(y[0], r, y[2].apr, true);
                uint _a1 = _aprToAmount(y[1], r, y[2].apr, true);
                if (_a0 + _a1 <= _amount) {
                    console.log("ALLOC3 CHECK 2_1");
                    (_amount, _isBreak) = _reachApr(
                        y[0],
                        y[2],
                        r,
                        y,
                        _amount,
                        true
                    );
                    if (_isBreak) continue;
                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        y[2],
                        r,
                        y,
                        _amount,
                        true
                    );
                } else if (_a0 <= _amount) {
                    console.log("ALLOC3 CHECK 2_2");
                    uint _eighth = _amount / 2;
                    if (_eighth == 0) _eighth = _amount;

                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        r,
                        y,
                        _amount,
                        _eighth,
                        true
                    );
                } else if (_a1 <= _amount) {
                    console.log("ALLOC3 CHECK 2_3");
                    uint _half = _amount / 2;
                    if (_half == 0) _half = _amount;

                    (_amount, _isBreak) = _reachApr(
                        y[0],
                        r,
                        y,
                        _amount,
                        _half,
                        true
                    );
                } else {
                    console.log("ALLOC3 CHECK 2_4");
                    uint _third = _amount / 6;
                    if (_third == 0) _third = _amount;
                    (_amount, _isBreak) = _reachApr(
                        y[0],
                        r,
                        y,
                        _amount,
                        _third,
                        true
                    );
                }
            } else if (eq(y[2].apr, y[1].apr) && lt(y[1].apr, y[0].apr)) {
                // console.log("CHECK 3");
                // i2 = i1 < i0
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    y[1],
                    r,
                    y,
                    _amount,
                    true
                );
            } else {
                console.log(
                    "ALLOC3 CHECK 4",
                    y[0].apr / 1e23,
                    y[1].apr / 1e23,
                    y[2].apr / 1e23
                );

                console.log(
                    // "CHECK amt",
                    y[0].amt / 1e6,
                    y[1].amt / 1e6,
                    y[2].amt / 1e6
                );
                // i2 = i1 = i0
                // pick slowest
                uint _eighth = _amount / 8;
                if (_eighth == 0) _eighth = _amount;
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    r,
                    y,
                    _amount,
                    _eighth,
                    true
                );
            }
        }
    }

    function _disallocateFundsFrom2Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt
    ) internal returns (uint _amount) {
        // console.log("## DISALLOCATE 2");
        _amount = _amt;
        bool _isBreak = false;
        while (_amount != 0 && !_isBreak) {
            console.log("DISALLOC2 AMOUNT", _amount / 1e6);
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = _reachApr(
                    y[1],
                    r,
                    y,
                    _amount,
                    _amount,
                    false
                );
                break;
            }

            if (lt(y[1].apr, y[0].apr)) {
                console.log("DISALLOC2 CHECK 1");
                // i1 < i0
                (_amount, _isBreak) = _reachApr(
                    y[1],
                    y[0],
                    r,
                    y,
                    _amount,
                    false
                );
            } else {
                // pick fastest
                console.log("DISALLOC2 CHECK 2");
                // i1 = i0
                uint _seventh = _amount / 7;
                if (_seventh == 0) _seventh = _amount;

                (_amount, _isBreak) = _reachApr(
                    y[1],
                    r,
                    y,
                    _amount,
                    _seventh,
                    false
                );
            }
        }
    }

    function _disallocateFundsFrom3Markets(
        YieldVar[3] memory y,
        ReservesVars memory r,
        uint _amt
    ) internal returns (uint _amount) {
        //
        // console.log("## DISALLOCATE 3");
        _amount = _amt;
        bool _isBreak = false;

        while (_amount != 0 && !_isBreak) {
            console.log("DISALLOC3 AMOUNT", _amount / 1e6);
            if (_amount <= MINIMUM) {
                (_amount, _isBreak) = _reachApr(
                    y[2],
                    r,
                    y,
                    _amount,
                    _amount,
                    false
                );
                break;
            }

            if (lt(y[2].apr, y[1].apr) && lt(y[1].apr, y[0].apr)) {
                // i2 < i1 < i0
                console.log("DISALLOC3 CHECK 1");
                // _amount = _reachApr(y[2], y[1], r, y, _amount, false);

                (_amount, _isBreak) = _reachApr(
                    y[2],
                    y[1],
                    r,
                    y,
                    _amount,
                    false
                );
            } else if (lt(y[2].apr, y[1].apr) && eq(y[1].apr, y[0].apr)) {
                // i2 < i1 = i0
                console.log("DISALLOC3 CHECK 2");
                // _amount = _reachApr(y[2], y[1], r, y, _amount, false);

                (_amount, _isBreak) = _reachApr(
                    y[2],
                    y[1],
                    r,
                    y,
                    _amount,
                    false
                );
            } else if (eq(y[2].apr, y[1].apr) && lt(y[1].apr, y[0].apr)) {
                // i2 = i1 < i0
                // console.log("DISALLOC3 CHECK 3");
                uint _a1 = _aprToAmount(y[1], r, y[0].apr, false);
                uint _a2 = _aprToAmount(y[2], r, y[0].apr, false);
                if (_a2 + _a1 <= _amount) {
                    console.log("DISALLOC3 CHECK 3_1");
                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        y[0],
                        r,
                        y,
                        _amount,
                        false
                    );
                    (_amount, _isBreak) = _reachApr(
                        y[2],
                        y[0],
                        r,
                        y,
                        _amount,
                        false
                    );

                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        y[0],
                        r,
                        y,
                        _amount,
                        false
                    );
                    if (_isBreak) continue;
                    (_amount, _isBreak) = _reachApr(
                        y[2],
                        y[0],
                        r,
                        y,
                        _amount,
                        false
                    );
                } else if (_a2 <= _amount) {
                    console.log("DISALLOC3 CHECK 3_2");
                    // _amount = _reachApr(y[1], y[0], r, y, _amount, false);

                    uint _eighth = _amount / 2;
                    if (_eighth == 0) _eighth = _amount;

                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        r,
                        y,
                        _amount,
                        _eighth,
                        false
                    );
                } else if (_a1 <= _amount) {
                    console.log("DISALLOC3 CHECK 3_3");
                    // _amount = _reachApr(y[2], y[0], r, y, _amount, false);

                    uint _eighth = _amount / 2;
                    if (_eighth == 0) _eighth = _amount;

                    (_amount, _isBreak) = _reachApr(
                        y[2],
                        r,
                        y,
                        _amount,
                        _eighth,
                        false
                    );
                } else {
                    console.log("DISALLOC3 CHECK 3_4");
                    uint _third = _amount / 6;
                    if (_third == 0) _third = _amount;
                    (_amount, _isBreak) = _reachApr(
                        y[1],
                        r,
                        y,
                        _amount,
                        _third,
                        false
                    );
                }
            } else {
                console.log("DISALLOC3 CHECK 4");
                // i2 = i1 = i0
                // pick fastest
                uint _eighth = _amount / 8;
                if (_eighth == 0) _eighth = _amount;
                (_amount, _isBreak) = _reachApr(
                    y[0],
                    r,
                    y,
                    _amount,
                    _eighth,
                    false
                );
            }
        }
    }

    // TBD
    function _amountToApr(
        YieldVar memory _y,
        ReservesVars memory _r,
        uint _amount,
        bool _isDeposit
    ) public view returns (uint _apr) {
        if (_y.stratType == StrategyType.COMPOUND) {
            _apr = _compAprAdapter(
                _compAmountToSupplyRate(_r.c, _amount, _isDeposit),
                true
            );
            // console.log("_apr c", _apr / 1e23);
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            _apr = uint(_calcAaveApr(_r.v2, int256(_amount), _isDeposit));
            // console.log("_apr v2", _apr / 1e23);
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            _apr = uint(_calcAaveApr(_r.v3, int256(_amount), _isDeposit));
            // console.log("_apr v3", _apr / 1e23);
        }
    }

    function _aprToAmount(
        YieldVar memory _y,
        ReservesVars memory _r,
        uint _apr,
        bool _isDeposit
    ) public view returns (uint _amount) {
        if (_y.stratType == StrategyType.COMPOUND) {
            _amount = _calcCompoundInterestToAmount(_r.c, _apr, _isDeposit);
            // console.log("comp", _amount / 1e6);
        } else if (_y.stratType == StrategyType.AAVE_V2) {
            _amount = _calcAaveInterestToAmount(_r.v2, int(_apr), _isDeposit);
            // console.log("aaveV2", _amount / 1e6);
        } else if (_y.stratType == StrategyType.AAVE_V3) {
            _amount = _calcAaveInterestToAmount(_r.v3, int(_apr), _isDeposit);
            // console.log("aaveV3", _amount / 1e6);
        }
        // console.log("input rate:", _apr / 1e23, _amount / 1e6);
    }

    function _calcAaveInterestToAmount(
        AaveVars memory v,
        int _apr,
        bool _isDeposit
    ) public view returns (uint _amount) {
        // console.log("---------------");
        int _amount0 = int(abs(_calcAmount(v, true, _apr)));
        // console.log("---------------");
        int _amount1 = int(abs(_calcAmount(v, false, _apr)));
        // console.log("---------------");
        int sr0 = _calcAaveApr(v, _amount0, _isDeposit);
        int sr1 = _calcAaveApr(v, _amount1, _isDeposit);

        // console.log("aave amount0", uint(_amount0), uint(_amount0) / 1e6);
        // console.log("aave amount1", uint(_amount1), uint(_amount1) / 1e6);

        // console.log("sr0", uint(sr0), uint(sr0) / 1e23);
        // console.log("sr1", uint(sr1), uint(sr1) / 1e23);
        _amount = abs(_apr - sr0) < abs(_apr - sr1)
            ? uint(_amount0)
            : uint(_amount1);
        // console.log("aave amount", uint(_amount) / 1e6);
    }

    // used by gelato checker, to determine if it needs to be called
    function status() external view returns (bool _keeperStatus) {
        return (_isKeeperActive);
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
