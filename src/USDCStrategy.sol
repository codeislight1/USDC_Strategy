// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAaveV2.sol";
import "./interfaces/IAaveV3.sol";
import "./interfaces/ICompound.sol";

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

contract USDCStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    enum StrategyType {
        IDLE,
        COMPOUND,
        AAVE_V2,
        AAVE_V3
    }

    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    ICompound constant COMP_USDC =
        ICompound(0xF25212E676D1F7F89Cd72fFEe66158f541246445);

    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant AAVE_V2_USDC = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address constant AAVE_V3_USDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;

    uint constant COMP100APR = 317100000 * 100;
    uint constant RAY = 1e27;

    uint MAX_CAP_AAVE_V3 = 150_000_000e6;
    uint public lastExecuted;

    StrategyType public highest;
    bool _isKeeperActive;

    constructor() BaseStrategy(USDC, "USDC strategy") {
        ERC20(USDC).approve(address(aaveV2), type(uint).max);
        ERC20(USDC).approve(address(aaveV3), type(uint).max);
        ERC20(USDC).approve(address(COMP_USDC), type(uint).max);

        highest = _getHighestYield();
        lastExecuted = block.timestamp;
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
        _deposit(highest, _amount);
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
        // uint _bal = ERC20(USDC).balanceOf(address(this));
        // if (_bal < _amount) {
        //     _withdraw(highest, _amount - _bal);
        // }
        _withdraw(highest, _amount);
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
    ) public pure override returns (uint256) {
        return type(uint).max;
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
            ERC20(USDC).balanceOf(address(this)) +
            min(
                ERC20(address(COMP_USDC)).balanceOf(address(this)),
                ERC20(USDC).balanceOf(address(COMP_USDC))
            ) +
            min(
                ERC20(AAVE_V2_USDC).balanceOf(address(this)),
                ERC20(USDC).balanceOf(address(AAVE_V2_USDC))
            ) +
            min(
                ERC20(AAVE_V3_USDC).balanceOf(address(this)),
                ERC20(USDC).balanceOf(address(AAVE_V3_USDC))
            );
    }

    /**
     * @dev Optional function for a strategist to override that will
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
        _withdraw(highest, _amount);
    }

    function execute() external onlyKeepers {
        StrategyType _highest = _getHighestYield();
        if (highest != _highest) {
            // withdraw
            uint _amount = _getAmount(highest);
            if (_amount > 0) _withdraw(highest, _amount);
            // deposit
            highest = _highest;
            lastExecuted = block.timestamp;
            _amount = ERC20(USDC).balanceOf(address(this));
            if (_amount > 0) _deposit(_highest, _amount);
        }
    }

    function setHighestYield(StrategyType _strategy) external onlyManagement {
        if (highest != _strategy) {
            // withdraw
            uint _amount = _getAmount(highest);
            if (_amount > 0) _withdraw(highest, _amount);
            // deposit
            highest = _strategy;
            _amount = ERC20(USDC).balanceOf(address(this));
            if (_amount > 0) _deposit(_strategy, _amount);
        }
    }

    function freeFromMarket(StrategyType _strategy) external onlyManagement {
        uint _amount = _getAmount(_strategy);
        if (_amount > 0) _withdraw(_strategy, _amount);
    }

    function deployToMarket(StrategyType _strategy) external onlyManagement {
        uint _amount = ERC20(USDC).balanceOf(address(this));
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

    function setKepperActive(bool _active) external onlyManagement {
        require(_isKeeperActive != _active);
        _isKeeperActive = _active;
    }

    function _getAmount(
        StrategyType _strategy
    ) internal view returns (uint _amount) {
        if (_strategy == StrategyType.COMPOUND)
            _amount = ERC20(address(COMP_USDC)).balanceOf(address(this));
        else if (_strategy == StrategyType.AAVE_V2)
            _amount = ERC20(AAVE_V2_USDC).balanceOf(address(this));
        else if (_strategy == StrategyType.AAVE_V3)
            _amount = ERC20(AAVE_V3_USDC).balanceOf(address(this));
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
            uint _supplyCap = ((_data >> 116) & 68719476735) * 10 ** 6;
            _active =
                (((_data >> 56) & 1) == 1) &&
                !(((_data >> 57) & 1) == 1) &&
                !(((_data >> 60) & 1) == 1) &&
                ERC20(AAVE_V3_USDC).totalSupply() < _supplyCap;
        }
    }

    function _totalAmounts() internal view returns (uint256 _totalAssets) {
        _totalAssets =
            ERC20(USDC).balanceOf(address(this)) +
            ERC20(address(COMP_USDC)).balanceOf(address(this)) +
            ERC20(AAVE_V2_USDC).balanceOf(address(this)) +
            ERC20(AAVE_V3_USDC).balanceOf(address(this));
    }

    function _getHighestYield() internal view returns (StrategyType _highest) {
        // compound
        uint _supplyRate = (COMP_USDC.getSupplyRate(
            COMP_USDC.getUtilization()
        ) * RAY) / COMP100APR;
        uint _maxRate = _supplyRate;
        if (_isActive(StrategyType.COMPOUND)) _highest = StrategyType.COMPOUND;
        // Aave V2
        _supplyRate = aaveV2.getReserveData(USDC).currentLiquidityRate;
        if (_supplyRate > _maxRate && _isActive(StrategyType.AAVE_V2)) {
            _highest = StrategyType.AAVE_V2;
            _maxRate = _supplyRate;
        }
        // Aave V3
        _supplyRate = aaveV3.getReserveData(USDC).currentLiquidityRate;
        if (_supplyRate > _maxRate && _isActive(StrategyType.AAVE_V3)) {
            _highest = StrategyType.AAVE_V3;
        }
    }

    // used by gelato checker, to determine if it needs to be called
    function status()
        external
        view
        returns (bool _isYieldChanged, bool _keeperStatus)
    {
        return (highest != _getHighestYield(), _isKeeperActive);
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}
