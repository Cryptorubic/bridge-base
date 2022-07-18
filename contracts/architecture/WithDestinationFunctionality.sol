// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

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
        if (!hasRole(RELAYER_ROLE, msg.sender)) {
            revert NotARelayer();
        }
        _;
    }

    function __WithDestinationFunctionalityInit(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256[] memory _blockchainIDs,
        uint256[] memory _blockchainToGasFee,
        uint256[] memory _blockchainToRubicPlatformFee
    ) internal onlyInitializing {
        __BridgeBaseInit(
            _fixedCryptoFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts
        );

        if (_blockchainToGasFee.length != _blockchainToRubicPlatformFee.length) {
            revert LengthMismatch();
        }

        for (uint256 i; i < _blockchainToGasFee.length; i++) {
            blockchainToGasFee[_blockchainIDs[i]] = _blockchainToGasFee[i];
            blockchainToRubicPlatformFee[_blockchainIDs[i]] = _blockchainToRubicPlatformFee[i];
        }
    }

    function accrueFixedAndGasFees(
        address _integrator,
        IntegratorFeeInfo memory _info,
        uint256 _blockchainID
    ) internal returns (uint256 _totalCryptoFee) {
        _totalCryptoFee = accrueFixedCryptoFee(_integrator, _info);
        uint256 _gasFee = blockchainToGasFee[_blockchainID];
        _totalCryptoFee += _gasFee;
        collectedGasFee += _gasFee;
    }

    function _calculateFee(
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256 initBlockchainNum
    ) internal view virtual override returns (uint256 _totalFee, uint256 _RubicFee) {
        if (_info.isIntegrator) {
            (_totalFee, _RubicFee) = _calculateFeeWithIntegrator(_amountWithFee, _info);
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

    function collectGasFee(address _to) external onlyManagerAndAdmin {
        uint256 _gasFee = collectedGasFee;
        collectedGasFee = 0;
        sendToken(address(0), _gasFee, _to);
    }

    /// TX STATUSES MANAGEMENT ///

    /**
     * @dev Function changes values associated with certain originalTxHash
     * @param _id ID of the transaction to change
     * @param _statusCode Associated status
     */
    function changeTxStatus(bytes32 _id, SwapStatus _statusCode) external onlyRelayer {
        if (_statusCode == SwapStatus.Null) {
            revert CantSetToNull();
        }
        if (processedTransactions[_id] == SwapStatus.Succeeded || processedTransactions[_id] == SwapStatus.Fallback) {
            revert Unchangeable();
        }

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
