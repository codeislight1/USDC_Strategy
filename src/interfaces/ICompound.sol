// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ICompound {
    function supply(address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;

    function getSupplyRate(uint utilization) external view returns (uint64);

    function getUtilization() external view returns (uint);

    function isSupplyPaused() external view returns (bool);
}
