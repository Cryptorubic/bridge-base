import { ethers } from 'hardhat';
import { Wallet } from '@ethersproject/wallet';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { TestOnlySource, TestERC20, TestDEX, BridgeBase } from '../typechain-types';
import { BigNumber as BN, ContractTransaction } from 'ethers';
import * as consts from './shared/consts';
import { onlySourceFixture } from './shared/fixtures';
import { calcCryptoFees, calcTokenFees } from './shared/utils';
import { balance } from '@openzeppelin/test-helpers';
import { DEFAULT_PROVIDER_NAME } from './shared/consts';
import { expect } from 'chai';

describe('TestOnlySource', () => {
    let owner: Wallet, swapper: Wallet, integratorWallet: Wallet, manager: Wallet;
    let bridge: TestOnlySource;
    let transitToken: TestERC20;
    let swapToken: TestERC20;
    let DEX: TestDEX;

    async function callBridge(
        {
            srcInputToken = swapToken.address,
            dstOutputToken = transitToken.address,
            integrator = ethers.constants.AddressZero,
            recipient = owner.address,
            srcInputAmount = consts.DEFAULT_AMOUNT_IN,
            dstMinOutputAmount = consts.MIN_TOKEN_AMOUNT,
            dstChainID = 228,
            router = DEX.address
        } = {},
        value?: BN
    ): Promise<ContractTransaction> {
        if (value === undefined) {
            value = (
                await calcCryptoFees({
                    bridge,
                    integrator: integrator === ethers.constants.AddressZero ? undefined : integrator
                })
            ).totalCryptoFee;
        }

        return bridge.crossChainWithSwap(
            {
                srcInputToken,
                dstOutputToken,
                integrator,
                recipient,
                srcInputAmount,
                dstMinOutputAmount,
                dstChainID,
                router
            },
            DEFAULT_PROVIDER_NAME,
            { value: value }
        );
    }

    before('initialize', async () => {
        [owner, swapper, integratorWallet, manager] = await (ethers as any).getSigners();
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
                RubicFixedCryptoShare: 0,
                RubicTokenShare: 0,
                fixedFeeAmount: BN.from(0)
            };

            await expect(
                bridge.connect(swapper).setIntegratorInfo(integratorWallet.address, feeInfo)
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

            await bridge.setIntegratorInfo(integratorWallet.address, feeInfo);
            const {
                isIntegrator,
                tokenFee,
                RubicFixedCryptoShare,
                RubicTokenShare,
                fixedFeeAmount
            }: {
                isIntegrator: boolean;
                tokenFee: number;
                RubicFixedCryptoShare: number;
                RubicTokenShare: number;
                fixedFeeAmount: BN;
            } = await bridge.integratorToFeeInfo(integratorWallet.address);
            expect({
                isIntegrator,
                tokenFee,
                RubicFixedCryptoShare,
                RubicTokenShare,
                fixedFeeAmount
            }).to.deep.eq(feeInfo);
        });
        it('only manager can set min token amounts', async () => {
            await expect(
                bridge
                    .connect(swapper)
                    .setMinTokenAmount(swapToken.address, consts.MIN_TOKEN_AMOUNT.add('1'))
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

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
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

            await bridge.setMaxTokenAmount(swapToken.address, consts.MAX_TOKEN_AMOUNT.add('1'));
            expect(await bridge.maxTokenAmount(swapToken.address)).to.be.eq(
                consts.MAX_TOKEN_AMOUNT.add('1')
            );
        });
        it('manager cannot set Rubic fee higher than the limit', async () => {
            await expect(
                bridge.connect(manager).setRubicPlatformFee(500000)
            ).to.be.revertedWithCustomError(bridge, 'FeeTooHigh');

            await bridge.connect(manager).setRubicPlatformFee(249000);
            expect(await bridge.RubicPlatformFee()).to.be.eq(249000);
        });
        it('only admin can set fee limit', async () => {
            await expect(
                bridge.connect(manager).setMaxRubicPlatformFee(500000)
            ).to.be.revertedWithCustomError(bridge, 'NotAnAdmin');

            await bridge.setMaxRubicPlatformFee(510000);

            await bridge.connect(manager).setRubicPlatformFee(500000);

            expect(await bridge.RubicPlatformFee()).to.be.eq(500000);
        });
        it('cannot set min token amount greater than max', async () => {
            const currentMax = await bridge.maxTokenAmount(swapToken.address);
            await expect(
                bridge.setMinTokenAmount(swapToken.address, currentMax.add('1'))
            ).to.be.revertedWithCustomError(bridge, 'MinMustBeLowerThanMax');
        });
        it('cannot set max token amount less than min', async () => {
            const currentMin = await bridge.minTokenAmount(swapToken.address);
            await expect(
                bridge.setMaxTokenAmount(swapToken.address, currentMin.sub('1'))
            ).to.be.revertedWithCustomError(bridge, 'MaxMustBeBiggerThanMin');
        });
        it('only manager can set fixed crypto fee', async () => {
            await expect(
                bridge.connect(swapper).setFixedCryptoFee('100')
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

            await bridge.setFixedCryptoFee('100');
            expect(await bridge.fixedCryptoFee()).to.be.eq('100');
        });
        it('only manager can remove routers', async () => {
            await expect(
                bridge.connect(swapper).removeAvailableRouters([DEX.address])
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

            await bridge.removeAvailableRouters([DEX.address]);
            expect(await bridge.getAvailableRouters()).to.be.deep.eq([]);
        });
        it('only manager can add routers', async () => {
            await expect(
                bridge.connect(swapper).addAvailableRouters([owner.address])
            ).to.be.revertedWithCustomError(bridge, 'NotAManager');

            await bridge.addAvailableRouters([owner.address]);

            expect(await bridge.getAvailableRouters()).to.be.deep.eq([DEX.address, owner.address]);
        });
        it('possible to add multiple routers', async () => {
            await bridge.addAvailableRouters([swapper.address, owner.address]);
            expect(await bridge.getAvailableRouters()).to.be.deep.eq([
                DEX.address,
                swapper.address,
                owner.address
            ]);
        });
        it('possible to remove multiple routers', async () => {
            await bridge.addAvailableRouters([swapper.address, owner.address]);
            await bridge.removeAvailableRouters([DEX.address, owner.address]);
            expect(await bridge.getAvailableRouters()).to.be.deep.eq([swapper.address]);
        });
        it('validation of integratorFeeInfo', async () => {
            let feeInfo = {
                isIntegrator: true,
                tokenFee: consts.DENOMINATOR.add('1'),
                RubicFixedCryptoShare: BN.from(0),
                RubicTokenShare: BN.from(0),
                fixedFeeAmount: BN.from(0)
            };

            await expect(
                bridge.setIntegratorInfo(integratorWallet.address, feeInfo)
            ).to.be.revertedWithCustomError(bridge, 'FeeTooHigh');

            feeInfo = {
                isIntegrator: true,
                tokenFee: consts.DENOMINATOR,
                RubicFixedCryptoShare: consts.DENOMINATOR.add('1'),
                RubicTokenShare: consts.DENOMINATOR,
                fixedFeeAmount: BN.from(0)
            };

            await expect(
                bridge.setIntegratorInfo(integratorWallet.address, feeInfo)
            ).to.be.revertedWithCustomError(bridge, 'ShareTooHigh');

            feeInfo = {
                isIntegrator: true,
                tokenFee: consts.DENOMINATOR,
                RubicFixedCryptoShare: consts.DENOMINATOR,
                RubicTokenShare: consts.DENOMINATOR.add('1'),
                fixedFeeAmount: BN.from(0)
            };

            await expect(
                bridge.setIntegratorInfo(integratorWallet.address, feeInfo)
            ).to.be.revertedWithCustomError(bridge, 'ShareTooHigh');
        });
        it('admin transfer and accept', async () => {
            await expect(bridge.transferAdmin(swapper.address))
                .to.emit(bridge, 'InitAdminTransfer')
                .withArgs(owner.address, swapper.address);

            await expect(bridge.connect(swapper).acceptAdmin())
                .to.emit(bridge, 'AcceptAdmin')
                .withArgs(owner.address, swapper.address);

            // eslint-disable-next-line @typescript-eslint/no-unused-expressions
            expect(await bridge.hasRole(await bridge.DEFAULT_ADMIN_ROLE(), owner.address)).to.be
                .false;

            // eslint-disable-next-line @typescript-eslint/no-unused-expressions
            expect(await bridge.hasRole(await bridge.DEFAULT_ADMIN_ROLE(), swapper.address)).to.be
                .true;

            await expect(bridge.transferAdmin(manager.address)).to.be.revertedWithCustomError(
                bridge as BridgeBase,
                'NotAnAdmin'
            );
        });
    });

    describe('cross chain tests', () => {
        beforeEach('setup before swaps', async () => {
            bridge = bridge.connect(swapper);

            await swapToken.transfer(swapper.address, ethers.utils.parseEther('10'));
            await swapToken.connect(swapper).approve(bridge.address, ethers.constants.MaxUint256);
        });
        it('check event', async () => {
            await expect(callBridge())
                .to.emit(bridge, 'RequestSent')
                .withArgs(
                    [
                        swapToken.address,
                        consts.DEFAULT_AMOUNT_IN,
                        228,
                        transitToken.address,
                        consts.MIN_TOKEN_AMOUNT,
                        owner.address,
                        ethers.constants.AddressZero,
                        DEX.address
                    ],
                    DEFAULT_PROVIDER_NAME
                );
        });
        it('cross chain with swap fails if router not available', async () => {
            await expect(callBridge({ router: owner.address }))
                .to.be.revertedWithCustomError(bridge, 'NotInWhitelist')
                .withArgs(owner.address);
        });
        it('cross chain with swap amounts without integrator', async () => {
            await callBridge();
            const { feeAmount, amountWithoutFee, RubicFee } = await calcTokenFees({
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
            expect(await bridge.availableRubicTokenFee(swapToken.address)).to.be.eq(
                RubicFee,
                'wrong Rubic fees collected'
            );
        });
        it('cross chain with swap amounts with integrator', async () => {
            await bridge.connect(owner).setIntegratorInfo(integratorWallet.address, {
                isIntegrator: true,
                tokenFee: '60000', // 6%
                RubicFixedCryptoShare: '0',
                RubicTokenShare: '400000', // 40%,
                fixedFeeAmount: BN.from(0)
            });

            await callBridge({ integrator: integratorWallet.address });
            const { feeAmount, amountWithoutFee, integratorFee, RubicFee } = await calcTokenFees({
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
            expect(await bridge.availableRubicTokenFee(swapToken.address)).to.be.eq(
                RubicFee,
                'wrong Rubic fees collected'
            );
            expect(
                await bridge.availableIntegratorTokenFee(
                    swapToken.address,
                    integratorWallet.address
                )
            ).to.be.eq(integratorFee, 'wrong integrator fees collected');
        });
        it('cross chain with swap amounts with integrator turned off', async () => {
            await bridge.connect(owner).setIntegratorInfo(integratorWallet.address, {
                isIntegrator: false,
                tokenFee: '60000', // 6%
                RubicFixedCryptoShare: '0',
                RubicTokenShare: '400000', // 40%,
                fixedFeeAmount: BN.from(0)
            });

            await callBridge({ integrator: integratorWallet.address });
            const { feeAmount, amountWithoutFee, RubicFee } = await calcTokenFees({
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
            expect(await bridge.availableRubicTokenFee(swapToken.address)).to.be.eq(
                RubicFee,
                'wrong Rubic fees collected'
            );
        });
        it('check fixed crypto fee without integrator', async () => {
            await callBridge();

            expect(await ethers.provider.getBalance(bridge.address)).to.be.eq(
                consts.FIXED_CRYPTO_FEE
            );
            expect(await bridge.availableRubicCryptoFee()).to.be.eq(consts.FIXED_CRYPTO_FEE);
        });
        it('check fixed crypto fee with integrator', async () => {
            await bridge.connect(owner).setIntegratorInfo(integratorWallet.address, {
                isIntegrator: true,
                tokenFee: '60000', // 6%
                RubicFixedCryptoShare: '800000', // 80%
                RubicTokenShare: '400000', // 40%,
                fixedFeeAmount: consts.FIXED_CRYPTO_FEE.add(BN.from('228'))
            });

            const { totalCryptoFee, RubicFixedFee, integratorFixedFee } = await calcCryptoFees({
                bridge,
                integrator: integratorWallet.address
            });

            await callBridge({ integrator: integratorWallet.address });

            expect(await ethers.provider.getBalance(bridge.address)).to.be.eq(totalCryptoFee);
            expect(await bridge.availableIntegratorCryptoFee(integratorWallet.address)).to.be.eq(
                integratorFixedFee
            );
            expect(await bridge.availableRubicCryptoFee()).to.be.eq(RubicFixedFee);
        });
        it('check fixed crypto fee with integrator (fixedCryptoFee = 0)', async () => {
            await bridge.connect(owner).setIntegratorInfo(integratorWallet.address, {
                isIntegrator: true,
                tokenFee: '60000', // 6%
                RubicFixedCryptoShare: '800000', // 80%
                RubicTokenShare: '400000', // 40%,
                fixedFeeAmount: '0'
            });

            await callBridge({ integrator: integratorWallet.address });

            expect(await ethers.provider.getBalance(bridge.address)).to.be.eq(0);
            expect(await bridge.availableIntegratorCryptoFee(integratorWallet.address)).to.be.eq(0);
            expect(await bridge.availableRubicCryptoFee()).to.be.eq(0);
        });
    });

    describe('collect functions', () => {
        const tokenFee = BN.from('60000'); // 6%
        const RubicFixedCryptoShare = BN.from('800000'); // 80%
        const RubicTokenShare = BN.from('400000'); // 40%
        const fixedFeeAmount = consts.FIXED_CRYPTO_FEE.add(BN.from('228'));

        let integratorFee;
        let RubicFee;
        let integratorFixedFee;
        let RubicFixedFee;

        beforeEach('setup before collects', async () => {
            await bridge.grantRole(await bridge.MANAGER_ROLE(), manager.address);

            await swapToken.transfer(swapper.address, ethers.utils.parseEther('10'));
            await swapToken.connect(swapper).approve(bridge.address, ethers.constants.MaxUint256);

            await bridge.setIntegratorInfo(integratorWallet.address, {
                isIntegrator: true,
                tokenFee,
                RubicFixedCryptoShare,
                RubicTokenShare,
                fixedFeeAmount
            });

            bridge = bridge.connect(swapper);

            ({ integratorFee, RubicFee } = await calcTokenFees({
                bridge,
                amountWithFee: consts.DEFAULT_AMOUNT_IN,
                integrator: integratorWallet.address
            }));

            ({ integratorFixedFee, RubicFixedFee } = await calcCryptoFees({
                bridge,
                integrator: integratorWallet.address
            }));

            await callBridge({ integrator: integratorWallet.address });

            bridge = bridge.connect(manager);
        });

        it('collect integrator token fee by integrator', async () => {
            await bridge
                .connect(integratorWallet)
                ['collectIntegratorFee(address)'](swapToken.address);

            expect(await swapToken.balanceOf(integratorWallet.address)).to.be.eq(integratorFee);
        });
        it('collect integrator token fee by manager', async () => {
            await bridge['collectIntegratorFee(address,address)'](
                integratorWallet.address,
                swapToken.address
            );

            expect(await swapToken.balanceOf(integratorWallet.address)).to.be.eq(integratorFee);
        });
        it('collect Rubic Token fee', async () => {
            await expect(
                bridge.collectRubicFee(swapToken.address, manager.address)
            ).to.be.revertedWithCustomError(bridge, 'NotAnAdmin');

            await bridge.connect(owner).collectRubicFee(swapToken.address, manager.address);

            expect(await swapToken.balanceOf(manager.address)).to.be.eq(RubicFee);
        });
        it('collect integrator crypto fee', async () => {
            const tracker = await balance.tracker(integratorWallet.address);

            await bridge
                .connect(integratorWallet)
                ['collectIntegratorFee(address)'](ethers.constants.AddressZero);

            const { delta, fees } = await tracker.deltaWithFees();

            expect(delta.add(fees).toString()).to.be.equal(integratorFixedFee.toString());
        });
        it('collect Rubic crypto fee', async () => {
            const tracker = await balance.tracker(manager.address);

            await expect(
                bridge.collectRubicCryptoFee(manager.address)
            ).to.be.revertedWithCustomError(bridge, 'NotAnAdmin');

            await bridge.connect(owner).collectRubicCryptoFee(manager.address);

            const { delta, fees } = await tracker.deltaWithFees();

            expect(delta.add(fees).toString()).to.be.equal(RubicFixedFee.toString());
        });
    });
});
