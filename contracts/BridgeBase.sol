pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./libraries/ECDSAOffsetRecovery.sol";
import "./libraries/FullMath.sol";

contract BridgeBase is AccessControlUpgradeable, PausableUpgradeable, ECDSAOffsetRecovery {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    uint256 public constant SIGNATURE_LENGTH = 65;

    uint256 public numOfThisBlockchain;
    uint256 public minConfirmationSignatures;

    mapping(uint256 => uint256) public feeAmountOfBlockchain;
    mapping(uint256 => uint256) public blockchainCryptoFee;

    mapping(bytes32 => uint256) public processedTransactions;

    EnumerableSetUpgradeable.AddressSet internal availableRouters;

    enum SwapStatus {
        Null,
        Succeeded,
        Failed,
        Fallback
    }
    
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), 'BridgeBase: Caller is not in admin role');
        _;
    }

    modifier onlyManagerAndAdmin() {
        require(hasRole(MANAGER_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), 'BridgeBase: Caller is not in manager or admin role');
        _;
    }

    modifier onlyRelayer() {
        require(hasRole(RELAYER_ROLE, _msgSender()), 'BridgeBase: Caller is not in relayer role');
        _;
    }

    modifier anyRole() {
        require(
            hasRole(MANAGER_ROLE, _msgSender()) ||
            hasRole(RELAYER_ROLE, _msgSender()) ||
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'BridgeBase: Caller is not in any role');
        _;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, 'BridgeBase: only EOA');
        _;
    }

    function __BridgeBaseInit(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _routers
    ) internal onlyInitializing {
        __Pausable_init_unchained();

        require(
            _cryptoFees.length == _platformFees.length,
            'BridgeBase: fees lengths mismatch'
        );

        for (uint256 i = 0; i < _cryptoFees.length; i++) {
            blockchainCryptoFee[_blockchainIDs[i]] = _cryptoFees[i];
            feeAmountOfBlockchain[_blockchainIDs[i]] = _platformFees[i];
        }

        for (uint256 i = 0; i < _routers.length; i++) {
            availableRouters.add(_routers[i]);
        }

        minConfirmationSignatures = 3;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// CONTROL FUNCTIONS ///

    function pauseExecution() external onlyManagerAndAdmin {
        _pause();
    }

    function unpauseExecution() external onlyManagerAndAdmin {
        _unpause();
    }

    function collectCryptoFee(address payable _to) external onlyManagerAndAdmin {
        AddressUpgradeable.sendValue(_to, address(this).balance);
    }

    /**
     * @dev Changes tokens values for blockchains in feeAmountOfBlockchain variables
     * @notice tokens is represented as hundredths of a bip, i.e. 1e-6
     * @param _blockchainID ID of the blockchain
     * @param _feeAmount Fee amount to subtract from transfer amount
     */
    function setFeeAmountOfBlockchain(uint256 _blockchainID, uint256 _feeAmount)
        external
        onlyManagerAndAdmin
    {
        feeAmountOfBlockchain[_blockchainID] = _feeAmount;
    }

    /**
     * @dev Changes crypto tokens values for blockchains in blockchainCryptoFee variables
     * @param _blockchainID ID of the blockchain
     * @param _feeAmount Fee amount of native token that must be sent in init call
     */
    function setCryptoFeeOfBlockchain(uint256 _blockchainID, uint256 _feeAmount)
        external
        anyRole
    {
        blockchainCryptoFee[_blockchainID] = _feeAmount;
    }

    /**
     * @dev Changes requirement for minimal amount of signatures to validate on transfer
     * @param _minConfirmationSignatures Number of signatures to verify
     */
    function setMinConfirmationSignatures(uint256 _minConfirmationSignatures)
        external
        onlyAdmin
    {
        require(
            _minConfirmationSignatures > 0,
            "BridgeBase: At least 1 confirmation can be set"
        );
        minConfirmationSignatures = _minConfirmationSignatures;
    }

    function transferAdmin(address _newAdmin) external onlyAdmin {
        _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    }

    /**
     * @dev Function changes values associated with certain originalTxHash
     * @param originalTxHash Transaction hash to change
     * @param statusCode Associated status: 0-Not processed, 1-Processed, 2-Reverted
     */
    function changeTxStatus(bytes32 originalTxHash, uint256 statusCode)
        external
        onlyRelayer
    {
        require(
            statusCode != 0,
            "swapContract: you cannot set the statusCode to 0"
        );
        require(
            processedTransactions[originalTxHash] != 1,
            "swapContract: transaction with this originalTxHash has already been set as succeed"
        );
        processedTransactions[originalTxHash] = statusCode;
    }

    /// VIEW FUNCTIONS ///

    function getAvailableRouters() external view returns(address[] memory) {
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

    /**
     * @dev Function to check if address is belongs to relayer role
     * @param _who Address to check
     */
    function isRelayer(address _who) public view returns (bool) {
        return hasRole(RELAYER_ROLE, _who);
    }

    /**
     * @dev Function to check if address is belongs to validator role
     * @param _who Address to check
     */
    function isValidator(address _who) public view returns (bool) {
        return hasRole(VALIDATOR_ROLE, _who);
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
                    require(res == true, 'BridgeBase: approve failed');
                } catch {
                    tokenIn.safeApprove(_to, 0);
                    tokenIn.safeApprove(_to, type(uint256).max);
                }
            }
        }
    }

    /**
     * @dev Plain fallback function to receive crypto
     */
    receive() external payable {}

    /**
     * @dev Plain fallback function to receive crypto
     */
    fallback() external payable {}
}