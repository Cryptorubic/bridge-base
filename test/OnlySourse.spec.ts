import { ethers, waffle } from 'hardhat';
import { Wallet } from '@ethersproject/wallet';
import { TestOnlySource, TestERC20, TestDEX } from '../typechain-types';
import { assert, expect } from 'chai';
import { BigNumber as BN, ContractTransaction } from 'ethers';
import * as consts from './shared/consts';
import { onlySourceFixture } from './shared/fixtures';
import { calcFees } from './shared/utils';
import { FIXED_CRYPTO_FEE } from './shared/consts';

const createFixtureLoader = waffle.createFixtureLoader;

describe('TestOnlySource', () => {
    let owner: Wallet, swapper: Wallet, integratorWallet: Wallet, manager: Wallet;
    let bridge: TestOnlySource;
    let transitToken: TestERC20;
    let swapToken: TestERC20;
    let DEX: TestDEX;

    let loadFixture: ReturnType<typeof createFixtureLoader>;

    async function callBridge({
        srcInputToken = swapToken.address,
        dstOutputToken = transitToken.address,
        integrator = ethers.constants.AddressZero,
        recipient = owner.address,
        srcInputAmount = consts.DEFAULT_AMOUNT_IN,
        dstMinOutputAmount = consts.MIN_TOKEN_AMOUNT,
        dstChainID = 228,
        router = DEX.address
    } = {}): Promise<ContractTransaction> {
        return bridge.crossChainWithSwap(
            {
                srcInputToken,
                dstOutputToken,
                integrator,
                recipient,
                srcInputAmount,
                dstMinOutputAmount,
                dstChainID
            },
            router
        );
    }

    before('initialize', async () => {
        [owner, swapper, integratorWallet, manager] = await (ethers as any).getSigners();
        loadFixture = createFixtureLoader();
    });

    beforeEach('deploy proxy', async () => {
        ({ bridge, transitToken, swapToken, DEX } = await loadFixture(onlySourceFixture));
    });

    describe('right settings', () => {
        it('routers', async () => {
            const routers = await bridge.getAvailableRouters();
            expect(routers).to.deep.eq([DEX.address]);
        });
        it('min max amounts', async () => {
            expect(await bridge.minTokenAmount(transitToken.address)).to.be.eq(
                consts.MIN_TOKEN_AMOUNT
            );
            expect(await bridge.minTokenAmount(swapToken.address)).to.be.eq(
                consts.MIN_TOKEN_AMOUNT
            );

            expect(await bridge.maxTokenAmount(transitToken.address)).to.be.eq(
                consts.MAX_TOKEN_AMOUNT
            );
            expect(await bridge.maxTokenAmount(swapToken.address)).to.be.eq(
                consts.MAX_TOKEN_AMOUNT
            );
        });
        it('fixed crypto fee', async () => {
            expect(await bridge.fixedCryptoFee()).to.be.eq(consts.FIXED_CRYPTO_FEE);
        });
    });

    describe('check setters', async () => {
        beforeEach('grant roles', async () => {
            await bridge.grantRole(await bridge.MANAGER_ROLE(), manager.address);
        });

        it('only manager can set integrator fee info', async () => {
            const feeInfo = {
                isIntegrator: true,
                tokenFee: 0,
                fixedCryptoShare: 0,
                RubicTokenShare: 0
            };

            await expect(
                bridge.connect(swapper).setIntegratorInfo(integratorWallet.address, feeInfo)
            ).to.be.revertedWith('NotAManager()');

            await bridge.setIntegratorInfo(integratorWallet.address, feeInfo);
            const {
                isIntegrator,
                tokenFee,
                fixedCryptoShare,
                RubicTokenShare
            }: {
                isIntegrator: boolean;
                tokenFee: number;
                fixedCryptoShare: number;
                RubicTokenShare: number;
            } = await bridge.integratorToFeeInfo(integratorWallet.address);
            expect({ isIntegrator, tokenFee, fixedCryptoShare, RubicTokenShare }).to.deep.eq(
                feeInfo
            );
        });
        it('only manager can set min token amounts', async () => {
            await expect(
                bridge
                    .connect(swapper)
                    .setMinTokenAmount(swapToken.address, consts.MIN_TOKEN_AMOUNT.add('1'))
            ).to.be.revertedWith('NotAManager');

            await bridge.setMinTokenAmount(swapToken.address, consts.MIN_TOKEN_AMOUNT.add('1'));
            expect(await bridge.minTokenAmount(swapToken.address)).to.be.eq(
                consts.MIN_TOKEN_AMOUNT.add('1')
            );
        });
        it('only manager can set max token amounts', async () => {
            await expect(
                bridge
                    .connect(swapper)
                    .setMaxTokenAmount(swapToken.address, consts.MAX_TOKEN_AMOUNT.add('1'))
            ).to.be.revertedWith('NotAManager');

            await bridge.setMaxTokenAmount(swapToken.address, consts.MAX_TOKEN_AMOUNT.add('1'));
            expect(await bridge.maxTokenAmount(swapToken.address)).to.be.eq(
                consts.MAX_TOKEN_AMOUNT.add('1')
            );
        });
        it('cannot set min token amount greater than max', async () => {
            const currentMax = await bridge.maxTokenAmount(swapToken.address);
            await expect(
                bridge.setMinTokenAmount(swapToken.address, currentMax.add('1'))
            ).to.be.revertedWith('MinMustBeLowerThanMax()');
        });
        it('cannot set max token amount less than min', async () => {
            const currentMin = await bridge.minTokenAmount(swapToken.address);
            await expect(
                bridge.setMaxTokenAmount(swapToken.address, currentMin.sub('1'))
            ).to.be.revertedWith('MaxMustBeBiggerThanMin()');
        });
        it('only manager can set fixed crypto fee', async () => {
            await expect(bridge.connect(swapper).setFixedCryptoFee('100')).to.be.revertedWith(
                'NotAManager()'
            );

            await bridge.setFixedCryptoFee('100');
            expect(await bridge.fixedCryptoFee()).to.be.eq('100');
        });
        it('only manager can remove routers', async () => {
            await expect(
                bridge.connect(swapper).removeAvailableRouter(DEX.address)
            ).to.be.revertedWith('NotAManager()');

            await bridge.removeAvailableRouter(DEX.address);
            expect(await bridge.getAvailableRouters()).to.be.deep.eq([]);
        });
        it('only manager can add routers', async () => {
            await expect(
                bridge.connect(swapper).addAvailableRouter(owner.address)
            ).to.be.revertedWith('NotAManager()');

            await bridge.addAvailableRouter(owner.address);

            expect(await bridge.getAvailableRouters()).to.be.deep.eq([DEX.address, owner.address]);
        });
    });

    describe.only('cross chain tests', () => {
        beforeEach('setup before swaps', async () => {
            bridge = bridge.connect(swapper);

            await swapToken.transfer(swapper.address, ethers.utils.parseEther('10'));
            await swapToken.connect(swapper).approve(bridge.address, ethers.constants.MaxUint256);
        });
        it('cross chain with swap fails if router not available', async () => {
            await expect(callBridge({ router: owner.address })).to.be.revertedWith(
                'TestBridge: no such router'
            );
        });
        it('cross chain with swap amounts without integrator', async () => {
            await callBridge();
            const { feeAmount, amountWithoutFee, RubicFee } = await calcFees({
                bridge,
                amountWithFee: consts.DEFAULT_AMOUNT_IN
            });
            expect(await transitToken.balanceOf(bridge.address)).to.be.eq(
                amountWithoutFee.mul(await DEX.price()),
                'wrong amount of transit token on the bridge'
            );
            expect(await swapToken.balanceOf(bridge.address)).to.be.eq(
                feeAmount,
                'wrong amount of swapped token on the contract as fees'
            );
            expect(await bridge.availableRubicFee(swapToken.address)).to.be.eq(
                RubicFee,
                'wrong Rubic fees collected'
            );
        });
        it('cross chain with swap amounts with integrator', async () => {
            await bridge.connect(owner).setIntegratorInfo(integratorWallet.address, {
                isIntegrator: true,
                tokenFee: '60000', // 6%
                fixedCryptoShare: '0',
                RubicTokenShare: '400000' // 40%
            });

            await callBridge({ integrator: integratorWallet.address });
            const { feeAmount, amountWithoutFee, integratorFee, RubicFee } = await calcFees({
                bridge,
                amountWithFee: consts.DEFAULT_AMOUNT_IN,
                integrator: integratorWallet.address
            });
            expect(await transitToken.balanceOf(bridge.address)).to.be.eq(
                amountWithoutFee.mul(await DEX.price()),
                'wrong amount of transit token on the bridge'
            );
            expect(await swapToken.balanceOf(bridge.address)).to.be.eq(
                feeAmount,
                'wrong amount of swapped token on the contract as fees'
            );
            expect(await bridge.availableRubicFee(swapToken.address)).to.be.eq(
                RubicFee,
                'wrong Rubic fees collected'
            );
            expect(
                await bridge.availableIntegratorFee(swapToken.address, integratorWallet.address)
            ).to.be.eq(integratorFee, 'wrong integrator fees collected');
        });
        it('check fixed crypto fee without integrator', async () => {
            await callBridge();

            expect(await waffle.provider.getBalance(bridge.address)).to.be.eq(
                consts.FIXED_CRYPTO_FEE
            );
        });
    });
});
