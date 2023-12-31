// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "./Constants.sol";
import "forge-std/console.sol";
import "./MathUtils.sol";
import "../interfaces/IAaveV3.sol";

library AaveV3Utils {
    function getReserveFactor(
        IAaveV3.ReserveData memory r
    ) internal view returns (uint) {
        return (r.configuration.data >> 64) & 65535;
    }

    function getSupplyCap(
        IAaveV3.ReserveData memory r
    ) internal view returns (uint) {
        return (r.configuration.data >> 116) & 68719476735;
    }

    function isFunctional(
        IAaveV3.ReserveData memory r
    ) internal view returns (bool) {
        uint _data = r.configuration.data;
        return
            (((_data >> 56) & 1) == 1) && // active
            !(((_data >> 57) & 1) == 1) && // frozen
            !(((_data >> 60) & 1) == 1); // paused
    }
}
