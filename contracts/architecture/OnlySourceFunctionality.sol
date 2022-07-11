pragma solidity ^0.8.0;

import '../BridgeBase.sol';

contract OnlySourceFunctionality is BridgeBase {
    uint256 public RubicPlatformFee;

    function __OnlySourceFunctionalityInitUnchained(
        uint256 _RubicPlatformFee
    ) internal onlyInitializing {
        require(_RubicPlatformFee <= DENOMINATOR, 'OSF: Rubic Fee too high');

        RubicPlatformFee = _RubicPlatformFee;
    }

    function _calculateFee(
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256
    ) internal override virtual view returns (uint256 _totalFee, uint256 _RubicFee) {
        if (_info.isIntegrator) {
            (_totalFee, _RubicFee) = _calculateFeeWithIntegrator(_amountWithFee, _info);
        } else {
            _totalFee = FullMath.mulDiv(_amountWithFee, RubicPlatformFee, DENOMINATOR);

            _RubicFee = _totalFee;
        }
    }
}
