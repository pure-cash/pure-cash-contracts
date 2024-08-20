// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import "../libraries/Constants.sol";
import "../governance/GovernableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract FeeDistributorUpgradeable is GovernableUpgradeable {
    using SafeCast for *;

    struct FeeDistribution {
        uint128 protocolFee;
        uint128 ecosystemFee;
        uint128 developmentFund;
    }

    /// @notice The rate at which fees are distributed to the protocol,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    uint24 public protocolFeeRate;
    /// @notice The rate at which fees are distributed to the ecosystem,
    /// denominated in thousandths of a bip (i.e. 1e-7)
    uint24 public ecosystemFeeRate;
    mapping(IERC20 market => FeeDistribution) public feeDistributions;

    event FeeRateUpdated(uint24 newProtocolFeeRate, uint24 newEcosystemFeeRate);
    event FeeDeposited(IERC20 indexed token, uint128 protocolFee, uint128 ecosystemFee, uint128 developmentFund);
    event ProtocolFeeWithdrawal(IERC20 indexed token, address indexed receiver, uint128 amount);
    event EcosystemFeeWithdrawal(IERC20 indexed token, address indexed receiver, uint128 amount);
    event DevelopmentFundWithdrawal(IERC20 indexed token, address indexed receiver, uint128 amount);

    error InvalidFeeRate(uint24 protocolFeeRate, uint24 ecosystemFeeRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialGov, uint24 _protocolFeeRate, uint24 _ecosystemFeeRate) public initializer {
        GovernableUpgradeable.__Governable_init(_initialGov);
        _updateFeeRate(_protocolFeeRate, _ecosystemFeeRate);
    }

    function updateFeeRate(uint24 _protocolFeeRate, uint24 _ecosystemFeeRate) external onlyGov {
        _updateFeeRate(_protocolFeeRate, _ecosystemFeeRate);
    }

    function deposit(IERC20 _token) external {
        uint256 balance = _token.balanceOf(address(this));
        FeeDistribution storage feeDistribution = feeDistributions[_token];
        uint128 delta = (balance -
            feeDistribution.protocolFee -
            feeDistribution.developmentFund -
            feeDistribution.ecosystemFee).toUint128();
        unchecked {
            uint128 protocolFeeDelta = uint128((uint256(delta) * protocolFeeRate) / Constants.BASIS_POINTS_DIVISOR);
            uint128 ecosystemFeeDelta = uint128((uint256(delta) * ecosystemFeeRate) / Constants.BASIS_POINTS_DIVISOR);
            uint128 developmentFundDelta = delta - protocolFeeDelta - ecosystemFeeDelta;

            // overflow is desired
            feeDistribution.protocolFee += protocolFeeDelta;
            feeDistribution.ecosystemFee += ecosystemFeeDelta;
            feeDistribution.developmentFund += developmentFundDelta;

            emit FeeDeposited(_token, protocolFeeDelta, ecosystemFeeDelta, developmentFundDelta);
        }
    }

    function withdrawProtocolFee(IERC20 _token, address _receiver, uint128 _amount) external onlyGov {
        feeDistributions[_token].protocolFee -= _amount;
        _token.transfer(_receiver, _amount);
        emit ProtocolFeeWithdrawal(_token, _receiver, _amount);
    }

    function withdrawEcosystemFee(IERC20 _token, address _receiver, uint128 _amount) external onlyGov {
        feeDistributions[_token].ecosystemFee -= _amount;
        _token.transfer(_receiver, _amount);
        emit EcosystemFeeWithdrawal(_token, _receiver, _amount);
    }

    function withdrawDevelopmentFund(IERC20 _token, address _receiver, uint128 _amount) external onlyGov {
        feeDistributions[_token].developmentFund -= _amount;
        _token.transfer(_receiver, _amount);
        emit DevelopmentFundWithdrawal(_token, _receiver, _amount);
    }

    function _updateFeeRate(uint24 _protocolFeeRate, uint24 _ecosystemFeeRate) internal {
        unchecked {
            require(
                uint32(_protocolFeeRate) + _ecosystemFeeRate <= Constants.BASIS_POINTS_DIVISOR,
                InvalidFeeRate(_protocolFeeRate, _ecosystemFeeRate)
            );
        }
        protocolFeeRate = _protocolFeeRate;
        ecosystemFeeRate = _ecosystemFeeRate;
        emit FeeRateUpdated(_protocolFeeRate, _ecosystemFeeRate);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGov {}
}
