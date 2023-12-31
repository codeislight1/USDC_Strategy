// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./StrategyImplementation.sol";

contract AaveV3ImplementationTest is StrategyImplementationTest {
    IAaveV3 constant aaveV3 =
        IAaveV3(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    function init()
        internal
        override
        returns (IStrategyImplementation impl_, ERC20 token_)
    {
        token_ = ERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        impl_ = IStrategyImplementation(new AaveV3Implementation());
        AaveV3Implementation(address(impl_)).initialize(
            address(aaveV3),
            address(token_)
        );
        impl_.setStrategy(address(this)); // caller will be this contract
        token = token_;
        impl = impl_;
        market = address(aaveV3);
    }
}
