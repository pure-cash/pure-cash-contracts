// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IPSM.sol";
import "./IConfigurable.sol";
import "./IMarketErrors.sol";
import "./IPUSDManager.sol";
import "./IMarketPosition.sol";
import "./IMarketLiquidity.sol";
import "../../oracle/interfaces/IPriceFeed.sol";
import "../../plugins/interfaces/IPluginManager.sol";
import "../../oracle/interfaces/IPriceFeed.sol";

interface IMarketManager is
    IMarketErrors,
    IMarketPosition,
    IMarketLiquidity,
    IPUSDManager,
    IConfigurable,
    IPluginManager,
    IPriceFeed,
    IPSM
{
    struct LiquidityBufferModule {
        /// @notice The debt of the liquidity buffer module
        uint128 pusdDebt;
        /// @notice The token payback of the liquidity buffer module
        uint128 tokenPayback;
    }

    struct PackedState {
        /// @notice The spread factor used to calculate spread
        int256 spreadFactorX96;
        /// @notice Last trading timestamp in seconds since Unix epoch
        uint64 lastTradingTimestamp;
        /// @notice The sum of long position sizes
        uint128 longSize;
        /// @notice The entry price of the net position
        uint64 lpEntryPrice;
        /// @notice The total liquidity of all LPs
        uint128 lpLiquidity;
        /// @notice The size of the net position held by all LPs
        uint128 lpNetSize;
        /// @notice The accumulated scaled USD PnL. For saving gas, this value is scaled up
        /// by 10^(market decimals + price decimals - usd decimals)
        int184 accumulateScaledUSDPnL;
        /// @notice The previous settled price
        uint64 previousSettledPrice;
    }

    struct State {
        /// @notice The packed state of the market
        PackedState packedState;
        /// @notice The value is used to track the global PUSD position
        GlobalPUSDPosition globalPUSDPosition;
        /// @notice Mapping of account to long position
        mapping(address account => Position) longPositions;
        /// @notice The value is used to track the liquidity buffer module status
        LiquidityBufferModule liquidityBufferModule;
        /// @notice The value is used to track the remaining protocol fee of the market
        uint128 protocolFee;
        /// @notice The value is used to track the token balance of the market
        uint128 tokenBalance;
        /// @notice The margin of the global stability fund
        uint256 globalStabilityFund;
    }

    /// @notice Emitted when the protocol fee is increased by trading fee
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The increased protocol fee
    event ProtocolFeeIncreased(IERC20 indexed market, uint96 amount);

    /// @notice Emitted when the protocol fee is increased by LP trading fee
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The increased protocol fee
    event ProtocolFeeIncreasedByLPTradingFee(IERC20 indexed market, uint96 amount);

    /// @notice Emitted when the protocol fee is collected
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param amount The collected protocol fee
    event ProtocolFeeCollected(IERC20 indexed market, uint128 amount);

    /// @notice Emitted when the stability fund is used by `Gov`
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param receiver The address that receives the stability fund
    /// @param stabilityFundDelta The amount of stability fund used
    event GlobalStabilityFundGovUsed(IERC20 indexed market, address indexed receiver, uint128 stabilityFundDelta);

    /// @notice Emitted when the liquidity of the stability fund is increased by liquidation
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param liquidationFee The amount of the liquidation fee that is added to the stability fund.
    event GlobalStabilityFundIncreasedByLiquidation(IERC20 indexed market, uint96 liquidationFee);

    /// @notice Emitted when the liquidity of the stability fund is increased by spread
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param spread The spread incurred by the position
    event GlobalStabilityFundIncreasedBySpread(IERC20 indexed market, uint96 spread);

    /// @notice Emitted when the liquidity buffer module debt is increased
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address for debt repayment
    /// @param pusdDebtDelta The increase in the debt of the LBM module
    /// @param tokenPaybackDelta The increase in the token payback of the LBM module
    event LiquidityBufferModuleDebtIncreased(
        IERC20 market,
        address account,
        uint128 pusdDebtDelta,
        uint128 tokenPaybackDelta
    );

    /// @notice Emitted when the liquidity buffer module debt is repaid
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address for debt repayment
    /// @param pusdDebtDelta The decrease in the debt of the LBM module
    /// @param tokenPaybackDelta The decrease in the token payback of the LBM module
    event LiquidityBufferModuleDebtRepaid(
        IERC20 market,
        address account,
        uint128 pusdDebtDelta,
        uint128 tokenPaybackDelta
    );

    /// @notice Emitted when the spread factor is changed
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param spreadFactorAfterX96 The spread factor after the trade, as a Q160.96
    event SpreadFactorChanged(IERC20 market, int256 spreadFactorAfterX96);

    /// @notice Get the packed state of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    function packedStates(IERC20 market) external view returns (PackedState memory);

    /// @notice Get the remaining protocol fee of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    function protocolFees(IERC20 market) external view returns (uint128);

    /// @notice Get the token balance of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    function tokenBalances(IERC20 market) external view returns (uint128);

    /// @notice Collect the protocol fee of the given market
    /// @dev This function can be called without authorization
    /// @param market The target market contract address, such as the contract address of WETH
    function collectProtocolFee(IERC20 market) external;

    /// @notice Get the information of global stability fund
    /// @param market The target market contract address, such as the contract address of WETH
    function globalStabilityFunds(IERC20 market) external view returns (uint256);

    /// @notice `Gov` uses the stability fund
    /// @dev The call will fail if the caller is not the `Gov` or the stability fund is insufficient
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param receiver The address to receive the stability fund
    /// @param stabilityFundDelta The amount of stability fund to be used
    function govUseStabilityFund(IERC20 market, address receiver, uint128 stabilityFundDelta) external;

    /// @notice Repay the liquidity buffer debt of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    /// @param account The address for debt repayment
    /// @param receiver The address to receive the payback token
    /// @return receiveAmount The amount of payback token received
    function repayLiquidityBufferDebt(
        IERC20 market,
        address account,
        address receiver
    ) external returns (uint128 receiveAmount);

    /// @notice Get the liquidity buffer module of the given market
    /// @param market The target market contract address, such as the contract address of WETH
    /// @return liquidityBufferModule The liquidity buffer module data
    function liquidityBufferModules(
        IERC20 market
    ) external view returns (LiquidityBufferModule memory liquidityBufferModule);
}
