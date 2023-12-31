// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {LendingSetup, ERC20, IStrategyInterface} from "./utils/LendingSetup.sol";
import {LendingAllocatorStrategy} from "../LendingAllocatorStrategy.sol";
import "../interfaces/IAaveV2.sol";
import "../interfaces/IAaveV3.sol";
import "../interfaces/ICompound.sol";
import "../interfaces/IAaveV2InterestStrategy.sol";
import "../libraries/Constants.sol";
import "../interfaces/IStrategyImplementation.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../implementations/AaveV2Implementation.sol";
import "../implementations/AaveV3Implementation.sol";
import "../implementations/CompoundImplementation.sol";
import "../AllocatorDataProvider.sol";
import "../libraries/MathUtils.sol";

abstract contract LendingStrategyDAITest is LendingSetup {
    using MathUtils for uint;
    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    AllocatorDataProvider allocator;

    uint _minimum = 1000;

    function getTicker() internal view virtual returns (string memory);

    function setUpImpls()
        internal
        virtual
        returns (
            IStrategyImplementation[] memory impls_,
            uint8[] memory order_
        );

    function setUp() public {
        _setTokenAddrs();
        address _asset = tokenAddrs[getTicker()];
        (
            IStrategyImplementation[] memory impls,
            uint8[] memory order
        ) = setUpImpls();

        _setUp(_asset, order, impls, _minimum);
        allocator = new AllocatorDataProvider(
            LendingAllocatorStrategy(address(strategy)),
            order,
            _asset,
            _minimum * 10 ** decimals
        );
    }

    modifier SetupRedundant(uint256 _amount, uint8 _state) {
        vm.assume(
            _amount > minFuzzAmount &&
                _amount < maxFuzzAmount &&
                0 <= uint8(_state) &&
                uint8(_state) <= 2
        );
        LendingAllocatorStrategy strat = LendingAllocatorStrategy(
            address(strategy)
        );
        if (State(_state) != State.NO_ALLOCATION) {
            vm.prank(management);
            strat.setDepositState(State(_state));
        }

        // Deposit into strategy
        uint shares = mintAndDepositIntoStrategy(strategy, user, _amount);

        // deploy any IDLE
        _keep();

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, shares, shares, 0);

        // Earn Interest
        skip(1 days);
        _;
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(shares, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + shares,
            "!final balance"
        );
    }

    function test_setupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
    }

    function test_operation(
        uint256 _amount,
        uint8 _state
    ) public SetupRedundant(_amount, _state) {
        //
    }

    function _keep() internal {
        // check and call strategy with keeper
        (bool isCheck, bytes memory execPayload) = allocator.check();
        if (isCheck) {
            bool isKeepIDLE = asset.balanceOf(address(strategy)) > 0;
            uint _p = gasleft();
            vm.prank(keeper);
            (bool success, ) = address(strategy).call(execPayload);
            require(success, "!keep");
            uint p_ = gasleft();
            console.log(
                isKeepIDLE ? "keepIDLE" : "keep",
                "gas consumed:",
                _p - p_
            );
            // TODO look into other approach other than tend
            vm.prank(keeper);
            strategy.tend(); // update storage balances
        }
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor,
        uint8 _state
    ) public SetupRedundant(_amount, _state) {
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor,
        uint8 _state
    ) public {
        vm.assume(
            _amount > minFuzzAmount &&
                _amount < maxFuzzAmount &&
                0 <= uint8(_state) &&
                uint8(_state) <= 2
        );
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        setFees(0, 1000);
        LendingAllocatorStrategy strat = LendingAllocatorStrategy(
            address(strategy)
        );
        if (State(_state) != State.NO_ALLOCATION) {
            vm.prank(management);
            strat.setDepositState(State(_state));
        }
        // Deposit into strategy
        uint shares = mintAndDepositIntoStrategy(strategy, user, _amount);

        // deploy any IDLE
        _keep();

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, shares, shares, 0);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGt(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        //
        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(shares, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + shares,
            "!final balance"
        );

        // TODO look into why there is little tokens left
        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_tendTrigger(
        uint256 _amount,
        uint8 _state
    ) public SetupRedundant(_amount, _state) {
        // vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // (bool trigger, ) = strategy.tendTrigger();
        // assertTrue(!trigger);

        // // Deposit into strategy
        // uint shares = mintAndDepositIntoStrategy(strategy, user, _amount);

        // (trigger, ) = strategy.tendTrigger();
        // assertTrue(!trigger);

        // // Skip some time
        // skip(1 days);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // vm.prank(user);
        // strategy.redeem(shares, user, user);

        // (trigger, ) = strategy.tendTrigger();
        // assertTrue(!trigger);
    }

    function test_IDLE_mode(
        uint256 _amount,
        uint8 _state
    ) public SetupRedundant(_amount, _state) {
        // vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // // Deposit into strategy
        // uint shares = mintAndDepositIntoStrategy(strategy, user, _amount);

        // // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        // checkStrategyTotals(strategy, _amount, _amount, 0);

        // // Earn Interest
        // skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // uint256 balanceBefore = asset.balanceOf(user);

        // // Withdraw all funds
        // vm.prank(user);
        // strategy.redeem(shares, user, user);

        // assertGe(
        //     asset.balanceOf(user),
        //     balanceBefore + shares,
        //     "!final balance"
        // );
    }

    function test_freeAndDeployToMarket(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        LendingAllocatorStrategy strat = LendingAllocatorStrategy(
            address(strategy)
        );

        airdrop(asset, address(strategy), _amount);

        uint amt = asset.balanceOf(address(strat));

        vm.prank(management);
        uint8 _id = 0;
        // TODO safety to not be aaveV3
        strat.deployToMarket(_id);

        (IStrategyImplementation _impl, ) = strat.markets(_id);
        address receipt = IStrategyImplementation(_impl)
            .getReceipTokenAddress();

        assertApproxEqAbs(ERC20(receipt).balanceOf(address(strategy)), amt, 1);

        vm.prank(management);
        strat.freeFromMarket(_id);

        assertApproxEqAbs(ERC20(asset).balanceOf(address(strategy)), amt, 1);
    }

    function test_keep(
        uint256 _amount,
        uint8 _state
    ) public SetupRedundant(_amount, _state) {
        // someone deposit into aave v3
        address bob = vm.addr(609);
        uint amt = (1_000_000 * 10 ** decimals);
        airdrop(asset, bob, amt);

        vm.startPrank(bob);
        ERC20(asset).approve(address(aaveV2), type(uint).max);
        aaveV2.deposit(address(asset), amt, bob, 0);
        vm.stopPrank();

        _keep(); // maintain any difference
    }

    function test_gasConsumptionNoAllocation() public {
        _operation();
    }

    function test_gasConsumptionPartialAllocation() public {
        LendingAllocatorStrategy strat = LendingAllocatorStrategy(
            address(strategy)
        );

        vm.prank(management);
        strat.setDepositState(State.PARTIAL_ALLOCATION);
        _operation();
    }

    function test_gasConsumptionFullAllocation() public {
        LendingAllocatorStrategy strat = LendingAllocatorStrategy(
            address(strategy)
        );
        vm.prank(management);
        strat.setDepositState(State.FULL_ALLOCATION);
        _operation();
    }

    function _operation() internal {
        address bob = vm.addr(0x609);
        allocator.printAprs();
        // initial deposit to set initial storage slots
        uint amount = 1_000 * 10 ** decimals;
        airdrop(asset, bob, amount);
        vm.prank(bob);
        asset.approve(address(strategy), type(uint).max);
        vm.prank(bob);
        strategy.deposit(amount, bob);

        allocator.printAprs();

        // deposit
        mintAndDepositIntoStrategy(strategy, user, 100_000 * 10 ** decimals);
        allocator.printAprs();
        // Keep
        console.log("k1");
        _keep();
        // deposit a lot to trigger keep
        // shares = mintAndDepositIntoStrategy(
        //     strategy,
        //     bob,
        //     500_000 * 10 ** decimals
        // );
        allocator.printAprs();

        amount = 1_000_000 * 10 ** decimals;
        airdrop(asset, bob, amount);
        vm.startPrank(bob);
        asset.approve(address(aaveV2), type(uint).max);
        aaveV2.deposit(address(asset), amount, bob, 0);
        // asset.approve(address(aaveV3), type(uint).max);
        // aaveV3.supply(address(asset), amount, bob, 0);
        vm.stopPrank();
        allocator.printAprs();

        // Keep
        console.log("k2");
        _keep();
        allocator.printAprs();

        uint _pre = gasleft();
        // withdraw
        uint shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user);
        uint pre_ = gasleft();
        console.log("redeem gas:", _pre - pre_);
        allocator.printAprs();
    }
}

