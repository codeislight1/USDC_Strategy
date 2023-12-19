// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IAaveV3InterestStrategy {
    function getVariableRateSlope1() external view returns (uint256);

    function getVariableRateSlope2() external view returns (uint256);

    function getBaseVariableBorrowRate() external view returns (uint256);

    function OPTIMAL_USAGE_RATIO() external view returns (uint256);

    function MAX_EXCESS_USAGE_RATIO() external view returns (uint256);
}
