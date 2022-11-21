import { TestOnlySource, TestDEX, TestERC20 } from '../../typechain-types';
import { ethers } from 'hardhat';
import { RUBIC_PLATFORM_FEE, MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT, FIXED_CRYPTO_FEE } from './consts';

// const envConfig = require('dotenv').config();
// const {
//     TRANSIT_POLYGON: TEST_TRANSIT,
//     SWAP_TOKEN_POLYGON: TEST_SWAP,
//     LIFI
// } = envConfig.parsed || {};

type Bridge = TestOnlySource;

interface BridgeFixture {
    bridge: Bridge;
    transitToken: TestERC20;
    swapToken: TestERC20;
    DEX: TestDEX;
}

const bridgeFixture = async function (): Promise<{
    transitToken: TestERC20;
    swapToken: TestERC20;
    DEX: TestDEX;
}> {
    const tokenFactory = await ethers.getContractFactory('TestERC20');
    const transitToken = (await tokenFactory.deploy()) as TestERC20;
    const swapToken = (await tokenFactory.deploy()) as TestERC20;

    const DEXFactory = await ethers.getContractFactory('TestDEX');
    const DEX = (await DEXFactory.deploy()) as TestDEX;

    await transitToken.transfer(DEX.address, ethers.utils.parseEther('100'));
    return { transitToken, swapToken, DEX };
};

export const onlySourceFixture = async function (): Promise<BridgeFixture> {
    const { transitToken, swapToken, DEX } = await bridgeFixture();
    const bridgeFactory = await ethers.getContractFactory('TestOnlySource');
    const bridge = (await bridgeFactory.deploy(
        FIXED_CRYPTO_FEE,
        RUBIC_PLATFORM_FEE,
        [DEX.address],
        [transitToken.address, swapToken.address],
        [MIN_TOKEN_AMOUNT, MIN_TOKEN_AMOUNT],
        [MAX_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT]
    )) as Bridge;

    return { bridge, transitToken, swapToken, DEX };
};
