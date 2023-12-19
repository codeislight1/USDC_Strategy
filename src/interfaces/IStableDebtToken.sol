// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IStableDebtToken {
    function getTotalSupplyAndAvgRate()
        external
        view
        returns (uint256, uint256);
}
