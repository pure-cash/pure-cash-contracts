// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract ERC20Test is ERC20, ERC20Permit {
    // Set the transfer result
    bool private transferRes;
    // To simulate an attack that drain the gas in transfer
    bool private drainGasInTransfer;
    uint8 private myDecimals;

    receive() external payable {}

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        myDecimals = _decimals;
        transferRes = true;
        drainGasInTransfer = false;

        _mint(_msgSender(), _initialSupply);
    }

    function setTransferRes(bool _transferRes) external {
        transferRes = _transferRes;
    }

    function setDrainGasInTransfer(bool _drainGas) external {
        drainGasInTransfer = _drainGas;
    }

    function decimals() public view override returns (uint8) {
        return myDecimals;
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        if (drainGasInTransfer) while (true) {}

        address owner = _msgSender();
        _transfer(owner, to, value);
        return transferRes;
    }
}
