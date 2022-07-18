import { OnlySourceFunctionality, WithDestinationFunctionality } from '../../typechain-types';
import { BigNumber, BigNumberish } from 'ethers';
import { DENOMINATOR } from './consts';

export async function calcTokenFees({
    bridge,
    amountWithFee,
    integrator,
    initChainID
}: {
    bridge: OnlySourceFunctionality | WithDestinationFunctionality;
    amountWithFee: BigNumber;
    integrator?: string;
    initChainID?: BigNumberish;
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

        feeAmount = amountWithFee.mul(feeInfo.tokenFee).div(DENOMINATOR);
        RubicFee = feeAmount.mul(feeInfo.RubicTokenShare).div(DENOMINATOR);
        integratorFee = feeAmount.sub(RubicFee);
        amountWithoutFee = amountWithFee.sub(feeAmount);
    } else {
        let fee;
        if (initChainID === undefined) {
            fee = await (<OnlySourceFunctionality>bridge).RubicPlatformFee();
        } else {
            fee = await (<WithDestinationFunctionality>bridge).blockchainToRubicPlatformFee(
                initChainID
            );
        }

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
    bridge: OnlySourceFunctionality | WithDestinationFunctionality;
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

        if (feeInfo.fixedFeeAmount.gt(BigNumber.from('0'))) {
            totalCryptoFee = feeInfo.fixedFeeAmount;

            fixedCryptoFee = totalCryptoFee;
            RubicFixedFee = totalCryptoFee.mul(feeInfo.RubicFixedCryptoShare).div(DENOMINATOR);
            integratorFixedFee = totalCryptoFee.sub(RubicFixedFee);
        } else {
            totalCryptoFee = await bridge.fixedCryptoFee();

            RubicFixedFee = totalCryptoFee;
        }
    } else {
        totalCryptoFee = await bridge.fixedCryptoFee();

        RubicFixedFee = totalCryptoFee;
    }

    if (dstChainID !== undefined) {
        gasFee = await (<WithDestinationFunctionality>bridge).blockchainToGasFee(dstChainID);

        totalCryptoFee += gasFee;
    }

    return { totalCryptoFee, fixedCryptoFee, RubicFixedFee, integratorFixedFee, gasFee };
}
