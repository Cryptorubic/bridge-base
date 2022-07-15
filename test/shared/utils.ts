import { OnlySourceFunctionality, WithDestinationFunctionality } from '../../typechain-types';
import { BigNumber, BigNumberish } from 'ethers';
import { DENOMINATOR } from './consts';

export async function calcFees({
    bridge,
    amountWithFee,
    integrator,
    initBlockchainNum
}: {
    bridge: OnlySourceFunctionality | WithDestinationFunctionality;
    amountWithFee: BigNumber;
    integrator?: string;
    initBlockchainNum?: BigNumberish;
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
        if (initBlockchainNum === undefined) {
            fee = await (<OnlySourceFunctionality>bridge).RubicPlatformFee();
        } else {
            fee = await (<WithDestinationFunctionality>bridge).blockchainToRubicPlatformFee(
                initBlockchainNum
            );
        }

        feeAmount = amountWithFee.mul(fee).div(DENOMINATOR);
        RubicFee = feeAmount;
        amountWithoutFee = amountWithFee.sub(feeAmount);
    }

    //console.log(feeAmount, RubicFee, integratorFee, amountWithoutFee)

    return { feeAmount, RubicFee, integratorFee, amountWithoutFee };
}
