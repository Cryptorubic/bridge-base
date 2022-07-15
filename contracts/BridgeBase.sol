// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './libraries/ECDSAOffsetRecovery.sol';
import './libraries/FullMath.sol';

import './errors/Errors.sol';

contract BridgeBase is AccessControlUpgradeable, PausableUpgradeable, ECDSAOffsetRecovery, ReentrancyGuardUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Denominator for setting fees
    uint256 internal constant DENOMINATOR = 1e6;

    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');

    // Struct with all info about integrator fees
    mapping(address => IntegratorFeeInfo) public integratorToFeeInfo;
    // Amount of collected fees in native token integrator -> native fees
    mapping(address => uint256) public integratorToCollectedCryptoFee;

    // token -> minAmount for swap
    mapping(address => uint256) public minTokenAmount;
    // token -> maxAmount for swap
    mapping(address => uint256) public maxTokenAmount;

    // token -> rubic collected fees
    mapping(address => uint256) public availableRubicFee;
    // token -> integrator collected fees
    mapping(address => mapping(address => uint256)) public availableIntegratorFee;

    // Rubic fixed fee for swap
    uint256 public fixedCryptoFee;
    // Collected rubic fees in native token
    uint256 public collectedCryptoFee;

    // AddressSet of whitelisted addresses
    EnumerableSetUpgradeable.AddressSet internal availableRouters;

    event FixedCryptoFee(uint256 RubicPart, uint256 integrtorPart, address integrator);
    event FixedCryptoFeeCollected(uint256 amount, address collector);

    struct IntegratorFeeInfo {
        bool isIntegrator; // flag for setting 0 fees for integrator      - 1 byte
        uint32 tokenFee; // total fee percent gathered from user          - 4 bytes
        uint32 RubicFixedCryptoShare; // native share of fixed commission - 4 bytes
        uint32 RubicTokenShare; // token share of platform commission     - 4 bytes
        uint128 fixedFeeAmount; // custom fixed fee amount                - 16 bytes
    } //                                                            total - 29 bytes <= 32 bytes

    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
    }

    // reference to https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3347/
    modifier onlyAdmin() {
        if (!isAdmin(msg.sender)) {
            revert NotAnAdmin();
        }
        _;
    }

    modifier onlyManagerAndAdmin() {
        if (!isAdmin(msg.sender) && !isManager(msg.sender)) {
            revert NotAManager();
        }
        _;
    }

    modifier onlyEOA() {
        if (msg.sender != tx.origin) {
            revert OnlyEOA();
        }
        _;
    }

    function __BridgeBaseInit(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts
    ) internal onlyInitializing {
        __Pausable_init_unchained();

        fixedCryptoFee = _fixedCryptoFee;

        uint256 routerLength = _routers.length;
        for (uint256 i; i < routerLength; ) {
            availableRouters.add(_routers[i]);
            unchecked {
                ++i;
            }
        }

        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength; ) {
            if (_minTokenAmounts[i] > _maxTokenAmounts[i]) {
                revert MinMustBeLowerThanMax();
            }
            minTokenAmount[_tokens[i]] = _minTokenAmounts[i];
            maxTokenAmount[_tokens[i]] = _maxTokenAmounts[i];
            unchecked {
                ++i;
            }
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function accrueFixedCryptoFee(address _integrator, IntegratorFeeInfo memory _info)
        internal
        virtual
        returns (uint256 _fixedCryptoFee)
    {
        // reference to https://gist.github.com/grGred/9bab8b9bad0cd42fc23d4e31e7347144#-0-is-cheaper-than--0-sometimes
        if (_info.fixedFeeAmount > 0) {
            // '>' is cheaper than '!=' in if statements with optimizer enabled
            _fixedCryptoFee = uint256(_info.fixedFeeAmount);
        } else {
            _fixedCryptoFee = fixedCryptoFee;
        }

        // made only for swaps with tokens since msg.value with native swaps will be bigger than fixed fee amount
        if (msg.value < _fixedCryptoFee) {
            revert InefficientFixedFee();
        }

        uint256 _integratorCryptoFee = (_fixedCryptoFee * _info.RubicFixedCryptoShare) / DENOMINATOR;
        uint256 _RubicPart = _fixedCryptoFee - _integratorCryptoFee;

        collectedCryptoFee += _RubicPart;
        integratorToCollectedCryptoFee[_integrator] += _integratorCryptoFee;

        emit FixedCryptoFee(_RubicPart, _integratorCryptoFee, _integrator);
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

    /**
     * @dev Calculates fee amount for integrator and rubic, used in architecture
     * @param _amountWithFee the users initial amount
     * @param _info the struct with data about integrator
     * @return _totalFee the amount of Rubic + integrator fee
     * @return _RubicFee the amount of Rubic fee only
     */
    function _calculateFeeWithIntegrator(uint256 _amountWithFee, IntegratorFeeInfo memory _info)
        internal
        pure
        returns (uint256 _totalFee, uint256 _RubicFee)
    {
        if (_info.tokenFee > 0) {
            _totalFee = FullMath.mulDiv(_amountWithFee, _info.tokenFee, DENOMINATOR);

            _RubicFee = FullMath.mulDiv(_totalFee, _info.RubicTokenShare, DENOMINATOR);
        }
    }

    function _collectIntegrator(address _integrator, address _token) private {
        uint256 _amount;

        if (_token == address(0)) {
            _amount = integratorToCollectedCryptoFee[_integrator];
            integratorToCollectedCryptoFee[_integrator] = 0;
            emit FixedCryptoFeeCollected(_amount, _integrator);
        }

        _amount += availableIntegratorFee[_token][_integrator];

        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableIntegratorFee[_token][_integrator] = 0;

        _sendToken(_token, _amount, _integrator);
    }

    function collectIntegratorFee(address _token) external nonReentrant {
        _collectIntegrator(_token, msg.sender);
    }

    function collectIntegratorFee(address _integrator, address _token) external onlyManagerAndAdmin {
        _collectIntegrator(_token, _integrator);
    }

    function collectRubicFee(address _token) external onlyManagerAndAdmin {
        uint256 _amount = availableRubicFee[_token];
        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableRubicFee[_token] = 0;
        _sendToken(_token, _amount, msg.sender);
    }

    function collectRubicCryptoFee() external onlyManagerAndAdmin {
        uint256 _cryptoFee = collectedCryptoFee;
        collectedCryptoFee = 0;

        _sendToken(address(0), _cryptoFee, msg.sender);

        emit FixedCryptoFeeCollected(_cryptoFee, address(0));
    }

    /// CONTROL FUNCTIONS ///

    function pauseExecution() external onlyManagerAndAdmin {
        _pause();
    }

    function unpauseExecution() external onlyManagerAndAdmin {
        _unpause();
    }

    function setIntegratorInfo(address _integrator, IntegratorFeeInfo memory _info) external onlyManagerAndAdmin {
        if (_info.tokenFee > DENOMINATOR) {
            revert FeeTooHigh();
        }
        if (_info.RubicTokenShare > DENOMINATOR) {
            revert ShareTooHigh();
        }
        if (_info.RubicFixedCryptoShare > DENOMINATOR) {
            revert ShareTooHigh();
        }
        // underflow is not possible because of the if statement higher
        unchecked {
            _info.RubicFixedCryptoShare = uint32(DENOMINATOR) - _info.RubicFixedCryptoShare;
        }

        integratorToFeeInfo[_integrator] = _info;
    }

    function setFixedCryptoFee(uint256 _fixedCryptoFee) external onlyManagerAndAdmin {
        fixedCryptoFee = _fixedCryptoFee;
    }

    /**
     * @dev Changes requirement for minimal token amount on transfers
     * @param _token The token address to setup
     * @param _minTokenAmount Amount of tokens
     */
    function setMinTokenAmount(address _token, uint256 _minTokenAmount) external onlyManagerAndAdmin {
        if (_minTokenAmount > maxTokenAmount[_token]) {
            // can be equal in case we want them to be zero
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
        if (_maxTokenAmount < maxTokenAmount[_token]) {
            // can be equal in case we want them to be zero
            revert MaxMustBeBiggerThanMin();
        }
        maxTokenAmount[_token] = _maxTokenAmount;
    }

    function addAvailableRouter(address _router) external onlyManagerAndAdmin {
        if (_router == address(0)) {
            revert ZeroAddress();
        }
        availableRouters.add(_router);
    }

    function removeAvailableRouter(address _router) external onlyManagerAndAdmin {
        availableRouters.remove(_router);
    }

    function transferAdmin(address _newAdmin) external onlyAdmin {
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    }

    /// VIEW FUNCTIONS ///

    function getAvailableRouters() external view returns (address[] memory) {
        return availableRouters.values();
    }

    /**
     * @dev Function to check if address is belongs to manager role
     * @param _who Address to check
     */
    function isManager(address _who) internal view virtual returns (bool) {
        return (hasRole(MANAGER_ROLE, _who));
    }

    /**
     * @dev Function to check if address is belongs to default admin role
     * @param _who Address to check
     */
    function isAdmin(address _who) internal view virtual returns (bool) {
        return (hasRole(DEFAULT_ADMIN_ROLE, _who));
    }

    /// UTILS ///

    function smartApprove(
        address _tokenIn,
        uint256 _amount,
        address _to
    ) internal {
        IERC20Upgradeable tokenIn = IERC20Upgradeable(_tokenIn);
        uint256 _allowance = tokenIn.allowance(address(this), _to);
        if (_allowance < _amount) {
            if (_allowance == 0) {
                tokenIn.safeApprove(_to, type(uint256).max);
            } else {
                try tokenIn.approve(_to, type(uint256).max) returns (bool res) {
                    if (!res) {
                        revert ApproveFailed();
                    }
                } catch {
                    tokenIn.safeApprove(_to, 0);
                    tokenIn.safeApprove(_to, type(uint256).max);
                }
            }
        }
    }

    function _sendToken(
        address _token,
        uint256 _amount,
        address _receiver
    ) internal virtual {
        if (_token == address(0)) {
            AddressUpgradeable.sendValue(payable(_receiver), _amount);
        } else {
            IERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
        }
    }

    function _calculateFee(
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256 _initBlockchainNum
    ) internal view virtual returns (uint256 _totalFee, uint256 _RubicFee) {}

    /**
     * @dev Plain fallback function to receive native
     */
    receive() external payable {}

    /**
     * @dev Plain fallback function
     */
    fallback() external {}
}
