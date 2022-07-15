import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';

export const DENOMINATOR = '1000000';
export const RUBIC_PLATFORM_FEE = '30000';
export const FIXED_CRYPTO_FEE = BigNumber.from(ethers.utils.parseEther('1'));
export const MIN_TOKEN_AMOUNT = BigNumber.from('1' + '0'.repeat(17));
export const MAX_TOKEN_AMOUNT = BigNumber.from(ethers.utils.parseEther('10'));
export const DEFAULT_AMOUNT_IN = BigNumber.from(ethers.utils.parseEther('1'));
