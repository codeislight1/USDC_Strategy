// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IAaveV2InterestStrategy {
    function variableRateSlope1() external view returns (uint256);

    function variableRateSlope2() external view returns (uint256);

    function baseVariableBorrowRate() external view returns (uint256);

    function OPTIMAL_UTILIZATION_RATE() external view returns (uint256);

    function EXCESS_UTILIZATION_RATE() external view returns (uint256);
}