contract Lending2UTest is LendingStrategyDAITest {
    uint8[] order = [0, 1];
    string _ticker = "USDC";

    function setUpImpls()
        internal
        override
        returns (IStrategyImplementation[] memory impls, uint8[] memory order_)
    {
        address _asset = tokenAddrs[_ticker];
        impls = new IStrategyImplementation[](order.length);
        impls[0] = IStrategyImplementation(new AaveV2Implementation());
        AaveV2Implementation(address(impls[0])).initialize(
            address(aaveV2),
            _asset
        );
        impls[1] = IStrategyImplementation(new AaveV3Implementation());
        AaveV3Implementation(address(impls[1])).initialize(
            address(aaveV3),
            _asset
        );
        order_ = order;
    }

    function getTicker() internal view override returns (string memory) {
        return _ticker;
    }
}

contract Lending3UTest is LendingStrategyDAITest {
    uint8[] order = [0, 1, 2];
    string _ticker = "USDC";
    address _cToken = 0xF25212E676D1F7F89Cd72fFEe66158f541246445;

    function setUpImpls()
        internal
        override
        returns (IStrategyImplementation[] memory impls, uint8[] memory order_)
    {
        address _asset = tokenAddrs[_ticker];
        impls = new IStrategyImplementation[](order.length);
        impls[0] = IStrategyImplementation(new AaveV2Implementation());
        AaveV2Implementation(address(impls[0])).initialize(
            address(aaveV2),
            _asset
        );
        impls[1] = IStrategyImplementation(new AaveV3Implementation());
        AaveV3Implementation(address(impls[1])).initialize(
            address(aaveV3),
            _asset
        );
        impls[2] = IStrategyImplementation(new CompoundImplementation());
        CompoundImplementation(address(impls[2])).initialize(_asset, _cToken);
        order_ = order;
    }

    function getTicker() internal view override returns (string memory) {
        return _ticker;
    }
}
