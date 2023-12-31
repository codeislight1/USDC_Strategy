// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./StrategyImplementation.sol";

contract AaveV2ImplementationTest is StrategyImplementationTest {
    IAaveV2 constant aaveV2 =
        IAaveV2(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);

    function init()
        internal
        override
        returns (IStrategyImplementation impl_, ERC20 token_)
    {
        token_ = ERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        impl_ = IStrategyImplementation(new AaveV2Implementation());
        AaveV2Implementation(address(impl_)).initialize(
            address(aaveV2),
            address(token_)
        );
        impl_.setStrategy(address(this)); // caller will be this contract
        token = token_;
        impl = impl_;
        market = address(aaveV2);
    }
}
