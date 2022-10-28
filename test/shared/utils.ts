import {
    OnlySourceFunctionality,
    WithDestinationFunctionality,
    BridgeBase
} from '../../typechain-types';
import { BigNumber, BigNumberish } from 'ethers';
import { DENOMINATOR } from './consts';

export async function calcTokenFees({
    bridge,
    amountWithFee,
    integrator
}: {
    bridge: BridgeBase;
    amountWithFee: BigNumber;
    integrator?: string;
}): Promise<{
    amountWithoutFee: BigNumber;
    feeAmount: BigNumber;
    RubicFee: BigNumber;
    integratorFee: BigNumber;
}> {
    let feeAmount;
    let RubicFee;
    let integratorFee;
    let amountWithoutFee;

    if (integrator !== undefined) {
        const feeInfo = await bridge.integratorToFeeInfo(integrator);
        if (feeInfo.isIntegrator) {
            feeAmount = amountWithFee.mul(feeInfo.tokenFee).div(DENOMINATOR);
            RubicFee = feeAmount.mul(feeInfo.RubicTokenShare).div(DENOMINATOR);
            integratorFee = feeAmount.sub(RubicFee);
            amountWithoutFee = amountWithFee.sub(feeAmount);
        } else {
            console.log('WARNING: integrator is not active');

            const fee = await bridge.RubicPlatformFee();

            feeAmount = amountWithFee.mul(fee).div(DENOMINATOR);
            RubicFee = feeAmount;
            amountWithoutFee = amountWithFee.sub(feeAmount);
        }
    } else {
        const fee = await bridge.RubicPlatformFee();

        feeAmount = amountWithFee.mul(fee).div(DENOMINATOR);
        RubicFee = feeAmount;
        amountWithoutFee = amountWithFee.sub(feeAmount);
    }

    //console.log(feeAmount, RubicFee, integratorFee, amountWithoutFee)

    return { feeAmount, RubicFee, integratorFee, amountWithoutFee };
}

export async function calcCryptoFees({
    bridge,
    integrator,
    dstChainID
}: {
    bridge: BridgeBase | OnlySourceFunctionality | WithDestinationFunctionality;
    integrator?: string;
    dstChainID?: BigNumberish;
}): Promise<{
    totalCryptoFee: BigNumber;
    fixedCryptoFee: BigNumber;
    RubicFixedFee: BigNumber;
    integratorFixedFee: BigNumber;
    gasFee: BigNumber;
}> {
    let totalCryptoFee;
    let fixedCryptoFee;
    let RubicFixedFee;
    let integratorFixedFee;
    let gasFee;

    if (integrator !== undefined) {
        const feeInfo = await bridge.integratorToFeeInfo(integrator);
        if (feeInfo.isIntegrator) {
            totalCryptoFee = feeInfo.fixedFeeAmount;
            fixedCryptoFee = totalCryptoFee;

            RubicFixedFee = totalCryptoFee.mul(feeInfo.RubicFixedCryptoShare).div(DENOMINATOR);
            integratorFixedFee = totalCryptoFee.sub(RubicFixedFee);
        } else {
            console.log('WARNING: integrator is not active');

            totalCryptoFee = await bridge.fixedCryptoFee();

            RubicFixedFee = totalCryptoFee;
        }
    } else {
        totalCryptoFee = await bridge.fixedCryptoFee();

        RubicFixedFee = totalCryptoFee;
    }

    if (dstChainID !== undefined) {
        gasFee = await (<WithDestinationFunctionality>bridge).blockchainToGasFee(dstChainID);

        totalCryptoFee = totalCryptoFee.add(gasFee);
    }

    return { totalCryptoFee, fixedCryptoFee, RubicFixedFee, integratorFixedFee, gasFee };
}
