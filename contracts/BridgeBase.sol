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

    // PLEASE rename cryptoFeeAmount
    mapping(uint256 => uint256) public feeAmountOfBlockchain;
    // cryptoFeeStored // cryptoFeeCollected // blockchainCryptoFeeStoredCollectedDisableRubic? XD
    mapping(uint256 => uint256) public blockchainCryptoFee;

    mapping(address => uint256) public integratorFee;
    mapping(address => uint256) public platformShare;

    mapping(bytes32 => SwapStatus) public processedTransactions;

    //EnumerableSetUpgradeable.AddressSet internal whitelistGateways;
    EnumerableSetUpgradeable.AddressSet internal availableRouters;

    /** Shows tx status with transfer id
     *  Null, - tx hasnt arrived yet
     *  Succeeded, - tx successfully executed on dst chain
     *  Failed, - tx failed on src chain, transfer transit token back to EOA
     *  Fallback - tx failed on dst chain, transfer transit token back to EOA
     */
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

    // In theory, what funcs will really need this modifier?
    modifier anyRole() {
        require(
            hasRole(MANAGER_ROLE, _msgSender()) ||
            hasRole(RELAYER_ROLE, _msgSender()) ||
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'BridgeBase: Caller is not in any role');
        _;
    }

    // I have tested it in remix, it works, but maybe lets think about that more? About security, a lot of projects
    // doesn't use it. Maybe some of the funcs shouldn't be only eoa in order to have a chance to have multy crosschain hops
    // E.x. Bsc via celer -> additional cross-chain via symbiosis Swap.
    // If we are using renBTC there is a need to make cross-chains to Eth, because all renBTC liquidity is there and
    // tx from BTC has 1 hour old slippage params
    // So You can BTC -> ETH, Then call Celer to swap RenBTC for ETH and cross-chain it to Polygon
    // This will be more profitable in most cases then doing swap in Poly renBTC to WETH because of liquidity problems
    // @notice Scalability issue
    modifier onlyEOA() {
        require(msg.sender == tx.origin, 'BridgeBase: only EOA');
        _;
    }

    // since some projects have there routers and gateways, which are added to whitelist to make approves
    // there is a need to add whitelist addresses
    // add executor/relayer address to whitelist? will save money in eth deployments
    function __BridgeBaseInit(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _routers
        // address[] memory _whitelistGateways,
        // address[] memory _relayers
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

//        for (uint256 i = 0; i < _whitelistGateways.length; i++) {
//            whitelistGateways.add(_whitelistGateways[i]);
//        }

//        for (uint256 i = 0; i < _relayers.length; i++) {
//            _setupRole(RELAYER_ROLE, _relayers[i]);
//        }

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
        // why not call{value: }
        // in audits it will be marked
        AddressUpgradeable.sendValue(_to, address(this).balance);
    }

    // @notice there are multiple transit tokens, this should have token address
    // @notice what if one cross-chain needs bigger fee amount while the other will have smaller
    // E.x. Celer platform fee in ETH is 0.04% but in Moonriver it is 0.6%, in Symbiosis it can be 0.01
    // so maybe be add there indetifier?
    function setIntegratorFee(
        address _integrator,
        uint256 _fee,
        uint256 _platformShare
    ) external onlyManagerAndAdmin {
        require(_fee <= 1000000, 'BridgeBase: fee too high');

        integratorFee[_integrator] = _fee;
        platformShare[_integrator] = _platformShare;
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

    // Sweep tokens is cool, but it will always be a weak point in audits

    // Add manual refund from Celer?

    function transferAdmin(address _newAdmin) external onlyAdmin {
        _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    }

    /**
     * @dev Function changes values associated with certain originalTxHash
     * @param _id ID of the transaction to change
     * @param _statusCode Associated status
     */
    function changeTxStatus(bytes32 _id, SwapStatus _statusCode)
        external
        onlyRelayer
    {
        require(
            _statusCode != SwapStatus.Null,
            "BridgeBase: cannot set the statusCode to Null"
        );
        require(
            processedTransactions[_id] != SwapStatus.Succeeded &&
            processedTransactions[_id] != SwapStatus.Fallback,
            "BridgeBase: cannot change Succeeded or Fallback status"
        );

        processedTransactions[_id] = _statusCode;
    }

    // there is change tx status func, but there is no compute id logic
    // message field can be replaced with nonce param or smth like that
//     function _computeSwapRequestId(
//        address _sender,
//        uint64 _srcChainId,
//        uint64 _dstChainId,
//        bytes memory _message
//    ) internal pure returns (bytes32) {
//        return keccak256(abi.encodePacked(_sender, _srcChainId, _dstChainId, _message));
//    }

    /// VIEW FUNCTIONS ///

//    function getAvailableGateways() external view returns(address[] memory) {
//        return whitelistGateways.values();
//    }

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

    // add strcuts for source swap info?

    // ============== struct for V2 like dexes ==============

//    struct SwapInfoV2 {
//        address dex; // the DEX to use for the swap
//        // if this array has only one element, it means no need to swap
//        address[] path;
//        // the following fields are only needed if path.length > 1
//        uint256 deadline; // deadline for the swap
//        uint256 amountOutMinimum; // minimum receive amount for the swap
//    }
//
//    // ============== struct for V3 like dexes ==============
//
//    struct SwapInfoV3 {
//        address dex; // the DEX to use for the swap
//        bytes path;
//        uint256 deadline;
//        uint256 amountOutMinimum;
//    }
//
//    // ============== struct for inch swap ==============
//
//    struct SwapInfoInch {
//        address dex;
//        // path is tokenIn, tokenOut
//        address[] path;
//        bytes data;
//        uint256 amountOutMinimum;
//    }
//    enum SwapVersion {
//        v2,
//        v3,
//        bridge
//    }
//
    // This funcs are used in all implementations with logic
    // Do you want to add swapV2Base and to add it there? Maybe all of that should be stored there
//    // returns address of first token for V3
//    function _getFirstBytes20(bytes memory input) internal pure returns (bytes20 result) {
//        assembly {
//            result := mload(add(input, 32))
//        }
//    }
//
//    // returns address of tokenOut for V3
//    function _getLastBytes20(bytes memory input) internal pure returns (bytes20 result) {
//        uint256 offset = input.length + 12;
//        assembly {
//            result := mload(add(input, offset))
//        }
//    }

}