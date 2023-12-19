// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./StrategyCore.sol";
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

contract USDCStrategy is BaseStrategy, StrategyCore {
    using SafeERC20 for ERC20;
    using MathUtils for uint;

    bool _isKeeperActive;
    uint public lastExecuted;

    constructor() BaseStrategy(USDC, "USDC strategy") {
        // approve markets
        ERC20(USDC).approve(address(aaveV2), type(uint).max);
        ERC20(USDC).approve(address(aaveV3), type(uint).max);
        ERC20(USDC).approve(address(COMP_USDC), type(uint).max);

        // load markets
        _loadCompound();
        _loadAaveV2(aaveV2.getReserveData(USDC).interestRateStrategyAddress);
        _loadAaveV3(aaveV3.getReserveData(USDC).interestRateStrategyAddress);

        // init
        lastExecuted = block.timestamp;
        _isKeeperActive = true;
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
        _totalAssets =
            _balanceOfToken(T.U) +
            _balanceOfToken(T.C) +
            _balanceOfToken(T.A2) +
            _balanceOfToken(T.A3);
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
                    ? _balanceOfToken(T.C).min(
                        _balanceOfToken(T.U, address(COMP_USDC))
                    )
                    : 0
            ) +
            (
                _isActive(StrategyType.AAVE_V2)
                    ? _balanceOfToken(T.A2).min(
                        _balanceOfToken(T.U, AAVE_V2_USDC)
                    )
                    : 0
            ) +
            (
                _isActive(StrategyType.AAVE_V3)
                    ? _balanceOfToken(T.A3).min(
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

    function _deposit(uint _amount) internal {
        (
            uint _totalMarkets,
            ReservesVars memory r,
            YieldVar[3] memory y
        ) = _loadDataSimulation(true);

        _simulate(true, _totalMarkets, _amount, r, y);

        for (uint i; i < 3; i++) {
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

    function _withdraw(uint _amount) internal {
        (
            uint _totalMarkets,
            ReservesVars memory r,
            YieldVar[3] memory y
        ) = _loadDataSimulation(false);

        _simulate(false, _totalMarkets, _amount, r, y);

        // deploy respective amounts for each market
        for (uint i = 0; i < 3; i++) {
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

    // used by gelato checker, to determine if it needs to be called
    function status() external view returns (bool _keeperStatus) {
        return (_isKeeperActive);
    }

    // Only Management
    function freeFromMarket(T _token) external onlyManagement {
        uint _amount = _balanceOfToken(_token);
        if (_amount > 0) _withdraw(_amount);
    }

    function deployToMarket(StrategyType _strategy) external onlyManagement {
        uint _amount = _balanceOfToken(T.U);
        if (_amount > 0) _deposit(_strategy, _amount);
    }

    function switchKepperActive(bool _active) external onlyManagement {
        require(_isKeeperActive != _active);
        _isKeeperActive = _active;
    }
}
