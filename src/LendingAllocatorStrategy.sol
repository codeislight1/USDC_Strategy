// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAaveV2.sol";
import "./interfaces/IAaveV3.sol";
import "./interfaces/ICompound.sol";
import "./interfaces/IAaveV2InterestStrategy.sol";
import "./interfaces/IAaveV3InterestStrategy.sol";
import "./interfaces/IStableDebtToken.sol";
import "./interfaces/IVariableDebtToken.sol";
import "./libraries/YieldUtils.sol";
import "./libraries/MathUtils.sol";
import "./interfaces/IStrategyImplementation.sol";

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

/** @author codeislight
 *  Optimized yield allocator contract across various markets, each market has its own specific logic that implements
 *  IStrategyImplementation interface, thus makes it easier to expand and integrate between various strategies and markets.
 */
contract LendingAllocatorStrategy is BaseStrategy {
    using SafeERC20 for ERC20;
    using MathUtils for uint;
    using YieldUtils for YieldVars;
    using YieldUtils for YieldVars[3];

    struct MarketData {
        IStrategyImplementation impl;
        address market;
    }

    // TODO include strategy name in constructooor
    State _state;
    uint public immutable TOTAL_MARKETS;
    mapping(uint8 => MarketData) public markets;

    constructor(
        address _asset,
        IStrategyImplementation[] memory impls
    ) BaseStrategy(_asset, "Strategy") {
        // approve markets
        uint len = impls.length;
        require(len == 3 || len == 2, "!impl");
        require(_asset != address(0), "0Address");
        // store and approve markets
        for (uint8 i; i < impls.length; i++) {
            require(impls[i].getAssetAddress() == _asset, "!asset");
            impls[i].setStrategy(address(this));
            address market = impls[i].getMarketAddress();
            markets[i] = MarketData({impl: impls[i], market: market});
            ERC20(asset).approve(market, type(uint).max);
        }
        TOTAL_MARKETS = len;
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
        _totalAssets = ERC20(asset).balanceOf(address(this));
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            _totalAssets += markets[i].impl.getStrategyReceiptBalance();
        }
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

    // function _tend(uint256 _totalIdle) internal override {
    //     //
    // }

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
     * @return limit_ The available amount the `_owner` can deposit in terms of `asset`
     *
     */

    function availableDepositLimit(
        address
    ) public view override returns (uint256 limit_) {
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            // TODO place always at market id 0, one with unlimited deposit
            uint _limit = markets[i].impl.getDepositLimit();
            if (_limit == type(uint248).max) return type(uint256).max;
            limit_ += _limit;
        }
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
     * @return limit_ The available amount that can be withdrawn in terms of `asset`
     *
     */

    function availableWithdrawLimit(
        address
    ) public view override returns (uint256 limit_) {
        limit_ = ERC20(asset).balanceOf(address(this));
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            limit_ += markets[i].impl.getWithdrawLimit();
        }
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

    function _loadDataSimulation(
        bool isDeposit
    ) internal view returns (uint markets_, YieldVars[3] memory y) {
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            IStrategyImplementation impl = markets[i].impl;
            if (impl.isActive()) {
                y[i] = impl.loadMarket(i, isDeposit);
                if (y[i].apr != 0) markets_++;
            }
        }

        y.orderYields();
    }

    /** @notice allocates funds according to the deposit mode, where:
     *  mode = NO_ALLOCATION, nothing allocated, awaiting for keeper to do so.
     *  mode = PARTIAL_ALLOCATION, we bring i0 to i1':
     *  |-------i2
     *  |------------------i1
     *  |------------------i0'-<-<-<-<-i0
     *  |------------------------------------------>
     *  mode = FULL_ALLOCATION, we allocate according to amount from higher to lowest rate
     * @param _amount to be allocated.
     */
    function _deposit(uint _amount) internal {
        if (_state == State.PARTIAL_ALLOCATION) {
            (uint _totalMarkets, YieldVars[3] memory y) = _loadDataSimulation(
                true
            );
            require(_totalMarkets > 0, "no markets");
            MarketData memory mrkt = markets[y[0].id];
            uint amount = y[0].limit < _amount ? y[0].limit : _amount;
            if (_totalMarkets > 1) {
                // get amount to move 0 to 1
                uint _amtTo1 = mrkt.impl.getAmount(y[0].r, y[1].apr, true);
                amount = _amtTo1 < amount ? _amtTo1 : amount;
            }
            _deposit(mrkt, amount);
        } else if (_state == State.FULL_ALLOCATION) {
            (uint _totalMarkets, YieldVars[3] memory y) = _loadDataSimulation(
                true
            );
            require(_totalMarkets > 0, "no markets");
            for (uint8 i; i < TOTAL_MARKETS; i++) {
                if (y[i].apr == 0) continue;
                MarketData memory mrkt = markets[y[i].id];
                // console.log("_amount", _amount);
                uint _amt = y[i].limit > _amount ? _amount : y[i].limit;
                if (_amt > 0) {
                    _amount -= _amt;
                    // console.log("amt limit", y[i].id, _amt, y[i].limit);
                    _deposit(mrkt, _amt);
                }

                if (_amount == 0) break;
            }
        }
    }

    /**@notice withdraw an `_amount` from the strategy, regardless of the rate
     * @param _amount to be withdrawn
     */
    function _withdraw(uint _amount) internal {
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            MarketData memory mrkt = markets[i];
            if (!mrkt.impl.isActive()) continue;
            uint receiptAmount = mrkt.impl.getStrategyReceiptBalance();
            uint _amt = receiptAmount > _amount ? _amount : receiptAmount;

            if (_amt > 0) {
                _amount -= _amt;
                _withdraw(mrkt, _amt);
            }
            if (_amount == 0) break;
        }
    }

    function _deposit(MarketData memory mrkt, uint amount) internal {
        console.log("//= allocate", amount);
        (bool success, ) = mrkt.market.call(
            mrkt.impl.encodeDepositCalldata(amount)
        );
        require(success, "!depositCall");
    }

    function _withdraw(MarketData memory mrkt, uint amount) internal {
        console.log("//= disallocate", amount);
        (bool success, ) = mrkt.market.call(
            mrkt.impl.encodeWithdrawCalldata(amount)
        );
        require(success, "!withdrawCall");
    }

    /** @notice management-restricted used to free funds from markets in case of emergencies
     * @param id market id to free funds from
     */
    function freeFromMarket(uint8 id) external onlyManagement {
        require(id < TOTAL_MARKETS, "!T");
        uint _amount = markets[id].impl.getStrategyReceiptBalance();
        if (_amount > 0) {
            _withdraw(markets[id], _amount);
        }
    }

    /** @notice management-restricted used to deploy funds to markets in case of emergencies
     * @param id market id to deploy funds to
     */
    function deployToMarket(uint8 id) external onlyManagement {
        require(id < TOTAL_MARKETS, "!T");
        uint _amount = ERC20(asset).balanceOf(address(this));
        if (_amount > 0) {
            _deposit(markets[id], _amount);
        }
    }

    /** @notice update deposit state
     *  @param _newState new deposit state to be updated
     */
    function setDepositState(State _newState) external onlyManagement {
        require(_newState != _state, "!s");
        _state = _newState;
    }

    /** @notice allocates IDLE funds based on the percentages passed in by a keeper.
     *  @dev The keeper should provide ids for markets which are active, and percentages that
     *  would allocate funds for an optimal rate for the 3 markets.
     *  @param data array of keep data containing an id and percentage of amount to allocate.
     */
    function keepIDLE(KeepData[] memory data) external onlyKeepers {
        console.log("_KEEPIDLE_");
        // deploy IDLE funds
        uint len = data.length;
        uint _amount = asset.balanceOf(address(this));
        require(len <= TOTAL_MARKETS, "!len");

        // check
        uint totalPercentages;
        for (uint8 i; i < len; i++) {
            totalPercentages += data[i].percent;
        }
        require(totalPercentages == 1 ether, "!100%");
        // allocate
        uint totalAmount;
        for (uint i; i < len; i++) {
            uint finalAmount;
            // TODO there is 1 which might be left
            finalAmount = (_amount * data[i].percent) / 1 ether;
            console.log("value", _amount, totalAmount, data[i].percent);
            console.log("isIt", i == len - 1);
            totalAmount += finalAmount;
            _deposit(markets[data[i].id], finalAmount);
        }
    }

    /** @notice equilibrate the markets interest based on the percentages passed in by a keeper.
     *  @dev The keeper should provide ids for markets which are active, and percentages totals to 1e18, that
     *  would bring the interest rate for the 3 markets at an optimal rate possible.
     *  @param data array of keep data containing an id and percentage of amount to allocate.
     */
    function keep(KeepData[] memory data) external onlyKeepers {
        console.log("_KEEP_");
        uint len = data.length;
        require(len <= TOTAL_MARKETS, "!len");
        uint totalPercentages;
        uint totalAmount = availableWithdrawLimit(address(0));
        int[] memory amts = new int[](TOTAL_MARKETS);
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            uint percent;
            for (uint j; j < data.length; j++) {
                if (data[j].id == i) percent = data[j].percent;
            }
            uint amt = (percent * totalAmount) / 1 ether;
            amts[i] =
                int(amt) -
                int(markets[i].impl.getStrategyReceiptBalance());
            totalPercentages += percent;
        }
        require(totalPercentages == 1 ether, "!100%");
        console.log("keep_totalAmount", totalAmount);
        // withdraw from over allocated markets
        uint num;
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            if (amts[i] < 0) {
                num++;
                uint amount = uint(-amts[i]);
                console.log("WITHDRAW id amount", i, amount);
                // withdraw difference
                _withdraw(markets[i], amount);
            }
        }

        // deposit into under allocated markets
        for (uint8 i; i < TOTAL_MARKETS; i++) {
            if (amts[i] > 0) {
                num++;
                uint amount = uint(amts[i]);
                console.log("DEPOSIT id amount", i, amount);
                // TODO improve and fix
                // if (data.length > 1 && num == TOTAL_MARKETS) amount++;
                // deposit difference
                _deposit(markets[i], amount);
            }
        }
    }

    // TODO add functionality to getUnclaimedYield for compound and swap it
}
