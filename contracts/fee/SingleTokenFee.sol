pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import "../BridgeBase.sol";
import "../libraries/FullMath.sol";

abstract contract SingleTokenFee is BridgeBase, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public transitToken;

    uint256 public availableRubicFee;
    mapping(address => uint256) public availableIntegratorFee;
    mapping(address => uint256) public integratorFee;
    mapping(address => uint256) public platformShare;

    function __SingleTokenFeeInit(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        uint256 _minTokenAmount,
        uint256 _maxTokenAmount,
        address[] memory _routers,
        address _transitToken
    ) internal onlyInitializing {
        __BridgeBaseInit(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _minTokenAmount,
            _maxTokenAmount,
            _routers
        );

        transitToken = _transitToken;

        for (uint256 i = 0; i < _routers.length; i++) {
            IERC20Upgradeable(_transitToken).safeApprove(_routers[i], type(uint256).max);
        }
    }

    function calculateFee(
        address integrator,
        uint256 amountWithFee,
        uint256 initBlockchainNum
    ) internal virtual returns(uint256 amountWithoutFee) {
        if (integrator != address(0)){
            uint256 integratorPercent = integratorFee[integrator];

            if (integratorPercent > 0){
                uint256 platformPercent = platformShare[integrator];

                uint256 _integratorAndProtocolFee = FullMath.mulDiv(
                    amountWithFee,
                    integratorPercent,
                    1e6
                );

                uint256 _platformFee = FullMath.mulDiv(
                    _integratorAndProtocolFee,
                    platformPercent,
                    1e6
                );

                availableIntegratorFee[integrator] += _integratorAndProtocolFee - _platformFee;
                availableRubicFee += _platformFee;

                amountWithoutFee = amountWithFee - _integratorAndProtocolFee;
            } else {
                amountWithoutFee = amountWithFee;
            }
        } else {
            amountWithoutFee = FullMath.mulDiv(
                amountWithFee,
                1e6 - feeAmountOfBlockchain[initBlockchainNum],
                1e6
            );

            availableRubicFee += amountWithFee - amountWithoutFee;
        }
    }

    function collectIntegratorFee() external nonReentrant {
        uint256 amount = availableIntegratorFee[msg.sender];
        require(amount > 0, 'SingleTokenFee: amount is zero');

        availableIntegratorFee[msg.sender] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, amount);
    }

    function collectIntegratorFee(address _integrator) external onlyManagerAndAdmin {
        uint256 amount = availableIntegratorFee[_integrator];
        require(amount > 0, 'SingleTokenFee: amount is zero');

        availableIntegratorFee[_integrator] = 0;

        IERC20Upgradeable(transitToken).safeTransfer(_integrator, amount);
    }

    function collectRubicFee() external onlyManagerAndAdmin {
        uint256 amount = availableRubicFee;
        require(amount > 0, 'SingleTokenFee: amount is zero');

        availableRubicFee = 0;

        IERC20Upgradeable(transitToken).safeTransfer(msg.sender, amount);
    }
}