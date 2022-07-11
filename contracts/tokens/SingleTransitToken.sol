pragma solidity ^0.8.10;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import '../BridgeBase.sol';

contract SingleTransitToken is BridgeBase, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public transitToken;

    uint256 public minTokenAmount;
    uint256 public maxTokenAmount;

    uint256 public availableRubicFee;
    mapping(address => uint256) public availableIntegratorFee;

    function __SingleTransitTokenInitUnchained(
        address[] memory _routers,
        address _transitToken,
        uint256 _minTokenAmount,
        uint256 _maxTokenAmount
    ) internal onlyInitializing {
        transitToken = _transitToken;

        minTokenAmount = _minTokenAmount;
        maxTokenAmount = _maxTokenAmount;

        for (uint256 i; i < _routers.length; i++) {
            IERC20Upgradeable(_transitToken).safeApprove(_routers[i], type(uint256).max);
        }
    }

    function accrueTokenFees(
        address _integrator,
        uint256 _amountWithFee,
        uint256 _initBlockchainNum
    ) internal returns (uint256) {
        (uint256 _totalFees, uint256 _RubicFee) = _calculateFee(_integrator, _amountWithFee, _initBlockchainNum);

        if (_integrator != address(0)) {
            availableIntegratorFee[_integrator] += _totalFees - _RubicFee;
        }
        availableRubicFee += _RubicFee;

        return _amountWithFee - _totalFees;
    }

    function collectIntegratorFee() external nonReentrant {
        uint256 _amount = availableIntegratorFee[msg.sender];
        if (_amount == 0) {
            revert ZeroAmount();
        }
        availableIntegratorFee[msg.sender] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, _amount);
    }

    function collectIntegratorFee(address _integrator) external onlyManagerAndAdmin {
        uint256 _amount = availableIntegratorFee[_integrator];
        if (_amount == 0) {
            revert ZeroAmount();
        }
        availableIntegratorFee[_integrator] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(_integrator, _amount);
    }

    function collectRubicFee() external onlyManagerAndAdmin {
        uint256 _amount = availableRubicFee;
        if (_amount == 0) {
            revert ZeroAmount();
        }
        availableRubicFee = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev Changes requirement for minimal token amount on transfers
     * @param _minTokenAmount Amount of tokens
     */
    function setMinTokenAmount(uint256 _minTokenAmount) external onlyManagerAndAdmin {
        if(_minTokenAmount > maxTokenAmount) {
            revert MinMustBeLowerThanMax();
        }
        minTokenAmount = _minTokenAmount;
    }

    /**
     * @dev Changes requirement for maximum token amount on transfers
     * @param _maxTokenAmount Amount of tokens
     */
    function setMaxTokenAmount(uint256 _maxTokenAmount) external onlyManagerAndAdmin {
        if(_maxTokenAmount < minTokenAmount) {
            revert MaxMustBeBiggerThanMin();
        }
        maxTokenAmount = _maxTokenAmount;
    }
}
