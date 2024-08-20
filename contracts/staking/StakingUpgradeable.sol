// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../libraries/MarketUtil.sol";
import "./interfaces/IStaking.sol";
import "../governance/GovernableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingUpgradeable is IStaking, GovernableUpgradeable {
    using SafeERC20 for IERC20;
    using MarketUtil for *;

    mapping(IERC20 token => uint256) public balances;
    mapping(IERC20 token => uint256) public maxStakedLimit;
    mapping(address account => mapping(IERC20 token => uint256)) public balancesPerAccount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialGov) public initializer {
        GovernableUpgradeable.__Governable_init(_initialGov);
    }

    /// @inheritdoc IStaking
    function stake(IERC20 _token, address _receiver, uint128 _amount, bytes calldata _permitData) external override {
        uint256 balanceAfter = balances[_token] + _amount;
        if (balanceAfter > maxStakedLimit[_token]) revert ExceededMaxStakedLimit(_amount);

        _token.safePermit(address(this), _permitData);
        IERC20(_token).safeTransferFrom(msg.sender, _receiver, _amount);
        balances[_token] = balanceAfter;
        unchecked {
            balancesPerAccount[_receiver][_token] += _amount;
        }
        emit Staked(_token, msg.sender, _receiver, _amount);
    }

    /// @inheritdoc IStaking
    function unstake(IERC20 _token, address _receiver, uint128 _amount) external override {
        uint256 balanceBefore = balancesPerAccount[msg.sender][_token];
        if (balanceBefore < _amount) revert InvalidInputAmount(_amount);

        unchecked {
            balances[_token] -= _amount;
            balancesPerAccount[msg.sender][_token] = balanceBefore - _amount;
        }
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit Unstaked(_token, msg.sender, _receiver, _amount);
    }

    /// @inheritdoc IStaking
    function setMaxStakedLimit(IERC20 _token, uint256 _limit) external override onlyGov {
        if (_limit < balances[_token]) revert InvalidLimit(_limit);
        maxStakedLimit[_token] = _limit;
        emit MaxStakedLimitSet(_token, _limit);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGov {}
}
