pragma solidity ^0.8.10;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';

import './libraries/ECDSAOffsetRecovery.sol';
import './libraries/FullMath.sol';

import './errors/Errors.sol';

contract BridgeBase is AccessControlUpgradeable, PausableUpgradeable, ECDSAOffsetRecovery {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 internal constant DENOMINATOR = 1e6;

    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');

    mapping(address => uint256) public integratorFee; // TODO: check whether integrator is valid
    mapping(address => uint256) public platformShare;

    uint256 public fixedCryptoFee; // TODO struct with uint128
    uint256 public collectedCryptoFee;

    EnumerableSetUpgradeable.AddressSet internal availableRouters;

    struct BaseCrossChainParams {
        address srcInputToken;
        address dstOutputToken;
        address integrator;
        uint256 srcInputAmount;
        uint256 dstMinOutputAmount;
        uint256 dstChainID;
    }

    modifier onlyAdmin() {
        if (isAdmin(msg.sender) == false) {
            revert NotAnAdmin();
        }
        _;
    }

    modifier onlyManagerAndAdmin() {
        if (isAdmin(msg.sender) == false && isManager(msg.sender) == false) {
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

    function __BridgeBaseInit(uint256 _fixedCryptoFee, address[] memory _routers) internal onlyInitializing {
        __Pausable_init_unchained();

        fixedCryptoFee = _fixedCryptoFee;

        for (uint256 i; i < _routers.length; i++) {
            availableRouters.add(_routers[i]);
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    function _calculateFeeWithIntegrator(uint256 _amountWithFee, address _integrator)
        internal
        view
        returns (uint256 _totalFee, uint256 _RubicFee)
    {
        uint256 integratorPercent = integratorFee[_integrator];

        if (integratorPercent > 0) {
            uint256 platformPercent = platformShare[_integrator];

            _totalFee = FullMath.mulDiv(_amountWithFee, integratorPercent, DENOMINATOR);

            _RubicFee = FullMath.mulDiv(_totalFee, platformPercent, DENOMINATOR);
        }
    }

    function _calculateFee(
        address _integrator,
        uint256 _amountWithFee,
        uint256 _initBlockchainNum
    ) internal virtual view returns (uint256 _totalFee, uint256 _RubicFee) {}

    function accrueFixedCryptoFee() internal returns (uint256 _amountWithoutCryptoFee) {
        uint256 _cryptoFee = fixedCryptoFee;
        collectedCryptoFee += _cryptoFee;

        _amountWithoutCryptoFee = msg.value - _cryptoFee; // if _cryptoFee > msg.value it would revert (sol 0.8);
    }

    /// CONTROL FUNCTIONS ///

    function pauseExecution() external onlyManagerAndAdmin {
        _pause();
    }

    function unpauseExecution() external onlyManagerAndAdmin {
        _unpause();
    }

    function collectCryptoFee(address payable _to) external onlyManagerAndAdmin {
        uint256 _cryptoFee = collectedCryptoFee;
        collectedCryptoFee = 0;

        _to.transfer(_cryptoFee);
    }

    function setIntegratorFee(
        address _integrator,
        uint256 _fee,
        uint256 _platformShare
    ) external onlyManagerAndAdmin {
        if (_fee > DENOMINATOR) {
            revert FeeTooHigh();
        }

        integratorFee[_integrator] = _fee;
        platformShare[_integrator] = _platformShare;
    }

    function setFixedCryptoFee(uint256 _fixedCryptoFee) external onlyManagerAndAdmin {
        fixedCryptoFee = _fixedCryptoFee;
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
    function isManager(address _who) public view returns (bool) {
        return (hasRole(MANAGER_ROLE, _who));
    }

    /**
     * @dev Function to check if address is belongs to default admin role
     * @param _who Address to check
     */
    function isAdmin(address _who) public view returns (bool) {
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

    /**
     * @dev Plain fallback function
     */
    fallback() external {}

    /**
     * @dev Plain fallback function to receive crypto
     */
    receive() external payable {}

}
