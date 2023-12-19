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

    uint constant COMP100APR = 317100000 * 100;
    uint constant RAY = 1e27;

    function setUp() public virtual override {
        vm.createSelectFork("polygon");
    }

    // function test_setupStrategyOK() public {
    //     super.setUp();
    //     console.log("address of strategy", address(strategy));
    //     assertTrue(address(0) != address(strategy));
    //     assertEq(strategy.asset(), address(asset));
    //     assertEq(strategy.management(), management);
    //     assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
    //     assertEq(strategy.keeper(), keeper);
    // }

    // modifier setAllYieldSources() {
    //     for (uint i = 1; i < 4; i++) {
    //         super.setUp();
    //         vm.prank(management);
    //         USDCStrategy(address(strategy)).setHighestYield(
    //             USDCStrategy.StrategyType(i)
    //         );
    //         _;
    //     }
    // }

    // function test_operation(uint256 _amount) public setAllYieldSources {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
    //     checkStrategyTotals(strategy, _amount, _amount, 0);

    //     // Earn Interest
    //     skip(1 days);

    //     // Report profit
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();
    //     // Check return Values
    //     assertGt(profit, 0, "!profit");
    //     assertEq(loss, 0, "!loss");

    //     skip(strategy.profitMaxUnlockTime());

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     assertGe(
    //         asset.balanceOf(user),
    //         balanceBefore + _amount,
    //         "!final balance"
    //     );
    // }

    // function test_profitableReport(
    //     uint256 _amount,
    //     uint16 _profitFactor
    // ) public setAllYieldSources {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
    //     _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
    //     checkStrategyTotals(strategy, _amount, _amount, 0);

    //     // Earn Interest
    //     skip(1 days);

    //     // TODO: implement logic to simulate earning interest.
    //     uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
    //     airdrop(asset, address(strategy), toAirdrop);

    //     // Report profit
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();

    //     // Check return Values
    //     assertGe(profit, toAirdrop, "!profit");
    //     assertEq(loss, 0, "!loss");

    //     skip(strategy.profitMaxUnlockTime());

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     assertGe(
    //         asset.balanceOf(user),
    //         balanceBefore + _amount,
    //         "!final balance"
    //     );
    // }

    // function test_profitableReport_withFees(
    //     uint256 _amount,
    //     uint16 _profitFactor
    // ) public setAllYieldSources {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
    //     _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

    //     // Set protocol fee to 0 and perf fee to 10%
    //     setFees(0, 1_000);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
    //     checkStrategyTotals(strategy, _amount, _amount, 0);

    //     // Earn Interest
    //     skip(1 days);

    //     // TODO: implement logic to simulate earning interest.
    //     uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
    //     airdrop(asset, address(strategy), toAirdrop);

    //     // Report profit
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();
    //     // Check return Values
    //     assertGe(profit, toAirdrop, "!profit");
    //     assertEq(loss, 0, "!loss");

    //     skip(strategy.profitMaxUnlockTime());

    //     // Get the expected fee
    //     uint256 expectedShares = (profit * 1_000) / MAX_BPS;

    //     assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     assertGe(
    //         asset.balanceOf(user),
    //         balanceBefore + _amount,
    //         "!final balance"
    //     );

    //     vm.prank(performanceFeeRecipient);
    //     strategy.redeem(
    //         expectedShares,
    //         performanceFeeRecipient,
    //         performanceFeeRecipient
    //     );

    //     checkStrategyTotals(strategy, 0, 0, 0);

    //     assertGe(
    //         asset.balanceOf(performanceFeeRecipient),
    //         expectedShares,
    //         "!perf fee out"
    //     );
    // }

    // function test_tendTrigger(uint256 _amount) public setAllYieldSources {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     (bool trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     (trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // Skip some time
    //     skip(1 days);

    //     (trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     vm.prank(keeper);
    //     strategy.report();

    //     (trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // Unlock Profits
    //     skip(strategy.profitMaxUnlockTime());

    //     (trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     (trigger, ) = strategy.tendTrigger();
    //     assertTrue(!trigger);
    // }

    // function test_IDLE_mode(uint256 _amount) public {
    //     super.setUp();
    //     vm.prank(management);
    //     USDCStrategy(address(strategy)).setHighestYield(
    //         USDCStrategy.StrategyType(0)
    //     );

    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
    //     checkStrategyTotals(strategy, _amount, 0, _amount);

    //     // Earn Interest
    //     skip(1 days);

    //     // Report profit
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();
    //     // Check return Values
    //     assertEq(profit, 0, "!profit");
    //     assertEq(loss, 0, "!loss");

    //     skip(strategy.profitMaxUnlockTime());

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     assertGe(
    //         asset.balanceOf(user),
    //         balanceBefore + _amount,
    //         "!final balance"
    //     );
    // }

    // function test_highestYieldStateTransition(uint256 _amount) public {
    //     super.setUp();
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
    //     // deposit
    //     for (uint i = 0; i < 4; i++) {
    //         vm.prank(management);
    //         USDCStrategy(address(strategy)).setHighestYield(
    //             USDCStrategy.StrategyType(i)
    //         );
    //         vm.prank(keeper);
    //         strategy.tend();
    //         // Deposit into strategy
    //         mintAndDepositIntoStrategy(strategy, user, _amount);
    //         // Withdraw 50%
    //         vm.prank(user);
    //         strategy.redeem((_amount * 5) / 10, user, user);
    //         for (uint j = 0; j < 4; j++) {
    //             if (i == j) continue;
    //             vm.prank(management);
    //             USDCStrategy(address(strategy)).setHighestYield(
    //                 USDCStrategy.StrategyType(j)
    //             );
    //             vm.prank(keeper);
    //             strategy.tend();
    //             // Deposit into strategy
    //             mintAndDepositIntoStrategy(strategy, user, _amount);
    //             // withdraw all
    //             vm.prank(user);
    //             strategy.redeem(_amount, user, user);
    //             // transition back
    //             vm.prank(management);
    //             USDCStrategy(address(strategy)).setHighestYield(
    //                 USDCStrategy.StrategyType(i)
    //             );
    //             vm.prank(keeper);
    //             strategy.tend();
    //         }
    //     }
    // }

    // function test_freeAndDeployToMarket(uint256 _amount) public {
    //     super.setUp();
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     mintAndDepositIntoStrategy(strategy, user, _amount);
    //     USDCStrategy strat = USDCStrategy(address(strategy));
    //     USDCStrategy.StrategyType _highest = strat.highest();
    //     vm.prank(management);
    //     strat.freeFromMarket(_highest);
    //     _highest = USDCStrategy.StrategyType(
    //         uint(_highest) == 3 ? 1 : uint(_highest) + 1
    //     );
    //     vm.prank(management);
    //     strat.deployToMarket(_highest);
    // }

    // function test_rateChange() public {
    //     super.setUp();
    //     uint _amount = 1_000_000 * 1e6;
    //     USDCStrategy strat = USDCStrategy(address(strategy));
    //     console.log("rate change:");
    //     strat.status();
    //     uint p1 = 0;
    //     uint p2 = 3806639602;
    //     uint p3 = 6193360398;
    //     uint total = p1 + p2 + p3;
    //     airdrop(asset, user, _amount);
    //     vm.startPrank(user);
    //     ERC20(USDC).approve(address(aaveV2), type(uint).max);
    //     ERC20(USDC).approve(address(aaveV3), type(uint).max);
    //     ERC20(USDC).approve(address(COMP_USDC), type(uint).max);
    //     // COMP_USDC.supply(USDC, (_amount * p1) / total);
    //     aaveV2.deposit(USDC, (_amount * p2) / total, user, 0);
    //     aaveV3.supply(USDC, (_amount * p3) / total, user, 0);
    //     vm.stopPrank();
    //     strat.status();
    // }

    // function test_rateCompound() public {
    //     super.setUp();
    //     uint apr = 2273824356;
    //     // 2581088947 -
    //     // 80% - 824454591 -
    //     apr = (apr * RAY) / COMP100APR;
    //     USDCStrategy strat = USDCStrategy(address(strategy));
    //     uint a = strat._aprToAmount(
    //         USDCStrategy.StrategyType.COMPOUND,
    //         apr
    //     );
    //     console.log("rates:");
    //     console.log(a);
    //     uint _amount = a;
    //     airdrop(asset, user, _amount);
    //     vm.startPrank(user);
    //     ERC20(USDC).approve(address(COMP_USDC), type(uint).max);
    //     uint utilization = COMP_USDC.getUtilization();
    //     console.log("supply rate before", COMP_USDC.getSupplyRate(utilization));
    //     console.log("utilization before", utilization);
    //     COMP_USDC.supply(USDC, _amount);
    //     utilization = COMP_USDC.getUtilization();
    //     console.log("supply rate after", COMP_USDC.getSupplyRate(utilization));
    //     console.log("utilization after", utilization);
    // }

    // function test_rateAaveV2() public {
    //     super.setUp();
    //     uint apr = 10000000000000000000000000;
    //     USDCStrategy strat = USDCStrategy(address(strategy));
    //     uint _amount = strat._aprToAmount(
    //         USDCStrategy.StrategyType.AAVE_V2,
    //         apr
    //     );
    //     console.log("amount needed:", _amount);
    //     airdrop(ERC20(USDC), user, _amount);
    //     vm.startPrank(user);
    //     ERC20(USDC).approve(address(aaveV2), type(uint).max);
    //     console.log(
    //         "LR before",
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate),
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate) / 1e23
    //     );
    //     aaveV2.deposit(USDC, _amount, user, 0);
    //     console.log(
    //         "LR after",
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate),
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate) / 1e23
    //     );
    //     vm.stopPrank();
    // }

    // function _aaveV2Test(uint apr) internal {
    //     console.log("-_-_-_-_-_-_-_-", apr);
    //     super.setUp();
    //     vm.startPrank(user);
    //     USDCStrategy strat = USDCStrategy(address(strategy));
    //     uint _amount = strat._aprToAmount(
    //         USDCStrategy.StrategyType.AAVE_V2,
    //         apr
    //     );
    //     console.log("apr:", apr);
    //     console.log("amount needed:", _amount, _amount / 1e6);
    //     airdrop(ERC20(USDC), user, _amount);
    //     ERC20(USDC).approve(address(aaveV2), type(uint).max);
    //     console.log(
    //         "LR before",
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate) / 1e23
    //     );
    //     aaveV2.deposit(USDC, _amount, user, 0);
    //     console.log(
    //         "LR after",
    //         uint(aaveV2.getReserveData(USDC).currentLiquidityRate) / 1e23
    //     );
    //     aaveV2.withdraw(USDC, _amount, user);
    // }

    // function test_rateAaveV2_1() public {
    //     _aaveV2Test(1 * 1e25);
    // }

    // function test_rateAaveV2_2() public {
    //     _aaveV2Test(2 * 1e25);
    // }

    // function test_rateAaveV2_3() public {
    //     _aaveV2Test(3 * 1e25);
    // }

    // function test_rateAaveV2_4() public {
    //     _aaveV2Test(4 * 1e25);
    // }

    // function test_rateAaveV2_5() public {
    //     _aaveV2Test(5 * 1e25);
    // }

    // function test_rateAaveV2_6() public {
    //     _aaveV2Test(6 * 1e25);
    // }

    // function test_rateAaveV2_7() public {
    //     _aaveV2Test(7 * 1e25);
    // }

    // function test_rateAaveV2_8() public {
    //     _aaveV2Test(8 * 1e25);
    // }

    function test_deposit_withdraw_20M() public {
        super.setUp();
        USDCStrategy strat = USDCStrategy(address(strategy));
        uint _amount = 10_000_000 * 1e6;

        strat.printAprs();

        mintAndDepositIntoStrategy(strategy, user, _amount);

        strat.printAprs();

        skip(1);
        console.log("--------------");

        // Withdraw all funds
        uint _pre = gasleft();
        vm.prank(user);
        strategy.redeem((_amount * 9) / 10, user, user);
        uint _post = gasleft();
        console.log("withdraw gas consumed", _pre - _post);
        console.log(
            "withdrawn amount",
            ERC20(USDC).balanceOf(address(user)) / 1e6
        );
    }

    // experiment with change in interest as funds are added and removed
    // withdraw but not enough in pool
}
