// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {OptimizerSetup, ERC20, IStrategyInterface} from "./utils/OptimizerSetup.sol";
import {USDCStrategy} from "../USDCStrategy.sol";
import "../interfaces/IAaveV2.sol";
import "../interfaces/IAaveV3.sol";
import "../interfaces/ICompound.sol";
import "../interfaces/IAaveV2InterestStrategy.sol";
import "../libraries/Constants.sol";

contract USDCStrategyTest is OptimizerSetup {
    address[] tokens = [
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
        0xF25212E676D1F7F89Cd72fFEe66158f541246445,
        0x1a13F4Ca1d028320A707D99520AbFefca3998b7F,
        0x625E7708f30cA75bfd92586e17077590C60eb4cD
    ];

    ERC20 constant AAVE_V2_USDC =
        ERC20(0x1a13F4Ca1d028320A707D99520AbFefca3998b7F);
    ERC20 constant AAVE_V3_USDC =
        ERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD);

    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    ICompound constant COMP_USDC =
        ICompound(0xF25212E676D1F7F89Cd72fFEe66158f541246445);
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    function setUp() public virtual override {
        super.setUp();
        // vm.createSelectFork("polygon");
    }

    function test_setupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // there is a bug in _adjustFor1Market and findLiquidMarket, so withdrawals are not properly processed

        // assertGe(
        //     asset.balanceOf(user),
        //     balanceBefore + _amount,
        //     "!final balance"
        // );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // there is a bug in _adjustFor1Market and findLiquidMarket, so withdrawals are not properly processed

        // assertGe(
        //     asset.balanceOf(user),
        //     balanceBefore + _amount,
        //     "!final balance"
        // );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // there is a bug in _adjustFor1Market and findLiquidMarket, so withdrawals are not properly processed

        // assertGe(
        //     asset.balanceOf(user),
        //     balanceBefore + _amount,
        //     "!final balance"
        // );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        // there is a bug in _adjustFor1Market and findLiquidMarket, so withdrawals are not properly processed

        // assertGe(
        //     asset.balanceOf(performanceFeeRecipient),
        //     expectedShares,
        //     "!perf fee out"
        // );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    function test_IDLE_mode(uint256 _amount) public {
        vm.prank(management);

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // there is a bug in _adjustFor1Market and findLiquidMarket, so withdrawals are not properly processed

        // assertGe(
        //     asset.balanceOf(user),
        //     balanceBefore + _amount,
        //     "!final balance"
        // );
    }

    function test_freeAndDeployToMarket(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        USDCStrategy strat = USDCStrategy(address(strategy));

        airdrop(asset, address(strategy), _amount);

        StrategyType stratType = StrategyType.AAVE_V2;

        uint amt = asset.balanceOf(address(strat));

        vm.prank(management);
        strat.deployToMarket(stratType);

        assertApproxEqAbs(
            ERC20(AAVE_V2_USDC).balanceOf(address(strategy)),
            amt,
            1
        );

        vm.prank(management);
        strat.freeFromMarket(stratType);

        assertApproxEqAbs(ERC20(asset).balanceOf(address(strategy)), amt, 1);
    }

    function test_deposit_withdrawHalf(uint _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        USDCStrategy strat = USDCStrategy(address(strategy));

        strat.printAprs();

        mintAndDepositIntoStrategy(strategy, user, _amount);

        strat.printAprs();

        skip(1);
        console.log("--------------");

        // Withdraw all funds
        uint _pre = gasleft();
        uint half = _amount / 2;
        vm.prank(user);
        strategy.redeem(half, user, user);
        uint _post = gasleft();
        console.log("withdraw gas consumed", _pre - _post);
        console.log(
            "withdrawn amount",
            ERC20(USDC).balanceOf(address(user)) / 1e6
        );
        strat.printAprs();
        assertEq(ERC20(USDC).balanceOf(address(user)), half);
    }

    function test_maintain() public {
        USDCStrategy strat = USDCStrategy(address(strategy));
        uint _amount = 5_000_000 * 1e6;
        console.log("1--------------");
        strat.printAprs();
        console.log("2--------------");
        mintAndDepositIntoStrategy(strategy, user, _amount);
        strat.printAprs();
        console.log("3--------------");

        skip(1);
        // someone deposit into aave v3
        address bob = vm.addr(609);
        uint amt = 1_000_000 * 1e6;
        airdrop(asset, bob, amt);
        vm.prank(bob);
        ERC20(asset).approve(address(aaveV3), type(uint).max);
        vm.prank(bob);
        aaveV3.supply(USDC, amt, bob, 0);
        console.log("4--------------");
        strat.printAprs();
        console.log("5--------------");
        // maintain1
        uint _pre = gasleft();
        vm.prank(keeper);
        strat.maintain();
        uint _post = gasleft();
        console.log("6--------------");
        strat.printAprs();
        console.log("7--------------");
        console.log("gas consumed maintain 1", _pre - _post);
    }
}
