// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "../../contracts/plugins/interfaces/IPositionRouterCommon.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPUSDManagerCallback {
    using SafeERC20 for *;

    IERC20 public payToken;
    uint96 public payAmount;
    uint96 public receiveAmount;
    uint96 public remaining;

    bool public ignoreTransfer;

    function setIgnoreTransfer() public {
        ignoreTransfer = true;
    }

    function PUSDManagerCallback(
        IERC20 _payToken,
        uint96 _payAmount,
        uint96 _receiveAmount,
        bytes calldata _data
    ) external {
        payToken = _payToken;
        payAmount = _payAmount;
        receiveAmount = _receiveAmount;

        IPositionRouterCommon.CallbackData memory data = abi.decode(_data, (IPositionRouterCommon.CallbackData));
        if (_payAmount > data.margin) revert IPositionRouterCommon.TooMuchPaid(_payAmount, data.margin);

        unchecked {
            // transfer remaining margin back to the account
            remaining = data.margin - _payAmount;
            if (remaining > 0) _payToken.safeTransfer(data.account, remaining);
        }

        // transfer pay token to the market manager
        if (!ignoreTransfer) _payToken.safeTransfer(msg.sender, _payAmount);
    }
}
