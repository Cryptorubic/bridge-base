pragma solidity ^0.8.4;

import '../architecture/OnlySourceFunctionality.sol';
import '../libraries/SmartApprove.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {ITestDEX} from './TestDEX.sol';

contract TestOnlySource is OnlySourceFunctionality {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    constructor(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
    ) {
        initialize(_fixedCryptoFee, _routers, _tokens, _minTokenAmounts, _maxTokenAmounts, _RubicPlatformFee);
    }

    function initialize(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
    ) private initializer {
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _RubicPlatformFee
        );
    }

    function crossChainWithSwap(BaseCrossChainParams calldata _params, address _router)
        external
        payable
        nonReentrant
        whenNotPaused
        EventEmitter(_params)
    {
        require(availableRouters.contains(_router), 'TestBridge: no such router');
        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        IERC20(_params.srcInputToken).transferFrom(msg.sender, address(this), _params.srcInputAmount);

        accrueFixedCryptoFee(_params.integrator, _info);

        uint256 _amountIn = accrueTokenFees(
            _params.integrator,
            _info,
            _params.srcInputAmount,
            0,
            _params.srcInputToken
        );

        SmartApprove.smartApprove(_params.srcInputToken, _amountIn, _router);

        ITestDEX(_router).swap(_params.srcInputToken, _amountIn, _params.dstOutputToken);
    }

    //    function _calculateFee(
    //        IntegratorFeeInfo memory _info,
    //        uint256 _amountWithFee,
    //        uint256 _initBlockchainNum
    //    ) internal override(BridgeBase, OnlySourceFunctionality) view returns (uint256 _totalFee, uint256 _RubicFee) {
    //        (_totalFee, _RubicFee) = OnlySourceFunctionality._calculateFee(
    //            _info,
    //            _amountWithFee,
    //            _initBlockchainNum
    //        );
    //    }
}
