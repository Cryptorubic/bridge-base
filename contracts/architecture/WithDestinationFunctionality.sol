pragma solidity ^0.8.0;

import '../BridgeBase.sol';

contract WithDestinationFunctionality is BridgeBase {
    enum SwapStatus {
        Null,
        Succeeded,
        Failed,
        Fallback
    }

    mapping(bytes32 => SwapStatus) public processedTransactions;

    mapping(uint256 => uint256) public blockchainToRubicPlatformFee;
    mapping(uint256 => uint256) public blockchainToGasFee;

    uint256 public collectedGasFee;

    bytes32 public constant RELAYER_ROLE = keccak256('RELAYER_ROLE');

    modifier onlyRelayer() {
        require(isRelayer(msg.sender), 'WDF: not a relayer');
        _;
    }

    function __WithDestinationFunctionalityInitUnchained(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        uint256[] memory _blockchainIDs
    ) internal onlyInitializing {
        require(_gasFees.length == _RubicPlatformFees.length, 'WDF: fees length mismatch');

        for (uint256 i; i < _gasFees.length; i++) {
            blockchainToGasFee[_blockchainIDs[i]] = _gasFees[i];
            blockchainToRubicPlatformFee[_blockchainIDs[i]] = _RubicPlatformFees[i];
        }
    }

    function accrueGasFee(uint256 _blockchainID) internal returns (uint256 _gasFee) {
        _gasFee = blockchainToGasFee[_blockchainID];
        collectedGasFee += _gasFee;
    }

    function _calculateFee(
        address _integrator,
        uint256 _amountWithFee,
        uint256 initBlockchainNum
    ) internal override returns (uint256 _totalFee, uint256 _RubicFee) {
        if (_integrator != address(0)) {
            (_totalFee, _RubicFee) = _calculateFeeWithIntegrator(_amountWithFee, _integrator);
        } else {
            _totalFee = FullMath.mulDiv(_amountWithFee, blockchainToRubicPlatformFee[initBlockchainNum], DENOMINATOR);

            _RubicFee = _totalFee;
        }
    }

    /// FEE MANAGEMENT ///

    /**
     * @dev Changes tokens values for blockchains in feeAmountOfBlockchain variables
     * @notice tokens is represented as hundredths of a bip, i.e. 1e-6
     * @param _blockchainID ID of the blockchain
     * @param _RubicPlatformFee Fee amount to subtract from transfer amount
     */
    function setRubicPlatformFeeOfBlockchain(uint256 _blockchainID, uint256 _RubicPlatformFee)
        external
        onlyManagerAndAdmin
    {
        require(_RubicPlatformFee <= DENOMINATOR);
        blockchainToRubicPlatformFee[_blockchainID] = _RubicPlatformFee;
    }

    /**
     * @dev Changes crypto tokens values for blockchains in blockchainCryptoFee variables
     * @param _blockchainID ID of the blockchain
     * @param _gasFee Fee amount of native token that must be sent in init call
     */
    function setGasFeeOfBlockchain(uint256 _blockchainID, uint256 _gasFee) external onlyManagerAndAdmin {
        blockchainToGasFee[_blockchainID] = _gasFee;
    }

    function collectGasFee(address payable _to) external onlyManagerAndAdmin {
        uint256 _gasFee = collectedGasFee;
        collectedGasFee = 0;

        _to.transfer(_gasFee);
    }

    /// TX STATUSES MANAGEMENT ///

    /**
     * @dev Function changes values associated with certain originalTxHash
     * @param _id ID of the transaction to change
     * @param _statusCode Associated status
     */
    function changeTxStatus(bytes32 _id, SwapStatus _statusCode) external onlyRelayer {
        require(_statusCode != SwapStatus.Null, 'WDF: cant set to Null');
        require(
            processedTransactions[_id] != SwapStatus.Succeeded && processedTransactions[_id] != SwapStatus.Fallback,
            'WDF: unchangeable'
        );

        processedTransactions[_id] = _statusCode;
    }

    /// VIEW FUNCTIONS ///

    /**
     * @dev Function to check if address is belongs to relayer role
     * @param _who Address to check
     */
    function isRelayer(address _who) public view returns (bool) {
        return hasRole(RELAYER_ROLE, _who);
    }
}
