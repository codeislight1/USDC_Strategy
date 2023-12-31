// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;
import "../libraries/Constants.sol";

/**
 * @title Multi yield strategy implementation
 * @author @codeislight
 * @notice Strategy implementation used by the main allocator contract to retrieve
 * crucial information about a yield source.
 */
interface IStrategyImplementation {
    /** @notice one-time set function to set main contract strategy address
     * @param _strategy strategy address
     */
    function setStrategy(address _strategy) external;

    /** @notice retrieves the resulting apr off depositing/withdrawing `_amount`
     *
     * @param _reserve encoded reserve market info, previously loaded off loadMarket
     * @param _amount input to derive apr
     * @param _isDeposit is action taken a deposit or not
     *
     *  @return apr_ derived apr after _amount
     */
    function getApr(
        bytes memory _reserve,
        uint _amount,
        bool _isDeposit
    ) external view returns (uint apr_);

    /** @notice retrieves the current active offered apr
     *  @return apr current offered yield
     */
    function getCurrentApr() external view returns (uint apr);

    /** @notice retrieves the resulting amount needed when depositing/withdrawing to reach `_amount`
     *
     *  @param _reserve encoded reserve market info, previously loaded off loadMarket
     *  @param _apr input to derive amount
     *  @param _isDeposit is action taken a deposit or not
     *
     *  @return amount_ derived amount to reach the apr
     */
    function getAmount(
        bytes memory _reserve,
        uint _apr,
        bool _isDeposit
    ) external view returns (uint amount_);

    /** @notice is market currently active
     *  @return is market active to deposit and withdraw
     */
    function isActive() external view returns (bool);

    /** @notice gets the receipt token address
     *  @return the address of the issued token
     */
    function getReceipTokenAddress() external view returns (address);

    /** @notice gets the receipt token balance of strategy address
     *  @return the strategy receipt token balance
     */
    function getStrategyReceiptBalance() external view returns (uint);

    /** @notice simulate a deposit or withdraw on the _y encoded reserve data
     *
     *  @param _y yield variable
     *  @param _amount amount to be simulated on a deposit or withdrawal
     *  @param _isDeposit is it a deposit simulation
     *  @param _isUpdateAPR should it update _y apr or not
     *
     *  return r_ new _y encoded reserve data
     *  return apr_ new apr
     */
    function updateVirtualReserve(
        // bytes memory _reserve,
        YieldVars memory _y,
        uint _amount,
        bool _isDeposit,
        bool _isUpdateAPR
    ) external view returns (bytes memory r_, uint apr_);

    /** @notice loads up the market yield info
     *
     * @param _id market id assigned by main contract
     * @param isDeposit is it for a deposit or withdrawal
     *
     * @return y_ market yield info
     */
    function loadMarket(
        uint8 _id,
        bool isDeposit
    ) external view returns (YieldVars memory y_);

    /** @notice retrieves market deposit limit
     *
     *  @dev in the case of unlimited deposit, return type(uint248).max,
     *  otherwise return the limit at which the market is capped at.
     *
     * @return _limit market deposit limit
     */
    function getDepositLimit() external view returns (uint _limit);

    /** @notice retrieves market withdrawal limit
     *
     *  @dev make sure to account for conditions at which the market might not be
     *  able to process full withdrawal.
     *
     *  e.g. users lend assets to lending markets such as Aave, borrowers
     *  borrow those assets, in this case there is no guarantee of full withdrawal at all times,
     *  thus in this case the withdrawal limit would be the minimum value between user's AToken balance and the tokens in the
     *  AToken pool contract.
     *
     * @return _limit market deposit limit
     */
    function getWithdrawLimit() external view returns (uint);

    /** @notice market address called when depositing and withdrawing
     *  @return _market address
     */
    function getMarketAddress() external view returns (address _market);

    /** @notice asset address used by the strategy
     *  @return _asset address
     */
    function getAssetAddress() external view returns (address _asset);

    /** @notice encoded depositing calldata used by the main contract to deposit
     *
     *  @param _amount to be deposited
     *
     *  @return data_ encoded deposit calldata
     */
    function encodeDepositCalldata(
        uint _amount
    ) external view returns (bytes memory data_);

    /** @notice encoded withdrawal calldata used by the main contract to withdraw
     *
     *  @param _amount to be withdrawn
     *
     *  @return data_ encoded withdraw calldata
     */
    function encodeWithdrawCalldata(
        uint _amount
    ) external view returns (bytes memory data_);
}
