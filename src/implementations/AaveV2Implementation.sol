// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "../libraries/Constants.sol";
import "../interfaces/IStrategyImplementation.sol";
import "../interfaces/IAaveV2InterestStrategy.sol";
import "forge-std/interfaces/IERC20.sol";
import "forge-std/console.sol";
import "../interfaces/IAaveV2.sol";
import "../interfaces/IStableDebtToken.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../libraries/MathUtils.sol";
import "../libraries/AaveUtils.sol";

contract AaveV2Implementation is IStrategyImplementation {
    using MathUtils for uint;
    using AaveUtils for AaveVars;

    address Token;
    address AToken;
    address strategy;
    IAaveV2 aaveV2;

    function initialize(address lendingPool, address token) external {
        require(lendingPool != address(0));
        require(token != address(0));
        require(Token == address(0));
        aaveV2 = IAaveV2(lendingPool);
        Token = token;
        IAaveV2.ReserveData memory data = IAaveV2(lendingPool).getReserveData(
            token
        );
        AToken = data.aTokenAddress;
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
        apr_ = aaveV2.getReserveData(Token).currentLiquidityRate;
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
    function isActive() public view override returns (bool active_) {
        uint _data = aaveV2.getReserveData(Token).configuration.data;
        active_ = (((_data >> 56) & 1) == 1) && !(((_data >> 57) & 1) == 1);
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
        return address(aaveV2);
    }

    /// @inheritdoc IStrategyImplementation
    function getStrategyReceiptBalance() external view override returns (uint) {
        return IERC20(AToken).balanceOf(strategy);
    }

    /// @inheritdoc IStrategyImplementation
    function updateVirtualReserve(
        // bytes memory _reserve,
        YieldVars memory _y,
        uint _amount,
        bool _isDeposit,
        bool _isUpdateAPR
    ) external pure override returns (bytes memory r_, uint apr_) {
        AaveVars memory _vars = abi.decode(_y.r, (AaveVars));
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
        IAaveV2.ReserveData memory _data = aaveV2.getReserveData(Token);
        IAaveV2InterestStrategy _interestStart = IAaveV2InterestStrategy(
            _data.interestRateStrategyAddress
        );

        uint _reserveFactor = ((_data.configuration.data >> 64) & 65535);
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
        vars.base = int(_interestStart.baseVariableBorrowRate());
        vars.vrs1 = int(_interestStart.variableRateSlope1());
        vars.vrs2 = int(_interestStart.variableRateSlope2());
        vars.opt = int(_interestStart.OPTIMAL_UTILIZATION_RATE());
        vars.exc = int(_interestStart.EXCESS_UTILIZATION_RATE());

        // load YieldVar
        y_.r = abi.encode(vars);
        y_.id = _id;
        y_.limit = _isDeposit
            ? type(uint248).max
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
        return isActive() ? type(uint248).max : 0; // uint.max / number of markets
    }

    /// @inheritdoc IStrategyImplementation
    function getWithdrawLimit() external view override returns (uint) {
        uint aTokenBal = IERC20(AToken).balanceOf(strategy);
        uint tokenBal = IERC20(Token).balanceOf(AToken);
        return (isActive() ? aTokenBal.min(tokenBal) : 0);
    }

    /// @inheritdoc IStrategyImplementation
    function encodeDepositCalldata(
        uint amount
    ) external view override returns (bytes memory) {
        return abi.encodeCall(IAaveV2.deposit, (Token, amount, strategy, 0));
    }

    /// @inheritdoc IStrategyImplementation
    function encodeWithdrawCalldata(
        uint amount
    ) external view override returns (bytes memory) {
        return abi.encodeCall(IAaveV2.withdraw, (Token, amount, strategy));
    }
}
