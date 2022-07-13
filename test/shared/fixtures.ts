import { SingleTransitOnlySource, TestERC20 } from '../../typechain-types';
import { Fixture } from 'ethereum-waffle';
import { ethers } from 'hardhat';
import { RUBIC_PLATFORM_FEE } from './consts';

// const envConfig = require('dotenv').config();
// const {
//     TRANSIT_POLYGON: TEST_TRANSIT,
//     SWAP_TOKEN_POLYGON: TEST_SWAP,
//     LIFI
// } = envConfig.parsed || {};

type Bridge = SingleTransitOnlySource;

interface BridgeFixture {
    bridge: Bridge;
    transitToken: TestERC20;
    swapToken: TestERC20;
}

const bridgeFixture = async function (): Promise<{
    transitToken: TestERC20;
    swapToken: TestERC20;
}> {
    const tokenFactory = await ethers.getContractFactory('TestERC20');
    const transitToken = (await tokenFactory.deploy()) as TestERC20;
    const swapToken = (await tokenFactory.deploy()) as TestERC20;

    return { transitToken, swapToken };
};

export const singleTransitOnlySourceFixture: Fixture<BridgeFixture> =
    async function (): Promise<BridgeFixture> {
        const bridgeFactory = await ethers.getContractFactory('SingleTransitOnlySource');
        const bridge = (await bridgeFactory.deploy(
            0,
            [],
            [],
            [],
            [],
            RUBIC_PLATFORM_FEE
        )) as Bridge;

        const { transitToken, swapToken } = await bridgeFixture();

        return { bridge, transitToken, swapToken };
    };
