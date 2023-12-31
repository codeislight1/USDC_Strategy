// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {LendingSetup, ERC20, IStrategyInterface} from "../utils/LendingSetup.sol";
import {LendingAllocatorStrategy} from "../../LendingAllocatorStrategy.sol";
import "../../interfaces/IAaveV2.sol";
import "../../interfaces/IAaveV3.sol";
import "../../interfaces/ICompound.sol";
import "../../interfaces/IAaveV2InterestStrategy.sol";
import "../../libraries/Constants.sol";
import "../../interfaces/IStrategyImplementation.sol";
import "../../interfaces/IVariableDebtToken.sol";
import "../../implementations/AaveV2Implementation.sol";
import "../../implementations/AaveV3Implementation.sol";
import "../../implementations/CompoundImplementation.sol";
import "../../AllocatorDataProvider.sol";
import "../../libraries/MathUtils.sol";

abstract contract StrategyImplementationTest is Test {
    IStrategyImplementation impl;
    ERC20 token;
    address market;

    function init()
        internal
        virtual
        returns (IStrategyImplementation, ERC20 token_);

    function setUp() public {
        init();
    }

    function test_implOK() public {
        assertEq(impl.getAssetAddress(), address(token));
        assertEq(impl.getMarketAddress(), market);
        assertTrue(impl.getCurrentApr() > 0);
        assertTrue(impl.isActive());
        assertTrue(impl.getDepositLimit() > 0);
        assertEq(impl.getWithdrawLimit(), 0);
        assertTrue(impl.encodeDepositCalldata(0).length > 4);
        assertTrue(impl.encodeWithdrawCalldata(0).length > 4);
    }

    function _loose(uint _apr) internal view returns (uint) {
        return (_apr * ACCURACY) / RAY;
    }

    function _deposit(uint amount) internal {
        if (token.balanceOf(address(this)) < amount)
            airdrop(token, address(this), amount);
        address market = impl.getMarketAddress();
        if (token.allowance(address(this), market) < amount)
            token.approve(address(market), type(uint).max);

        // deposit
        (bool s, ) = market.call(impl.encodeDepositCalldata(amount));
        require(s, "!depositTest");
    }

    function _withdraw(uint amount) internal {
        address market = impl.getMarketAddress();

        // withdraw
        (bool s, ) = market.call(impl.encodeWithdrawCalldata(amount));
        require(s, "!withdrawTest");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function test_getApr() public {
        uint amount = 100_000 * 10 ** token.decimals();
        // deposit to move apr by 0.25%
        uint currentApr = impl.getCurrentApr();
        uint newApr = impl.getApr(impl.loadMarket(0, true).r, amount, true);
        // airdrop amountNeeded
        _deposit(amount);
        assertEq(_loose(impl.getCurrentApr()), _loose(newApr), "!depositApr");
        // withdraw to move apr by 0.1%
        amount /= 2;
        newApr = impl.getApr(impl.loadMarket(0, false).r, amount, false);
        _withdraw(amount);
        assertEq(_loose(impl.getCurrentApr()), _loose(newApr), "!withdrawApr");
    }

    function test_getAmount(uint percent) public {
        // deposit to move apr by 0.25%
        percent = bound(percent, 0.05e27 / 100, 0.95e27 / 100);
        uint currentApr = impl.getCurrentApr();
        uint newApr = currentApr - percent;
        uint amountNeeded = impl.getAmount(
            impl.loadMarket(0, true).r,
            newApr,
            true
        );
        // airdrop amountNeeded
        _deposit(amountNeeded);
        assertApproxEqAbs(
            _loose(impl.getCurrentApr()),
            _loose(newApr),
            1,
            "!depositApr"
        );
        // withdraw to move apr by 0.1%
        newApr = currentApr - percent / 2;
        amountNeeded = impl.getAmount(
            impl.loadMarket(0, false).r,
            newApr,
            false
        );
        _withdraw(amountNeeded);
        assertEq(_loose(impl.getCurrentApr()), _loose(newApr), "!withdrawApr");
    }

    function test_strategyReceiptBalance() public {
        uint amount = 1 * 10 ** token.decimals();
        _deposit(amount);
        assertApproxEqAbs(amount, impl.getStrategyReceiptBalance(), 1);
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function test_depositAndWithdrawLimit(uint amount) public {
        uint dLimit = min(impl.getDepositLimit(), token.totalSupply());
        vm.assume(amount > 0 && amount <= dLimit);
        _deposit(amount);
        _withdraw(impl.getWithdrawLimit());
    }

    function _delta() internal view virtual returns (uint) {
        return 1;
    }

    function test_encodeDepositAndWithdraw(uint amount) public {
        uint dLimit = min(impl.getDepositLimit(), token.totalSupply());
        vm.assume(amount > 0 && amount <= dLimit);
        airdrop(token, address(this), amount);
        token.approve(address(market), type(uint).max);
        // deposit
        (bool s, ) = market.call(impl.encodeDepositCalldata(amount));
        require(s, "!depositTest");
        assertEq(token.balanceOf(address(this)), 0);
        assertApproxEqAbs(amount, impl.getStrategyReceiptBalance(), _delta());
        // withdraw
        amount = impl.getStrategyReceiptBalance();
        (s, ) = market.call(impl.encodeWithdrawCalldata(amount));
        require(s, "!withdrawTest");
        assertEq(token.balanceOf(address(this)), amount);
        assertEq(impl.getStrategyReceiptBalance(), 0);
    }
}
