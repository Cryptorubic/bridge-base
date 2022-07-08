pragma solidity ^0.8.0;

import '../BridgeBase.sol';

contract OnlySourceFunctionality is BridgeBase {
    uint256 public RubicPlatformFee;

    function _OnlySourceFunctionalityInit(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        uint256 _RubicPlatformFee
    ) internal onlyInitializing {
        __BridgeBaseInit(_fixedCryptoFee, _routers);

        require(_RubicPlatformFee <= DENOMINATOR, 'OSF: Rubic Fee too high');

        _RubicPlatformFee = RubicPlatformFee;
    }

    function _calculateFee(
        address _integrator,
        uint256 _amountWithFee,
        uint256
    ) internal override returns (uint256 _totalFee, uint256 _RubicFee) {
        if (_integrator != address(0)) {
            (_totalFee, _RubicFee) = _calculateFeeWithIntegrator(_amountWithFee, _integrator);
        } else {
            _totalFee = FullMath.mulDiv(_amountWithFee, RubicPlatformFee, DENOMINATOR);

            _RubicFee = _totalFee;
        }
    }
}
