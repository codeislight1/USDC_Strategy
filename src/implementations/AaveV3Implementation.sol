// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "../libraries/Constants.sol";
import "../interfaces/IStrategyImplementation.sol";
import "../interfaces/IAaveV3InterestStrategy.sol";
import "forge-std/interfaces/IERC20.sol";
import "forge-std/console.sol";
import "../interfaces/IAaveV3.sol";
import "../interfaces/IStableDebtToken.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../libraries/MathUtils.sol";
import "../libraries/AaveUtils.sol";
import "../libraries/AaveV3Utils.sol";

contract AaveV3Implementation is IStrategyImplementation {
    using MathUtils for uint;
    using AaveUtils for uint;
    using AaveUtils for AaveVars;
    using AaveV3Utils for IAaveV3.ReserveData;

    address Token;
    address AToken;
    IAaveV3 aaveV3;
    uint8 decimals;
    address strategy;

    function initialize(address pool, address token) external {
        aaveV3 = IAaveV3(pool);
        Token = token;
        IAaveV3.ReserveData memory data = IAaveV3(pool).getReserveData(token);
        AToken = data.aTokenAddress;
        decimals = IERC20(token).decimals();
    }

    /// @inheritdoc IStrategyImplementation
    function setStrategy(address _strategy) external {
        require(_strategy != address(0));
        require(strategy == address(0));
        strategy = _strategy;
    }

    /// @inheritdoc IStrategyImplementation
    function getApr(
        bytes memory _reserve,
        uint _amount,
        bool _isDeposit
    ) external pure override returns (uint apr_) {
        AaveVars memory v = abi.decode(_reserve, (AaveVars));
        // TODO safecast
        apr_ = uint(v.getApr(int(_amount), _isDeposit));
    }

    /// @inheritdoc IStrategyImplementation
    function getCurrentApr() public view override returns (uint apr_) {
        apr_ = aaveV3.getReserveData(Token).currentLiquidityRate;
    }

    /// @inheritdoc IStrategyImplementation
    function getAmount(
        bytes memory _reserve,
        uint _apr,
        bool _isDeposit
    ) external view override returns (uint amount_) {
        AaveVars memory v = abi.decode(_reserve, (AaveVars));
        amount_ = v.aprToAmount(int(_apr), _isDeposit);
    }

    /// @inheritdoc IStrategyImplementation
    function isActive() public view override returns (bool) {
        return _isActive(aaveV3.getReserveData(Token));
    }

    /// @inheritdoc IStrategyImplementation
    function getReceipTokenAddress() external view override returns (address) {
        return AToken;
    }

    /// @inheritdoc IStrategyImplementation
    function getAssetAddress() external view returns (address) {
        return Token;
    }

    /// @inheritdoc IStrategyImplementation
    function getMarketAddress() external view override returns (address) {
        return address(aaveV3);
    }

    /// @inheritdoc IStrategyImplementation
    function getStrategyReceiptBalance() external view override returns (uint) {
        return IERC20(AToken).balanceOf(strategy);
    }

    /// @inheritdoc IStrategyImplementation
    function updateVirtualReserve(
        YieldVars memory _y,
        uint _amount,
        bool _isDeposit,
        bool _isUpdateAPR
    ) external pure override returns (bytes memory r_, uint apr_) {
        AaveVars memory _vars = abi.decode(_y.r, (AaveVars));
        apr_ = _y.apr;
        if (_isUpdateAPR) {
            apr_ = uint(_vars.getApr(int256(_amount), _isDeposit));
        }
        if (_isDeposit) _vars.aL += int256(_amount);
        else _vars.aL -= int256(_amount);

        r_ = abi.encode(_vars);
    }

    /// @inheritdoc IStrategyImplementation
    function loadMarket(
        uint8 _id,
        bool _isDeposit
    ) external view override returns (YieldVars memory y_) {
        // getting AaveVars vars
        AaveVars memory vars;
        IAaveV3.ReserveData memory _data = aaveV3.getReserveData(Token);
        IAaveV3InterestStrategy _interestStart = IAaveV3InterestStrategy(
            _data.interestRateStrategyAddress
        );
        uint _reserveFactor = _data.getReserveFactor();
        (uint _tsd, uint _avgSBR) = IStableDebtToken(
            _data.stableDebtTokenAddress
        ).getTotalSupplyAndAvgRate();
        (vars.tSD, vars.avgSBR) = (int(_tsd), int(_avgSBR));
        vars.tVD = int(
            IVariableDebtToken(_data.variableDebtTokenAddress)
                .scaledTotalSupply()
                .rayMul(uint(_data.variableBorrowIndex))
        );
        vars.tD = vars.tVD + vars.tSD;
        vars.aL = int(IERC20(Token).balanceOf(_data.aTokenAddress));
        vars.subFactor = PERCENT_FACTOR - int(_reserveFactor);
        vars.base = int(_interestStart.getBaseVariableBorrowRate());
        vars.vrs1 = int(_interestStart.getVariableRateSlope1());
        vars.vrs2 = int(_interestStart.getVariableRateSlope2());
        vars.opt = int(_interestStart.OPTIMAL_USAGE_RATIO());
        vars.exc = int(_interestStart.MAX_EXCESS_USAGE_RATIO());

        // load YieldVar
        y_.r = abi.encode(vars);
        y_.id = _id;
        uint supplyCap = _getV3SupplyCap(_data);
        uint tS = _getTotalSupply(_data);
        y_.limit = _isDeposit
            ? (
                supplyCap == 0
                    ? type(uint248).max
                    : (tS < supplyCap ? supplyCap - tS : 0)
            )
            : (
                IERC20(Token).balanceOf(AToken).min(
                    IERC20(AToken).balanceOf(strategy)
                )
            );

        y_.apr = _isDeposit || y_.limit != 0 ? getCurrentApr() : 0;
        y_.cacheApr = y_.apr;
    }

    /// @inheritdoc IStrategyImplementation
    function getDepositLimit() external view override returns (uint) {
        IAaveV3.ReserveData memory r = aaveV3.getReserveData(Token);
        uint v3_tS = _getTotalSupply(r);
        uint v3_cap = _getV3SupplyCap(r);
        uint v3Limit = v3_cap == 0
            ? type(uint248).max
            : (v3_cap > v3_tS ? v3_cap - v3_tS : 0);
        return _isActive(r) ? v3Limit : 0; // uint.max / number of markets
    }

    /// @inheritdoc IStrategyImplementation
    function getWithdrawLimit() external view override returns (uint) {
        uint aTokenBal = IERC20(AToken).balanceOf(strategy);
        uint tokenBal = IERC20(Token).balanceOf(AToken);
        return (isActive() ? (aTokenBal < tokenBal ? aTokenBal : tokenBal) : 0);
    }

    /// @inheritdoc IStrategyImplementation
    function encodeDepositCalldata(
        uint amount
    ) external view override returns (bytes memory) {
        return abi.encodeCall(IAaveV3.supply, (Token, amount, strategy, 0));
    }

    /// @inheritdoc IStrategyImplementation
    function encodeWithdrawCalldata(
        uint amount
    ) external view override returns (bytes memory) {
        return abi.encodeCall(IAaveV3.withdraw, (Token, amount, strategy));
    }

    function _isActive(
        IAaveV3.ReserveData memory r
    ) internal view returns (bool) {
        return r.isFunctional();
    }

    function _getV3SupplyCap(
        IAaveV3.ReserveData memory _data
    ) internal view returns (uint) {
        uint AMT = 0;
        return (_data.getSupplyCap() - AMT) * 10 ** decimals;
    }

    function _getTotalSupply(
        IAaveV3.ReserveData memory _data
    ) internal view returns (uint) {
        (
            uint accruedToTreasury,
            uint nextLiquidityIndex
        ) = _getCurrentAccruedTreasuryAndNextLiquidityIndex(_data);
        return
            uint(
                IVariableDebtToken(AToken).scaledTotalSupply() +
                    accruedToTreasury
            ).rayMul(nextLiquidityIndex);
    }

    struct AccrueToTreasuryLocalVars {
        uint256 nextLiquidityIndex;
        uint256 prevTotalStableDebt;
        uint256 prevTotalVariableDebt;
        uint256 currTotalVariableDebt;
        uint256 cumulatedStableInterest;
        uint256 totalDebtAccrued;
        uint256 currVariableBorrowIndex;
        uint256 nextVariableBorrowIndex;
        uint256 currScaledVariableDebt;
        uint256 nextScaledVariableDebt;
        uint256 currPrincipalStableDebt;
        uint256 currTotalStableDebt;
        uint256 currAvgStableBorrowRate;
        uint40 stableDebtLastUpdateTimestamp;
    }

    function _getCurrentAccruedTreasuryAndNextLiquidityIndex(
        IAaveV3.ReserveData memory _data
    ) internal view returns (uint, uint) {
        AccrueToTreasuryLocalVars memory vars;
        uint _reserveFactor = _data.getReserveFactor();

        vars.nextLiquidityIndex = _data.liquidityIndex;

        // update nextLiquidityIndex
        vars.nextLiquidityIndex = (
            uint(_data.currentLiquidityRate).calculateLinearInterest(
                _data.lastUpdateTimestamp
            )
        ).rayMul(_data.liquidityIndex);

        if (_reserveFactor == 0) {
            return (_data.accruedToTreasury, vars.nextLiquidityIndex);
        }

        vars.currScaledVariableDebt = vars
            .nextScaledVariableDebt = IVariableDebtToken(
            _data.variableDebtTokenAddress
        ).scaledTotalSupply();

        vars.currVariableBorrowIndex = vars.nextVariableBorrowIndex = _data
            .variableBorrowIndex;

        if (vars.currScaledVariableDebt != 0) {
            uint256 cumulatedVariableBorrowInterest = MathUtils
                .calculateCompoundedInterest(
                    _data.currentVariableBorrowRate,
                    _data.lastUpdateTimestamp
                );
            vars.nextVariableBorrowIndex = cumulatedVariableBorrowInterest
                .rayMul(vars.currVariableBorrowIndex);
        }

        //calculate the total variable debt at moment of the last interaction
        vars.prevTotalVariableDebt = vars.currScaledVariableDebt.rayMul(
            vars.currVariableBorrowIndex
        );

        //calculate the new total variable debt after accumulation of the interest on the index
        vars.currTotalVariableDebt = vars.currScaledVariableDebt.rayMul(
            vars.nextVariableBorrowIndex
        );

        (
            vars.currPrincipalStableDebt,
            vars.currTotalStableDebt,
            vars.currAvgStableBorrowRate,
            vars.stableDebtLastUpdateTimestamp
        ) = IStableDebtToken(_data.stableDebtTokenAddress).getSupplyData();

        //calculate the stable debt until the last timestamp update
        vars.cumulatedStableInterest = vars
            .currAvgStableBorrowRate
            .calculateCompoundedInterest(
                vars.stableDebtLastUpdateTimestamp,
                _data.lastUpdateTimestamp
            );

        vars.prevTotalStableDebt = vars.currPrincipalStableDebt.rayMul(
            vars.cumulatedStableInterest
        );

        vars.totalDebtAccrued =
            vars.currTotalVariableDebt +
            vars.currTotalStableDebt -
            vars.prevTotalVariableDebt -
            vars.prevTotalStableDebt;

        uint toMint = vars.totalDebtAccrued.percentMul(_reserveFactor);
        toMint = toMint.rayDiv(vars.nextLiquidityIndex);

        return (_data.accruedToTreasury + toMint, vars.nextLiquidityIndex);
    }
}
