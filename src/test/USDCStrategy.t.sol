// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {OptimizerSetup, ERC20, IStrategyInterface} from "./utils/OptimizerSetup.sol";
import {USDCStrategy} from "../USDCStrategy.sol";

contract USDCStrategyTest is OptimizerSetup {
    address[] tokens = [
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
        0xF25212E676D1F7F89Cd72fFEe66158f541246445,
        0x1a13F4Ca1d028320A707D99520AbFefca3998b7F,
        0x625E7708f30cA75bfd92586e17077590C60eb4cD
    ];

    function setUp() public virtual override {
        vm.createSelectFork("polygon");
    }

    function test_setupStrategyOK() public {
        super.setUp();
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
    }

    modifier setAllYieldSources() {
        for (uint i = 1; i < 4; i++) {
            super.setUp();
            vm.prank(management);
            USDCStrategy(address(strategy)).setHighestYield(
                USDCStrategy.StrategyType(i)
            );
            _;
        }
    }

    function test_operation(uint256 _amount) public setAllYieldSources {
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public setAllYieldSources {
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public setAllYieldSources {
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public setAllYieldSources {
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
        super.setUp();
        vm.prank(management);
        USDCStrategy(address(strategy)).setHighestYield(
            USDCStrategy.StrategyType(0)
        );

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_highestYieldStateTransition(uint256 _amount) public {
        super.setUp();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // deposit
        for (uint i = 0; i < 4; i++) {
            vm.prank(management);
            USDCStrategy(address(strategy)).setHighestYield(
                USDCStrategy.StrategyType(i)
            );
            vm.prank(keeper);
            strategy.tend();
            // Deposit into strategy
            mintAndDepositIntoStrategy(strategy, user, _amount);
            // Withdraw 50%
            vm.prank(user);
            strategy.redeem((_amount * 5) / 10, user, user);
            for (uint j = 0; j < 4; j++) {
                if (i == j) continue;
                vm.prank(management);
                USDCStrategy(address(strategy)).setHighestYield(
                    USDCStrategy.StrategyType(j)
                );
                vm.prank(keeper);
                strategy.tend();
                // Deposit into strategy
                mintAndDepositIntoStrategy(strategy, user, _amount);
                // withdraw all
                vm.prank(user);
                strategy.redeem(_amount, user, user);
                // transition back
                vm.prank(management);
                USDCStrategy(address(strategy)).setHighestYield(
                    USDCStrategy.StrategyType(i)
                );
                vm.prank(keeper);
                strategy.tend();
            }
        }
    }

    function test_freeAndDeployToMarket(uint256 _amount) public {
        super.setUp();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        USDCStrategy strat = USDCStrategy(address(strategy));
        USDCStrategy.StrategyType _highest = strat.highest();
        vm.prank(management);
        strat.freeFromMarket(_highest);
        _highest = USDCStrategy.StrategyType(
            uint(_highest) == 3 ? 1 : uint(_highest) + 1
        );
        vm.prank(management);
        strat.deployToMarket(_highest);
    }

    function test_recoverERC20(uint256 _amount) public {
        super.setUp();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        ERC20Mock mock = new ERC20Mock(
            "mock",
            "mock",
            address(strategy),
            _amount
        );
        USDCStrategy strat = USDCStrategy(address(strategy));

        vm.prank(management);
        strat.recoverERC20(address(mock), management);
        assertEq(mock.balanceOf(management), _amount);
        vm.startPrank(management);
        for (uint i; i < tokens.length; i++) {
            vm.expectRevert();
            strat.recoverERC20(tokens[i], management);
        }
        vm.stopPrank();
    }
}
