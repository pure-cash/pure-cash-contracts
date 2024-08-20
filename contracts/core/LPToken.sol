// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../libraries/Constants.sol";
import "./interfaces/ILPToken.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract LPToken is ILPToken, ERC20Permit {
    address public immutable marketManager;

    IERC20 public market;
    string private _symbol;

    error Forbidden();
    error AlreadyInitialized();

    modifier onlyMarketManager() {
        if (marketManager != _msgSender()) revert Forbidden();
        _;
    }

    constructor() ERC20("Pure.cash LP", "") ERC20Permit("Pure.cash LP") {
        marketManager = _msgSender();
    }

    function initialize(IERC20 market_, string calldata symbol_) external onlyMarketManager {
        require(market == IERC20(address(0)), AlreadyInitialized());
        market = market_;
        _symbol = symbol_;
    }

    /// @inheritdoc ERC20
    function decimals() public pure virtual override returns (uint8) {
        return Constants.DECIMALS_6;
    }

    /// @inheritdoc ERC20
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address _to, uint256 _amount) external onlyMarketManager {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) external onlyMarketManager {
        _burn(msg.sender, _amount);
    }
}
