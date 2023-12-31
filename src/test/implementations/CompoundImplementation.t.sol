// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./StrategyImplementation.sol";

contract CompoundImplementationTest is StrategyImplementationTest {
    function _delta() internal view override returns (uint) {
        return 2;
    }

    function init()
        internal
        override
        returns (IStrategyImplementation impl_, ERC20 token_)
    {
        address _cToken = 0xF25212E676D1F7F89Cd72fFEe66158f541246445;
        token_ = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        impl_ = IStrategyImplementation(new CompoundImplementation());
        CompoundImplementation(address(impl_)).initialize(
            address(token_),
            _cToken
        );
        impl_.setStrategy(address(this)); // caller will be this contract
        token = token_;
        impl = impl_;
        market = address(_cToken);
    }
}
