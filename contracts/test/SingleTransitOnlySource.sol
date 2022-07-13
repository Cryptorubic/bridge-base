pragma solidity ^0.8.0;

import '../tokens/SingleTransitToken.sol';
import '../architecture/OnlySourceFunctionality.sol';

import { ITestDEX } from './TestDEX.sol';

contract SingleTransitOnlySource is SingleTransitToken, OnlySourceFunctionality {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    constructor(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address _transitToken,
        uint256 _minTokenAmount,
        uint256 _maxTokenAmount,
        uint256 _RubicPlatformFee
    ) {
        initialize(
            _fixedCryptoFee,
            _routers,
            _transitToken,
            _minTokenAmount,
            _maxTokenAmount,
            _RubicPlatformFee
        );
    }

    function initialize(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address _transitToken,
        uint256 _minTokenAmount,
        uint256 _maxTokenAmount,
        uint256 _RubicPlatformFee
    ) private initializer {
        __BridgeBaseInit(_fixedCryptoFee, _routers);
        __SingleTransitTokenInitUnchained(_routers, _transitToken, _minTokenAmount, _maxTokenAmount);
        __OnlySourceFunctionalityInitUnchained(_RubicPlatformFee);
    }

    function crossChainWithSwap(
        BaseCrossChainParams calldata _params,
        address _router
    ) external payable nonReentrant whenNotPaused EventEmitter(_params) {
        require(availableRouters.contains(_router), 'TestBridge: no such router');
        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        accrueFixedCryptoFee(_params.integrator, _info);

        uint256 _amountIn = accrueTokenFees(_params.integrator, _info, _params.srcInputAmount, 0);

        smartApprove(_params.srcInputToken, _amountIn, _router);

        ITestDEX(_router).swap(
            _params.srcInputToken,
            _amountIn,
            _params.dstOutputToken
        );
    }

    function _calculateFee(
        IntegratorFeeInfo memory _info,
        uint256 _amountWithFee,
        uint256 _initBlockchainNum
    ) internal override(BridgeBase, OnlySourceFunctionality) view returns (uint256 _totalFee, uint256 _RubicFee) {
        (_totalFee, _RubicFee) = OnlySourceFunctionality._calculateFee(
            _info,
            _amountWithFee,
            _initBlockchainNum
        );
    }
}