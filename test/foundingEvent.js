const { expect } = require('chai');
const { mine, loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { foundingEventInitializedFixture, foundingEventWithUniswapFixture } = require('./fixtures/foundingEventFixtures.js');

let foundingEvent,
  eerc20,
  WETH,
  DAI,
  router,
  factory,
  ETHDAIPool,
  foundingEventProxied = {},
  accounts = [];
const provider = ethers.provider;

describe('FOUNDINGEVENT', function () {
  beforeEach('deploy fixture', async () => {
    [foundingEvent, eerc20, WETH, DAI, accounts] = await loadFixture(foundingEventInitializedFixture);
    router = accounts[5];
    factory = accounts[6];
  });

  describe('init()', function () {
    it('Initializes state variables correctly', async function () {
      const ab = await foundingEvent.ab();
      expect(await foundingEvent.maxSold(), 'unexpected maxSold').to.equal(ethers.BigNumber.from('50000000000000000000000'));
      expect(await ab.deployer, 'unexpected deployer').to.equal(accounts[0].address);
      expect(await ab.letToken, 'unexpected letToken').to.equal(eerc20.address);
      expect(await ab.WETH, 'unexpected WETH').to.equal(WETH.address);
      expect(await ab.DAI, 'unexpected DAI').to.equal(DAI.address);
      expect(await ab.router, 'unexpected router').to.equal(router.address);
      expect(await ab.factory, 'unexpected factory').to.equal(factory.address);
      expect(await foundingEvent.emergency(), 'unexpected emergency').to.equal(false);
      expect(await foundingEvent.swapToETH(), 'unexpected swapToETH').to.equal(false);
      expect(await foundingEvent.genesisBlock(), 'unexpected genesisBlock').to.equal(0);
      expect(await foundingEvent.hardcap(), 'unexpected hardcap').to.equal(0);
      expect(await foundingEvent.sold(), 'unexpected sold').to.equal(0);
      expect(await foundingEvent.presaleEndBlock(), 'unexpected presaleEndBlock').to.equal(0);
    });
    it('Sets correct initial allowances to router for letToken, WETH and wDAI', async () => {
      expect(await eerc20.allowance(foundingEvent.address, router.address), 'unexpected let token allowance').to.equal(ethers.constants.MaxUint256);
      expect(await WETH.allowance(foundingEvent.address, router.address), 'unexpected WETH allowance').to.equal(ethers.constants.MaxUint256);
      expect(await DAI.allowance(foundingEvent.address, router.address), 'unexpected stable coin allowance').to.equal(ethers.constants.MaxUint256);
    });
  });

  describe('setupEvent(uint b)', function () {
    it('Fails if not deployer', async function () {
      const arg = 11111111111111;
      await expect(foundingEvent.connect(accounts[1]).setupEvent(arg)).to.be.reverted;
      expect(await foundingEvent.presaleEndBlock()).to.equal(0);
    });
    it('Sets presaleEndBlock', async function () {
      const arg = 11111111111111;
      await foundingEvent.setupEvent(arg);
      expect(await foundingEvent.presaleEndBlock()).to.equal(arg);
    });
    it('Fails to set presaleEndBlock if not higher than block.number', async function () {
      const arg = 1;
      await expect(foundingEvent.setupEvent(arg)).to.be.reverted;
      expect(await foundingEvent.presaleEndBlock()).to.equal(0);
    });
    it('Sets presaleEndBlock if presaleEndBlock already wasnt zero and new value is lower than previous', async function () {
      const arg = 11111111111111;
      const arg1 = 1111111111111;
      await expect(foundingEvent.setupEvent(arg));
      await expect(foundingEvent.setupEvent(arg1));
      expect(await foundingEvent.presaleEndBlock()).to.equal(arg1);
    });
    it('Fails to set presaleEndBlock if presaleEndBlock already not zero and new value is not lower than previous', async function () {
      const arg = 11111111111111;
      const arg1 = 111111111111111;
      await expect(foundingEvent.setupEvent(arg));
      await expect(foundingEvent.setupEvent(arg1)).to.be.reverted;
      expect(await foundingEvent.presaleEndBlock()).to.equal(arg);
    });
  });

  describe('toggleEmergency()', function () {
    it('Fails if not deployer', async function () {
      await expect(foundingEvent.connect(accounts[1]).toggleEmergency()).to.be.reverted;
    });
    it('Sets emergency to true if it was false', async function () {
      await foundingEvent.toggleEmergency();
      expect(await foundingEvent.emergency()).to.equal(true);
    });
    it('Sets emergency to false if it was true', async function () {
      await foundingEvent.toggleEmergency();
      expect(await foundingEvent.emergency()).to.equal(true);
      await foundingEvent.toggleEmergency();
      expect(await foundingEvent.emergency()).to.equal(false);
    });
  });
});

describe('uniswap dependent functions', function () {
  beforeEach('deploy fixture', async () => {
    [foundingEvent, eerc20, WETH, DAI, accounts, router, factory, ETHDAIPool] = await loadFixture(foundingEventWithUniswapFixture);
    await eerc20
      .connect(accounts[19])
      .init({
        liquidityManager: accounts[2].address,
        treasury: accounts[3].address,
        foundingEvent: foundingEvent.address,
        governance: accounts[0].address,
        factory: accounts[0].address,
        helper: accounts[0].address,
        WETH: accounts[0].address,
      });
  });
  describe('setSwapToETH(bool swapToETH_)', function () {
    it('Fails if not deployer', async function () {
      await expect(foundingEvent.connect(accounts[1]).setSwapToETH(true)).to.be.reverted;
    });
    it('Sets swapToETH', async function () {
      const arg = true;
      await foundingEvent.setSwapToETH(arg);
      expect(await foundingEvent.swapToETH()).to.equal(arg);
    });
    it('Swaps all DAI funds to WETH if swapToETH is true', async function () {
      const transferAmount = 1001110111;
      await DAI.transfer(foundingEvent.address, transferAmount);
      const reserves = await ETHDAIPool.getReserves();
      const WETHReserve = reserves[0];
      const DAIReserve = reserves[1];
      const result = await router.getAmountOut(transferAmount, DAIReserve, WETHReserve);
      const arg = true;
      const tx = foundingEvent.setSwapToETH(arg);
      await expect(tx).not.to.be.reverted;
      expect(await WETH.balanceOf(foundingEvent.address), 'unexpected WETH balance').to.be.equal(result);
    });
    it('Swaps all WETH funds to DAI if swapToETH is false', async function () {
      const transferAmount = 6001110111;
      await WETH.deposit({ value: transferAmount });
      await WETH.transfer(foundingEvent.address, transferAmount);
      const reserves = await ETHDAIPool.getReserves();
      const WETHReserve = reserves[0];
      const DAIReserve = reserves[1];
      const result = await router.getAmountOut(transferAmount, DAIReserve, WETHReserve);
      const arg = false;
      await foundingEvent.setSwapToETH(arg);
      expect(await DAI.balanceOf(foundingEvent.address), 'unexpected DAI balance').to.be.equal(result);
    });
    it('Ignores swapping funds to ETH if there are no funds to swap', async function () {
      const initialBalance = await WETH.balanceOf(foundingEvent.address);
      const arg = true;
      await expect(foundingEvent.setSwapToETH(arg), 'unexpected revert').not.to.be.reverted;
      expect(await WETH.balanceOf(foundingEvent.address), 'unexpected WETH balance').to.be.equal(initialBalance);
    });
    it('Ignores swapping funds to DAI if there are no funds to swap', async function () {
      const initialBalance = await DAI.balanceOf(foundingEvent.address);
      const arg = false;
      await expect(foundingEvent.setSwapToETH(arg), 'unexpected revert').not.to.be.reverted;
      expect(await WETH.balanceOf(foundingEvent.address), 'unexpected WETH balance').to.be.equal(initialBalance);
    });
  });

  describe('depositDAI()', function () {
    it('Fails if emergency', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await DAI.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.toggleEmergency();
      await expect(foundingEvent.depositDAI(111111)).to.be.reverted;
    });
    it('Fails if presaleEndBlock is zero', async function () {
      await DAI.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await expect(foundingEvent.depositDAI(111111)).to.be.reverted;
    });
    it('Fails if let token balance of FoundingEvent is zero', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await DAI.transfer(foundingEvent.address, ethers.BigNumber.from('11111111111111111111111111'));
      await foundingEvent.triggerLaunch();
      await DAI.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await expect(foundingEvent.depositDAI(111111)).to.be.reverted;
    });
    it('Successfully deposits DAI', async function () {
      const depositAmount = ethers.BigNumber.from(10000000);
      await DAI.transfer(accounts[1].address, depositAmount);
      await foundingEvent.setupEvent(1111111111111);
      const initialDeployerBalance = await DAI.balanceOf(accounts[0].address);
      await DAI.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositDAI(depositAmount);
      const deployerBalance = await DAI.balanceOf(accounts[0].address);
      const deposit = await foundingEvent.deposits(accounts[1].address);
      expect(deposit, 'unexpected deposits[msg.sender]').to.be.equal(depositAmount.div(2));
      expect(deployerBalance, 'unexpected deployer balance, incorrect 10% fee').to.equal(
        ethers.BigNumber.from(initialDeployerBalance).add(ethers.BigNumber.from(depositAmount.div(10)))
      );
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount.div(2));
      expect(await foundingEvent.sold(), 'unexpected sold()').to.be.equal(depositAmount);
    });
    it('Swaps input token amount to WETH if swapToETH is true', async function () {
      await foundingEvent.setSwapToETH(true);
      await foundingEvent.setupEvent(1111111111111);
      const depositAmount = ethers.BigNumber.from(10000000);
      await DAI.transfer(accounts[1].address, depositAmount);
      await DAI.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositDAI(depositAmount);
      expect(await DAI.balanceOf(foundingEvent.address), 'unexpected DAI balance').to.be.equal(0);
      expect(await WETH.balanceOf(foundingEvent.address), 'unexpected WETH balance').to.be.above(0);
      expect(await provider.getBalance(foundingEvent.address), 'unexpected ETH balance').to.equal(0);
    });
    it('Calculates correct let amount if setSwapToETH is true', async function () {
      await DAI.transfer(accounts[1].address, 10000000);
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToETH(true);
      const depositAmount = ethers.BigNumber.from(10000000);
      await DAI.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositDAI(depositAmount);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount.div(2));
    });
    it('Creates liquidity if sold is equal or higher than maxSold', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToETH(true);
      const depositAmount = (await DAI.balanceOf(accounts[0].address)).div(300);
      await DAI.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.depositDAI(depositAmount);
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount.div(2));
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let token balance').to.equal(0);
    });
    it('Creates liquidity if presaleEndBlock reached or exceeded', async function () {
      await foundingEvent.setupEvent(1000000000);
      await mine(1000000000);
      await foundingEvent.setSwapToETH(true);
      const depositAmount = ethers.BigNumber.from(10000000);
      await DAI.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.depositDAI(depositAmount);
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount.div(2));
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let token balance').to.equal(0);
    });
  });

  describe('depositETH()', function () {
    it('Fails if emergency', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.toggleEmergency();
      await expect(foundingEvent.depositETH({ value: 111111 })).to.be.reverted;
    });
    it('Fails if presaleEndBlock is zero', async function () {
      await expect(foundingEvent.depositETH({ value: 111111 })).to.be.reverted;
    });
    it('Fails if let token balance of FoundingEvent is zero', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await DAI.transfer(foundingEvent.address, ethers.BigNumber.from('111111111111111111111111'));
      await foundingEvent.triggerLaunch();
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let balance').to.equal(0);
      await expect(foundingEvent.depositETH({ value: 1111111111 }), 'unexpected successful transaction').to.be.reverted;
    });
    it('Successfully deposits ETH', async function () {
      const depositAmount = ethers.BigNumber.from(10000000);
      await foundingEvent.setupEvent(1111111111111);
      const initialDeployerBalance = await provider.getBalance(accounts[0].address);
      await foundingEvent.connect(accounts[1]).depositETH({ value: depositAmount });
      const deployerBalance = await provider.getBalance(accounts[0].address);
      const deposit = await foundingEvent.deposits(accounts[1].address);
      expect(deployerBalance, 'unexpected deployer balance').to.equal(
        ethers.BigNumber.from(initialDeployerBalance).add(ethers.BigNumber.from(depositAmount.div(10)))
      );
      expect(await foundingEvent.sold(), 'unexpectedSold()').to.be.equal(depositAmount);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexepected msg.sender let balance').to.be.equal(depositAmount.div(2));
      expect(await foundingEvent.deposits(accounts[1].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount.div(2));
    });
    it('Should swap input token to DAI if swapToETH is false', async function () {
      await foundingEvent.setSwapToETH(true);
      await foundingEvent.setupEvent(1111111111111);
      const depositAmount = ethers.BigNumber.from(10000000);
      await foundingEvent.connect(accounts[1]).depositETH({ value: depositAmount });
      expect(await DAI.balanceOf(foundingEvent.address), 'unexepected DAI balance').to.be.equal(0);
      expect(await WETH.balanceOf(foundingEvent.address), 'unexepected WETH balance').to.be.above(0);
      expect(await provider.getBalance(foundingEvent.address), 'unexepected ETH balance').to.equal(0);
    });
    it('Calculates correct let amount if setSwapToETH is false', async function () {
      await foundingEvent.setupEvent(1111111111111);
      
      const depositAmount = ethers.BigNumber.from(10000000);
      await foundingEvent.connect(accounts[1]).depositETH({ value: depositAmount });
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount.div(2));
    });
    it('Should create liquidity if sold is equal or higher than maxSold', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToETH(true);
      for (let i = 0; i < 8; i++) {
        const depositAmount = (await provider.getBalance(accounts[i].address)).mul(7).div(10);
        await foundingEvent.connect(accounts[i]).depositETH({ value: depositAmount });
      }
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let balance').to.equal(0);
    });
    it('Should create liquidity if presaleEndBlock is reached or exceeded', async function () {
      await foundingEvent.setupEvent(100000000000);
      await mine(100000000000);
      await foundingEvent.setSwapToETH(true);
      const depositAmount = ethers.BigNumber.from(10000000);
      await foundingEvent.depositETH({ value: depositAmount });
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let balance').to.equal(0);
    });
  });

  describe('withdraw()', function () {
    it('Fails if not emergency', async function () {
      await expect(foundingEvent.withdraw()).to.be.reverted;
    });
    it('Fails if deposit is 0', async function () {
      await foundingEvent.toggleEmergency();
      await expect(foundingEvent.withdraw()).to.be.reverted;
    });
    it('Sends deposit amount to msg.sender and sets deposit for msg.sender to 0', async function () {
      const depositAmount = (await DAI.balanceOf(accounts[0].address)).div(100000);
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.depositETH({ value: depositAmount });
      const contractBalance = await DAI.balanceOf(foundingEvent.address);
      await foundingEvent.toggleEmergency();
      const balanceAfterDeposit = await DAI.balanceOf(accounts[0].address);
      await foundingEvent.withdraw();
      expect(await DAI.balanceOf(accounts[0].address), 'unexpected DAI balance').to.equal(balanceAfterDeposit.add(contractBalance));
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.equal(0);
    });
  });
});
