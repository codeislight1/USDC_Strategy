// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "../libraries/Constants.sol";
import "../libraries/CompoundUtils.sol";
import "../libraries/MathUtils.sol";
import "../interfaces/IStrategyImplementation.sol";
import "../interfaces/ICompound.sol";
import "forge-std/interfaces/IERC20.sol";

contract CompoundImplementation is IStrategyImplementation {
    using MathUtils for uint;
    using CompoundUtils for uint;
    using CompoundUtils for CompoundVars;

    address Token;
    address CToken;
    address strategy;

    function initialize(address _token, address _cToken) external {
        Token = _token;
        CToken = _cToken;
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
    ) external pure returns (uint apr_) {
        CompoundVars memory v = abi.decode(_reserve, (CompoundVars));
        apr_ = v.amountToSupplyRate(_amount, _isDeposit).compAprWrapper(true);
    }

    /// @inheritdoc IStrategyImplementation
    function getCurrentApr() public view returns (uint apr_) {
        apr_ = uint(
            ICompound(CToken).getSupplyRate(ICompound(CToken).getUtilization())
        ).compAprWrapper(true);
    }

    /// @inheritdoc IStrategyImplementation
    function getAmount(
        bytes memory _reserve,
        uint _apr,
        bool _isDeposit
    ) external pure returns (uint amount_) {
        CompoundVars memory v = abi.decode(_reserve, (CompoundVars));
        amount_ = CompoundUtils.aprToAmount(v, _apr, _isDeposit);
    }

    /// @inheritdoc IStrategyImplementation
    function isActive() public view returns (bool) {
        return !ICompound(CToken).isSupplyPaused();
    }

    /// @inheritdoc IStrategyImplementation
    function getReceipTokenAddress() external view returns (address) {
        return CToken;
    }

    /// @inheritdoc IStrategyImplementation
    function getAssetAddress() external view returns (address) {
        return Token;
    }

    /// @inheritdoc IStrategyImplementation
    function getStrategyReceiptBalance() external view returns (uint) {
        return IERC20(CToken).balanceOf(strategy);
    }

    /// @inheritdoc IStrategyImplementation
    function updateVirtualReserve(
        // bytes memory _reserve,
        YieldVars memory _y,
        uint _amount,
        bool _isDeposit,
        bool _isUpdateAPR
    ) external pure override returns (bytes memory r_, uint apr_) {
        CompoundVars memory _vars = abi.decode(_y.r, (CompoundVars));

        if (_isDeposit) _vars.tS += int256(_amount);
        else _vars.tS -= int256(_amount);
        if (_isUpdateAPR)
            apr_ = _vars.amountToSupplyRate().compAprWrapper(true);

        r_ = abi.encode(_vars);
    }

    /// @inheritdoc IStrategyImplementation
    function loadMarket(
        uint8 _id,
        bool _isDeposit
    ) external view returns (YieldVars memory y_) {
        CompoundVars memory _vars;
        ICompound cToken = ICompound(CToken);
        //
        _vars.tS = int(cToken.totalSupply());
        _vars.tB = int(cToken.totalBorrow());
        _vars.base = int(cToken.supplyPerSecondInterestRateBase());
        _vars.rsl = int(cToken.supplyPerSecondInterestRateSlopeLow());
        _vars.rsh = int(cToken.supplyPerSecondInterestRateSlopeHigh());
        _vars.kink = int(cToken.supplyKink());

        // load YieldVar
        y_.r = abi.encode(_vars);

        y_.id = _id;
        y_.limit = _isDeposit
            ? type(uint248).max
            : (
                IERC20(Token).balanceOf(CToken).min(
                    IERC20(CToken).balanceOf(strategy)
                )
            );
        y_.apr = _isDeposit || y_.limit != 0 ? getCurrentApr() : 0;
        y_.cacheApr = y_.apr;
    }

    /// @inheritdoc IStrategyImplementation
    function getDepositLimit() external pure returns (uint) {
        return type(uint248).max; // uint.max / number of markets
    }

    /// @inheritdoc IStrategyImplementation
    function getWithdrawLimit() external view returns (uint) {
        uint aTokenBal = IERC20(CToken).balanceOf(strategy);
        uint tokenBal = IERC20(Token).balanceOf(CToken);
        return (isActive() ? aTokenBal.min(tokenBal) : 0);
    }

    /// @inheritdoc IStrategyImplementation
    function getMarketAddress() external view returns (address) {
        return CToken;
    }

    /// @inheritdoc IStrategyImplementation
    function encodeDepositCalldata(
        uint amount
    ) external view returns (bytes memory) {
        return abi.encodeCall(ICompound.supply, (Token, amount));
    }

    /// @inheritdoc IStrategyImplementation
    function encodeWithdrawCalldata(
        uint amount
    ) external view returns (bytes memory) {
        return abi.encodeCall(ICompound.withdraw, (Token, amount));
    }
}
