// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "../core/interfaces/IMarketManager.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20 as OneInchSafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

/// @notice Utility library for market manager
library MarketUtil {
    using SafeCast for *;

    /// @notice Transfer ETH from the contract to the receiver
    /// @param _receiver The address of the receiver
    /// @param _amount The amount of ETH to transfer
    /// @param _executionGasLimit The gas limit for the transfer
    function transferOutETH(address payable _receiver, uint256 _amount, uint256 _executionGasLimit) internal {
        if (_amount == 0) return;

        if (address(this).balance < _amount) revert IMarketErrors.InsufficientBalance(address(this).balance, _amount);

        (bool success, ) = _receiver.call{value: _amount, gas: _executionGasLimit}("");
        if (!success) revert IMarketErrors.FailedTransferETH();
    }

    /// @notice Check if the account is a deployed contract
    /// @param _account The address of the account
    /// @return true if the account is a deployed contract, false otherwise
    function isDeployedContract(address _account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        // prettier-ignore
        assembly { size := extcodesize(_account) }
        return size > 0;
    }

    /// @notice `Gov` uses the stability fund
    /// @param _state The state of the market
    /// @param _market The target market contract address, such as the contract address of WETH
    /// @param _stabilityFundDelta The amount of stability fund to be used
    /// @param _receiver The address to receive the stability fund
    function govUseStabilityFund(
        IMarketManager.State storage _state,
        IERC20 _market,
        uint128 _stabilityFundDelta,
        address _receiver
    ) public {
        _state.globalStabilityFund -= _stabilityFundDelta;
        emit IMarketManager.GlobalStabilityFundGovUsed(_market, _receiver, _stabilityFundDelta);
    }

    /// @notice Validate the leverage of a position
    /// @param _margin The margin of the position
    /// @param _size The size of the position
    /// @param _maxLeverage The maximum acceptable leverage of the position
    function validateLeverage(uint128 _margin, uint128 _size, uint8 _maxLeverage) internal pure {
        unchecked {
            if (uint256(_margin) * _maxLeverage < _size)
                revert IMarketErrors.LeverageTooHigh(_margin, _size, _maxLeverage);
        }
    }

    function safePermit(IERC20 _token, address _spender, bytes calldata _data) internal {
        if (_data.length == 0) return;
        OneInchSafeERC20.safePermit(_token, msg.sender, _spender, _data);
    }
}
