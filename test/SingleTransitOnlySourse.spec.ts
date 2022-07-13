import { ethers, waffle, network } from 'hardhat';
import { Wallet } from '@ethersproject/wallet';
import { SingleTransitOnlySource, TestERC20 } from '../typechain-types';
import { assert, expect } from 'chai';
import { BigNumber as BN } from 'ethers';
import * as consts from './shared/consts';
import { singleTransitOnlySourceFixture } from './shared/fixtures';

const createFixtureLoader = waffle.createFixtureLoader;

describe('RubicLiFiProxy', () => {
    let owner: Wallet, swapper: Wallet, integrator: Wallet;
    let bridge: SingleTransitOnlySource;
    let transitToken: TestERC20;
    let swapToken: TestERC20;

    let loadFixture: ReturnType<typeof createFixtureLoader>;

    before('initialize', async () => {
        [owner, swapper, integrator] = await (ethers as any).getSigners();
        loadFixture = createFixtureLoader();
    });

    beforeEach('deploy proxy', async () => {
        ({ bridge, transitToken, swapToken } = await loadFixture(singleTransitOnlySourceFixture));
    });

    describe('SingleTransitOnlySource', () => {

    });
});
