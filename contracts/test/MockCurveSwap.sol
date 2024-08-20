// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockCurveSwap {
    function exchange(
        address[4] memory _route,
        uint256[][] memory /*_swap_params*/,
        uint256 _amount,
        uint256 _min_dy,
        address[5] memory /*_pools*/,
        address _receiver
    ) public returns (uint256) {
        address input_token = _route[0];
        address output_token = address(0);
        uint256 amount = _amount;
        IERC20(input_token).transferFrom(msg.sender, address(this), _amount);

        for (uint i = 0; i < 1; i++) {
            output_token = _route[(i + 1) * 2];

            if (input_token == address(0)) {
                break;
            }

            // mock swap...
            amount = _min_dy;
            // if there is another swap, the output token becomes the input for the next round
            input_token = output_token;
        }

        IERC20(output_token).transfer(_receiver, amount);

        return amount;
    }
}
