// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library TransferHelper {
    error TransferFailed(IERC20 token);

    function safeTransfer(IERC20 _token, address _receiver, uint256 _amount) internal {
        (bool success, bytes memory returnData) = address(_token).call(
            abi.encodeCall(_token.transfer, (_receiver, _amount))
        );
        _validateCallResult(_token, success, returnData);
    }

    function safeTransfer(IERC20 _token, address _receiver, uint256 _amount, uint256 _gasLimit) internal {
        (bool success, bytes memory returnData) = address(_token).call{gas: _gasLimit}(
            abi.encodeCall(_token.transfer, (_receiver, _amount))
        );
        _validateCallResult(_token, success, returnData);
    }

    function _validateCallResult(IERC20 _token, bool _success, bytes memory _returnData) private view {
        _returnData = Address.verifyCallResultFromTarget(address(_token), _success, _returnData);
        if (_returnData.length != 0 && !abi.decode(_returnData, (bool))) revert TransferFailed(_token);
    }
}
