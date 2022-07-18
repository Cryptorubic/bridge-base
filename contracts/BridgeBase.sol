// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './libraries/FullMath.sol';

import './errors/Errors.sol';

contract BridgeBase is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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

    event FixedCryptoFee(uint256 RubicPart, uint256 integratorPart, address integrator);
    event FixedCryptoFeeCollected(uint256 amount, address collector);
    event TokenFee(uint256 RubicPart, uint256 integratorPart, address integrator, address token);
    event IntegratorTokenFeeCollected(uint256 amount, address integrator, address token);
    event RubicTokenFeeCollected(uint256 amount, address token);

    struct IntegratorFeeInfo {
        bool isIntegrator; // flag for setting 0 fees for integrator      - 1 byte
        uint32 tokenFee; // total fee percent gathered from user          - 4 bytes
        uint32 RubicTokenShare; // token share of platform commission     - 4 bytes
        uint32 RubicFixedCryptoShare; // native share of fixed commission - 4 bytes
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
        checkIsAdmin();
        _;
    }

    modifier onlyManagerAndAdmin() {
        checkIsManagerOrAdmin();
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

    /**
     * @dev Calculates and accrues fixed crypto fee
     * @param _integrator Integrator's address if there is one
     * @param _info A struct with integrator fee info
     * @return The msg.value without fixedCryptoFee
     */
    function accrueFixedCryptoFee(address _integrator, IntegratorFeeInfo memory _info)
        internal
        returns (uint256)
    {
        uint256 _fixedCryptoFee;
        uint256 _RubicPart;
        // reference to https://gist.github.com/grGred/9bab8b9bad0cd42fc23d4e31e7347144#-0-is-cheaper-than--0-sometimes
        if (_info.fixedFeeAmount > 0 && _info.isIntegrator) {
            // '>' is cheaper than '!=' in if statements with optimizer enabled
            _fixedCryptoFee = uint256(_info.fixedFeeAmount);
            _RubicPart = (_fixedCryptoFee * _info.RubicFixedCryptoShare) / DENOMINATOR;

            integratorToCollectedCryptoFee[_integrator] += _fixedCryptoFee - _RubicPart;

            emit FixedCryptoFee(_RubicPart, _fixedCryptoFee - _RubicPart, _integrator);
        } else {
            _fixedCryptoFee = fixedCryptoFee;

            emit FixedCryptoFee(_fixedCryptoFee, 0, address(0));
        }

        collectedCryptoFee += _RubicPart;

        // Underflow is not possible
        return (msg.value - _fixedCryptoFee);
    }

    /**
     * @dev Calculates token fees and accrues them
     * @param _integrator Integrator's address if there is one
     * @param _info A struct with fee info about integrator
     * @param _amountWithFee Total amount passed by the user
     * @param _token The token in which the fees are collected
     * @param _initBlockchainNum Used if the _calculateFee is overriden by
     * WithDestinationFunctionality, otherwise is ignored
     * @return Amount of tokens without fee
     */
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

        emit TokenFee(_RubicFee, _totalFees - _RubicFee, _integrator, _token);

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

    /// COLLECT FUNCTIONS ///

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

        sendToken(_token, _amount, _integrator);

        emit IntegratorTokenFeeCollected(_amount, _integrator, _token);
    }

    /**
     * @dev Integrator can collect fees calling this function
     * @param _token The token to collect fees in
     */
    function collectIntegratorFee(address _token) external nonReentrant {
        _collectIntegrator(_token, msg.sender);
    }

    /**
     * @dev Managers can collect integrator's fees calling this function
     * Fees go to the integrator
     * @param _integrator Address of the integrator
     * @param _token The token to collect fees in
     */
    function collectIntegratorFee(address _integrator, address _token) external onlyManagerAndAdmin {
        _collectIntegrator(_token, _integrator);
    }

    /**
     * @dev Calling this function managers can collect Rubic's token fee
     * @param _token The token to collect fees in
     */
    function collectRubicFee(address _token) external onlyManagerAndAdmin {
        uint256 _amount = availableRubicFee[_token];
        if (_amount == 0) {
            revert ZeroAmount();
        }

        availableRubicFee[_token] = 0;
        sendToken(_token, _amount, msg.sender);

        emit RubicTokenFeeCollected(_amount, _token);
    }

    /**
     * @dev Calling this function managers can collect Rubic's fixed crypto fee
     */
    function collectRubicCryptoFee() external onlyManagerAndAdmin {
        uint256 _cryptoFee = collectedCryptoFee;
        collectedCryptoFee = 0;

        sendToken(address(0), _cryptoFee, msg.sender);

        emit FixedCryptoFeeCollected(_cryptoFee, msg.sender);
    }

    /// CONTROL FUNCTIONS ///

    function pauseExecution() external onlyManagerAndAdmin {
        _pause();
    }

    function unpauseExecution() external onlyManagerAndAdmin {
        _unpause();
    }

    /**
     * @dev Sets fee info associated with an integrator
     * @param _integrator Address of the integrator
     * @param _info Struct with fee info
     */
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

        integratorToFeeInfo[_integrator] = _info;
    }

    /**
     * @dev Sets fixed crypto fee
     * @param _fixedCryptoFee Fixed crypto fee
     */
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

    /**
     * @dev Appends new available router
     * @param _router Router's address to add
     */
    function addAvailableRouter(address _router) external onlyManagerAndAdmin {
        if (_router == address(0)) {
            revert ZeroAddress();
        }
        // Check that router exists is performed inside the library
        availableRouters.add(_router);
    }

    /**
     * @dev Removes existing available router
     * @param _router Router's address to remove
     */
    function removeAvailableRouter(address _router) external onlyManagerAndAdmin {
        // Check that router exists is performed inside the library
        availableRouters.remove(_router);
    }

    /**
     * @dev Transfers admin role
     * @param _newAdmin New admin's address
     */
    function transferAdmin(address _newAdmin) external onlyAdmin {
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    }

    /// VIEW FUNCTIONS ///

    /**
     * @return Available routers
     */
    function getAvailableRouters() external view returns (address[] memory) {
        return availableRouters.values();
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if address is belongs to manager or admin role
     */
    function checkIsManagerOrAdmin() internal view {
        if (!(hasRole(MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))) {
            revert NotAManager();
        }
    }

    /**
     * @notice Used in modifiers
     * @dev Function to check if address is belongs to default admin role
     */
    function checkIsAdmin() internal view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAnAdmin();
        }
    }

    function sendToken(
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
