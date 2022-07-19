// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '../BridgeBase.sol';

contract OnlySourceFunctionality is BridgeBase {
    uint256 public RubicPlatformFee;

    event RequestSent(BaseCrossChainParams parameters);

    modifier eventEmitter(BaseCrossChainParams calldata _params) {
        _;
        emit RequestSent(_params);
    }

    function __OnlySourceFunctionalityInit(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
    ) internal onlyInitializing {
        __BridgeBaseInit(_fixedCryptoFee, _routers, _tokens, _minTokenAmounts, _maxTokenAmounts);

        if (_RubicPlatformFee > DENOMINATOR) {
            revert FeeTooHigh();
        }

        RubicPlatformFee = _RubicPlatformFee;
    }

    function _calculateFee(
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256
    ) internal view virtual override returns (uint256 _totalFee, uint256 _RubicFee) {
        if (_info.isIntegrator) {
            (_totalFee, _RubicFee) = _calculateFeeWithIntegrator(_amountWithFee, _info);
        } else {
            _totalFee = FullMath.mulDiv(_amountWithFee, RubicPlatformFee, DENOMINATOR);

            _RubicFee = _totalFee;
        }
    }
}
