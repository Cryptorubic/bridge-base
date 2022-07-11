pragma solidity ^0.8.0;

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

        for (uint256 i = 0; i < _routers.length; i++) {
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
        uint256 amount = availableIntegratorFee[msg.sender];
        require(amount > 0, 'STT: amount is zero');

        availableIntegratorFee[msg.sender] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, amount);
    }

    function collectIntegratorFee(address _integrator) external onlyManagerAndAdmin {
        uint256 amount = availableIntegratorFee[_integrator];
        require(amount > 0, 'STT: amount is zero');

        availableIntegratorFee[_integrator] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(_integrator, amount);
    }

    function collectRubicFee() external onlyManagerAndAdmin {
        uint256 amount = availableRubicFee;
        require(amount > 0, 'STT: amount is zero');

        availableRubicFee = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Changes requirement for minimal token amount on transfers
     * @param _minTokenAmount Amount of tokens
     */
    function setMinTokenAmount(uint256 _minTokenAmount) external onlyManagerAndAdmin {
        minTokenAmount = _minTokenAmount;
    }

    /**
     * @dev Changes requirement for maximum token amount on transfers
     * @param _maxTokenAmount Amount of tokens
     */
    function setMaxTokenAmount(uint256 _maxTokenAmount) external onlyManagerAndAdmin {
        maxTokenAmount = _maxTokenAmount;
    }
}
