// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {LendingAllocatorStrategy, ERC20} from "../../LendingAllocatorStrategy.sol";

import {IStrategyImplementation} from "../../interfaces/IStrategyImplementation.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract LendingSetup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = vm.addr(10);
    address public keeper = vm.addr(4);
    address public management = vm.addr(1);
    address public performanceFeeRecipient = vm.addr(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount; // 1e7 * 1e6; // 10M
    uint256 public minFuzzAmount; // 10_000; // 0.01

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function _setUp(
        address _asset,
        uint8[] memory _prioritiy,
        IStrategyImplementation[] memory _impls,
        uint _minimum
    ) public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(_asset);

        // Set decimals
        decimals = asset.decimals();

        maxFuzzAmount = 1e8 * 10 ** decimals; // 1e7 * 1e6; // 10M
        minFuzzAmount = 10 ** decimals / 100; // 10_000; // 0.01

        // Deploy strategy and set variables
        strategy = IStrategyInterface(
            setUpStrategy(_asset, _prioritiy, _impls, _minimum * 10 ** decimals)
        );

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy(
        address _asset,
        uint8[] memory _prioritiy,
        IStrategyImplementation[] memory _impls,
        uint _minimum
    ) public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(new LendingAllocatorStrategy(_asset, _impls))
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public returns (uint shares) {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        uint _pre = gasleft();
        vm.prank(_user);
        shares = _strategy.deposit(_amount, _user);
        uint _post = gasleft();
        console.log("deposit gas consumed:", _pre - _post);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public returns (uint) {
        airdrop(asset, _user, _amount);
        return depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertApproxEqAbs(
            _strategy.totalAssets(),
            _totalAssets,
            2,
            "!totalAssets"
        );
        assertApproxEqAbs(_strategy.totalDebt(), _totalDebt, 2, "!totalDebt");
        assertApproxEqAbs(_strategy.totalIdle(), _totalIdle, 2, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        // tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        // tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        // tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        tokenAddrs["DAI"] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        tokenAddrs["USDC"] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }
}
