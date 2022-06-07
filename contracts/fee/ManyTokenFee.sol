pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import "../BridgeBase.sol";
import "../libraries/FullMath.sol";

abstract contract ManyTokenFee is BridgeBase, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => uint256) public availableRubicFee;
    mapping(address => mapping(address => uint256)) public availableIntegratorFee;
    mapping(address => uint256) public integratorFee;
    mapping(address => uint256) public platformShare;

    function __ManyTokenFeeInit(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        uint256 _minTokenAmount,
        uint256 _maxTokenAmount,
        address[] memory _routers
    ) internal onlyInitializing {
        __BridgeBaseInit(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _minTokenAmount,
            _maxTokenAmount,
            _routers
        );
    }

    function calculateFee(
        address integrator,
        uint256 amountWithFee,
        uint256 initBlockchainNum,
        address token
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

                availableIntegratorFee[token][integrator] += _integratorAndProtocolFee - _platformFee;
                availableRubicFee[token] += _platformFee;

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

            availableRubicFee[token] += amountWithFee - amountWithoutFee;
        }
    }

    function collectIntegratorFee(address _token) external nonReentrant {
        uint256 amount = availableIntegratorFee[_token][msg.sender];
        require(amount > 0, 'ManyTokenFee: amount is zero');

        availableIntegratorFee[_token][msg.sender] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(msg.sender), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
        }
    }

    function collectIntegratorFee(address _token, address _integrator) external onlyManagerAndAdmin {
        uint256 amount = availableIntegratorFee[_token][_integrator];
        require(amount > 0, 'ManyTokenFee: amount is zero');

        availableIntegratorFee[_token][_integrator] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(_integrator), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(_integrator, amount);
        }
    }

    function collectRubicFee(address _token) external onlyManagerAndAdmin {
        uint256 amount = availableRubicFee[_token];
        require(amount > 0, 'ManyTokenFee: amount is zero');

        availableRubicFee[_token] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(msg.sender), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
        }
    }
}