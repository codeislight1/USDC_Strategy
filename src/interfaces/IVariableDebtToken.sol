// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IVariableDebtToken {
    function scaledTotalSupply() external view returns (uint256);
}
