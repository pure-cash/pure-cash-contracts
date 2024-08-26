// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "./interfaces/IPUSD.sol";
import "../libraries/Constants.sol";
import "../governance/Governable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PUSD is ERC20, ERC20Permit, IPUSD {
    address public immutable marketManager;

    constructor() ERC20("Pure USD", "PUSD") ERC20Permit("Pure USD") {
        marketManager = msg.sender;
    }

    /// @inheritdoc ERC20
    function decimals() public view virtual override returns (uint8) {
        return Constants.DECIMALS_6;
    }

    /// @inheritdoc IPUSD
    function mint(address _to, uint256 _value) external override {
        require(msg.sender == marketManager, Governable.Forbidden());

        _mint(_to, _value);
    }

    /// @inheritdoc IPUSD
    function burn(uint256 _value) external override {
        require(msg.sender == marketManager, Governable.Forbidden());

        _burn(msg.sender, _value);
    }
}
