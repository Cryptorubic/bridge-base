pragma solidity ^0.8.10;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import '../BridgeBase.sol';

contract MultipleTransitToken is BridgeBase, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => uint256) public minTokenAmount; // TODO: valid if set
    mapping(address => uint256) public maxTokenAmount;

    mapping(address => uint256) public availableRubicFee;
    mapping(address => mapping(address => uint256)) public availableIntegratorFee;

    function __MultipleTransitTokenInitUnchained(
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts
    ) internal onlyInitializing {
        for (uint256 i; i < _tokens.length; i++) {
            if (_minTokenAmounts[i] > _maxTokenAmounts[i]) {
                revert MinMustBeLowerThanMax();
            }
            minTokenAmount[_tokens[i]] = _minTokenAmounts[i];
            maxTokenAmount[_tokens[i]] = _maxTokenAmounts[i];
        }
    }

    function accrueTokenFees(
        address _integrator,
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256 _initBlockchainNum,
        address _token
    ) internal returns (uint256) {
        (uint256 _totalFees, uint256 _RubicFee) = _calculateFee(_info, _amountWithFee, _initBlockchainNum);

        if (_integrator != address(0)) {
            availableIntegratorFee[_token][_integrator] += _totalFees - _RubicFee;
        }
        availableRubicFee[_token] += _RubicFee;

        return _amountWithFee - _totalFees;
    }

    function collectIntegratorFee(address _token) external nonReentrant {
        uint256 _amount = availableIntegratorFee[_token][msg.sender];
        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableIntegratorFee[_token][msg.sender] = 0;
        _sendToken(_token, _amount, msg.sender);
    }

    function collectIntegratorFee(address _token, address _integrator) external onlyManagerAndAdmin { // TODO sum 2 funcs
        uint256 _amount = availableIntegratorFee[_token][_integrator];
        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableIntegratorFee[_token][_integrator] = 0;
        _sendToken(_token, _amount, _integrator);
    }

    function collectRubicFee(address _token) external onlyManagerAndAdmin {
        uint256 _amount = availableRubicFee[_token];
        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableRubicFee[_token] = 0;
        _sendToken(_token, _amount, msg.sender);
    }

    /**
     * @dev Changes requirement for minimal token amount on transfers
     * @param _token The token address to setup
     * @param _minTokenAmount Amount of tokens
     */
    function setMinTokenAmount(address _token, uint256 _minTokenAmount) external onlyManagerAndAdmin {
        if (_minTokenAmount > maxTokenAmount[_token]) { // can be equal in case we want them to be zero
            revert MinMustBeLowerThanMax();
        }
        minTokenAmount[_token] = _minTokenAmount;
    }

    /**
     * @dev Changes requirement for maximum token amount on transfers
     * @param _token The token address to setup
     * @param _maxTokenAmount Amount of tokens
     */
    function setMaxTokenAmount(address _token, uint256 _maxTokenAmount) external onlyManagerAndAdmin {
        if (_maxTokenAmount < maxTokenAmount[_token]) { // can be equal in case we want them to be zero
            revert MaxMustBeBiggerThanMin();
        }
        maxTokenAmount[_token] = _maxTokenAmount;
    }
}
