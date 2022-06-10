pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import "../BridgeBase.sol";
import "../libraries/FullMath.sol";

abstract contract MultipleTransitToken is BridgeBase, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => uint256) public minTokenAmount;
    mapping(address => uint256) public maxTokenAmount;

    mapping(address => uint256) public availableRubicFee;
    mapping(address => mapping(address => uint256)) public availableIntegratorFee;

    function __MultipleTransitTokenInit(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address[] memory _routers
    ) internal onlyInitializing {
        __BridgeBaseInit(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _routers
        );

        for (uint i=0; i < _tokens.length; i++) {
            require(_minTokenAmounts[i] < _maxTokenAmounts[i], 'MultipleTransitToken: min >= max');
            minTokenAmount[_tokens[i]] = _minTokenAmounts[i];
            maxTokenAmount[_tokens[i]] = _maxTokenAmounts[i];
        }
    }

    // rename for each? calculateFeeMulty
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
        require(amount > 0, 'MultipleTransitToken: amount is zero');

        availableIntegratorFee[_token][msg.sender] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(msg.sender), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
        }
    }

    function collectIntegratorFee(address _token, address _integrator) external onlyManagerAndAdmin {
        uint256 amount = availableIntegratorFee[_token][_integrator];
        require(amount > 0, 'MultipleTransitToken: amount is zero');

        availableIntegratorFee[_token][_integrator] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(_integrator), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(_integrator, amount);
        }
    }

    function collectRubicFee(address _token) external onlyManagerAndAdmin {
        uint256 amount = availableRubicFee[_token];
        require(amount > 0, 'MultipleTransitToken: amount is zero');

        availableRubicFee[_token] = 0;

        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(msg.sender), amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @dev Changes requirement for minimal token amount on transfers
     * @param _token The token address to setup
     * @param _minTokenAmount Amount of tokens
     */
    function setMinTokenAmount(address _token, uint256 _minTokenAmount)
        external
        onlyManagerAndAdmin
    {
        minTokenAmount[_token] = _minTokenAmount;
    }

    /**
     * @dev Changes requirement for maximum token amount on transfers
     * @param _token The token address to setup
     * @param _maxTokenAmount Amount of tokens
     */
    function setMaxTokenAmount(address _token, uint256 _maxTokenAmount)
        external
        onlyManagerAndAdmin
    {
        maxTokenAmount[_token] = _maxTokenAmount;
    }
}