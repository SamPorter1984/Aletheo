const { expect } = require('chai');
const { mine, loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { foundingEventInitializedFixture, foundingEventWithUniswapFixture } = require('./fixtures/foundingEventFixtures.js');

let foundingEvent,
  eerc20,
  wbnb,
  busd,
  router,
  factory,
  bnbBUSDPool,
  foundingEventProxied = {},
  accounts = [];
const provider = ethers.provider;

describe('FOUNDINGEVENT', function () {
  beforeEach('deploy fixture', async () => {
    [foundingEvent, eerc20, wbnb, busd, accounts] = await loadFixture(foundingEventInitializedFixture);
    router = accounts[5];
    factory = accounts[6];
  });

  describe('init()', function () {
    it('Initializes state variables correctly', async function () {
      const ab = await foundingEvent._ab();
      expect(await foundingEvent.maxSold(), 'unexpected maxSold').to.equal(ethers.BigNumber.from('50000000000000000000000'));
      expect(await ab.deployer, 'unexpected deployer').to.equal(accounts[0].address);
      expect(await ab.letToken, 'unexpected letToken').to.equal(eerc20.address);
      expect(await ab.WBNB, 'unexpected WBNB').to.equal(wbnb.address);
      expect(await ab.BUSD, 'unexpected BUSD').to.equal(busd.address);
      expect(await ab.router, 'unexpected router').to.equal(router.address);
      expect(await ab.factory, 'unexpected factory').to.equal(factory.address);
      expect(await foundingEvent.emergency(), 'unexpected emergency').to.equal(false);
      expect(await foundingEvent.swapToBNB(), 'unexpected swapToBNB').to.equal(false);
      expect(await foundingEvent.genesisBlock(), 'unexpected genesisBlock').to.equal(0);
      expect(await foundingEvent.hardcap(), 'unexpected hardcap').to.equal(0);
      expect(await foundingEvent.sold(), 'unexpected sold').to.equal(0);
      expect(await foundingEvent.presaleEndBlock(), 'unexpected presaleEndBlock').to.equal(0);
    });
    it('Sets correct initial allowances to router for letToken, wbnb and wbusd', async () => {
      expect(await eerc20.allowance(foundingEvent.address, router.address), 'unexpected let token allowance').to.equal(ethers.constants.MaxUint256);
      expect(await wbnb.allowance(foundingEvent.address, router.address), 'unexpected wbnb allowance').to.equal(ethers.constants.MaxUint256);
      expect(await busd.allowance(foundingEvent.address, router.address), 'unexpected stable coin allowance').to.equal(ethers.constants.MaxUint256);
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
    [foundingEvent, eerc20, wbnb, busd, accounts, router, factory, bnbBUSDPool] = await loadFixture(foundingEventWithUniswapFixture);
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
  describe('setSwapToBNB(bool swapToBNB_)', function () {
    it('Fails if not deployer', async function () {
      await expect(foundingEvent.connect(accounts[1]).setSwapToBNB(true)).to.be.reverted;
    });
    it('Sets swapToBNB', async function () {
      const arg = true;
      await foundingEvent.setSwapToBNB(arg);
      expect(await foundingEvent.swapToBNB()).to.equal(arg);
    });
    it('Swaps all BUSD funds to WBNB if swapToBNB is true', async function () {
      const transferAmount = 1001110111;
      await busd.transfer(foundingEvent.address, transferAmount);
      const reserves = await bnbBUSDPool.getReserves();
      const wbnbReserve = reserves[0];
      const busdReserve = reserves[1];
      const result = await router.getAmountOut(transferAmount, busdReserve, wbnbReserve);
      const arg = true;
      const tx = foundingEvent.setSwapToBNB(arg);
      await expect(tx).not.to.be.reverted;
      expect(await wbnb.balanceOf(foundingEvent.address), 'unexpected wbnb balance').to.be.equal(result);
    });
    it('Swaps all WBNB funds to BUSD if swapToBNB is false', async function () {
      const transferAmount = 6001110111;
      await wbnb.deposit({ value: transferAmount });
      await wbnb.transfer(foundingEvent.address, transferAmount);
      const reserves = await bnbBUSDPool.getReserves();
      const wbnbReserve = reserves[0];
      const busdReserve = reserves[1];
      const result = await router.getAmountOut(transferAmount, busdReserve, wbnbReserve);
      const arg = false;
      await foundingEvent.setSwapToBNB(arg);
      expect(await busd.balanceOf(foundingEvent.address), 'unexpected busd balance').to.be.equal(result);
    });
    it('Ignores swapping funds to BNB if there are no funds to swap', async function () {
      const initialBalance = await wbnb.balanceOf(foundingEvent.address);
      const arg = true;
      await expect(foundingEvent.setSwapToBNB(arg), 'unexpected revert').not.to.be.reverted;
      expect(await wbnb.balanceOf(foundingEvent.address), 'unexpected wbnb balance').to.be.equal(initialBalance);
    });
    it('Ignores swapping funds to BUSD if there are no funds to swap', async function () {
      const initialBalance = await busd.balanceOf(foundingEvent.address);
      const arg = false;
      await expect(foundingEvent.setSwapToBNB(arg), 'unexpected revert').not.to.be.reverted;
      expect(await wbnb.balanceOf(foundingEvent.address), 'unexpected wbnb balance').to.be.equal(initialBalance);
    });
  });

  describe('depositBUSD()', function () {
    it('Fails if emergency', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await busd.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.toggleEmergency();
      await expect(foundingEvent.depositBUSD(111111)).to.be.reverted;
    });
    it('Fails if presaleEndBlock is zero', async function () {
      await busd.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await expect(foundingEvent.depositBUSD(111111)).to.be.reverted;
    });
    it('Fails if let token balance of FoundingEvent is zero', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await busd.transfer(foundingEvent.address, ethers.BigNumber.from('11111111111111111111111111'));
      await foundingEvent.triggerLaunch();
      await busd.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await expect(foundingEvent.depositBUSD(111111)).to.be.reverted;
    });
    it('Successfully deposits BUSD', async function () {
      const depositAmount = 10000000;
      await busd.transfer(accounts[1].address, depositAmount);
      await foundingEvent.setupEvent(1111111111111);
      const initialDeployerBalance = await busd.balanceOf(accounts[0].address);
      await busd.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositBUSD(depositAmount);
      const deployerBalance = await busd.balanceOf(accounts[0].address);
      const deposit = await foundingEvent.deposits(accounts[1].address);
      expect(deposit, 'unexpected deposits[msg.sender]').to.be.equal(depositAmount);
      expect(deployerBalance, 'unexpected deployer balance, incorrect 5% fee').to.equal(
        ethers.BigNumber.from(initialDeployerBalance).add(ethers.BigNumber.from(depositAmount / 20))
      );
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount);
      expect(await foundingEvent.sold(), 'unexpected sold()').to.be.equal(depositAmount * 2);
    });
    it('Swaps input token amount to WBNB if swapToBNB is true', async function () {
      await foundingEvent.setSwapToBNB(true);
      await foundingEvent.setupEvent(1111111111111);
      const depositAmount = 10000000;
      await busd.transfer(accounts[1].address, depositAmount);
      await busd.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositBUSD(depositAmount);
      expect(await busd.balanceOf(foundingEvent.address), 'unexpected busd balance').to.be.equal(0);
      expect(await wbnb.balanceOf(foundingEvent.address), 'unexpected wbnb balance').to.be.above(0);
      expect(await provider.getBalance(foundingEvent.address), 'unexpected bnb balance').to.equal(0);
    });
    it('Calculates correct let amount if setSwapToBNB is true', async function () {
      await busd.transfer(accounts[1].address, 10000000);
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToBNB(true);
      const depositAmount = 10000000;
      await busd.connect(accounts[1]).approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.connect(accounts[1]).depositBUSD(depositAmount);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount);
    });
    it('Creates liquidity if sold is equal or higher than maxSold', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToBNB(true);
      const depositAmount = (await busd.balanceOf(accounts[0].address)).div(700);
      await busd.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.depositBUSD(depositAmount);
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount);
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let token balance').to.equal(0);
    });
    it('Creates liquidity if presaleEndBlock reached or exceeded', async function () {
      await foundingEvent.setupEvent(1000000000);
      await mine(1000000000);
      await foundingEvent.setSwapToBNB(true);
      const depositAmount = ethers.BigNumber.from(10000000);
      await busd.approve(foundingEvent.address, ethers.constants.MaxUint256);
      await foundingEvent.depositBUSD(depositAmount);
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount);
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let token balance').to.equal(0);
    });
  });

  describe('depositBNB()', function () {
    it('Fails if emergency', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.toggleEmergency();
      await expect(foundingEvent.depositBNB({ value: 111111 })).to.be.reverted;
    });
    it('Fails if presaleEndBlock is zero', async function () {
      await expect(foundingEvent.depositBNB({ value: 111111 })).to.be.reverted;
    });
    it('Fails if let token balance of FoundingEvent is zero', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await busd.transfer(foundingEvent.address, ethers.BigNumber.from('111111111111111111111111'));
      await foundingEvent.triggerLaunch();
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let balance').to.equal(0);
      await expect(foundingEvent.depositBNB({ value: 1111111111 }), 'unexpected successful transaction').to.be.reverted;
    });
    it('Successfully deposits BUSD', async function () {
      const depositAmount = 10000000;
      await foundingEvent.setupEvent(1111111111111);
      const initialDeployerBalance = await provider.getBalance(accounts[0].address);
      await foundingEvent.connect(accounts[1]).depositBNB({ value: depositAmount });
      const deployerBalance = await provider.getBalance(accounts[0].address);
      const deposit = await foundingEvent.deposits(accounts[1].address);
      expect(deployerBalance, 'unexpected deployer balance').to.equal(
        ethers.BigNumber.from(initialDeployerBalance).add(ethers.BigNumber.from(depositAmount / 20))
      );
      expect(await foundingEvent.sold(), 'unexpectedSold()').to.be.equal(depositAmount);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexepected msg.sender let balance').to.be.equal(depositAmount);
      expect(await foundingEvent.deposits(accounts[1].address), 'unexpected deposits[msg.sender]').to.be.equal(depositAmount);
    });
    it('Should swap input token to BUSD if swapToBNB is false', async function () {
      await foundingEvent.setSwapToBNB(true);
      await foundingEvent.setupEvent(1111111111111);
      const depositAmount = 10000000;
      await foundingEvent.connect(accounts[1]).depositBNB({ value: depositAmount });
      expect(await busd.balanceOf(foundingEvent.address), 'unexepected busd balance').to.be.equal(0);
      expect(await wbnb.balanceOf(foundingEvent.address), 'unexepected wbnb balance').to.be.above(0);
      expect(await provider.getBalance(foundingEvent.address), 'unexepected bnb balance').to.equal(0);
    });
    it('Calculates correct let amount if setSwapToBNB is false', async function () {
      await foundingEvent.setupEvent(1111111111111);
      const depositAmount = 10000000;
      await foundingEvent.connect(accounts[1]).depositBNB({ value: depositAmount });
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected let token balance').to.be.equal(depositAmount);
    });
    it('Should create liquidity if sold is equal or higher than maxSold', async function () {
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.setSwapToBNB(true);
      for (let i = 0; i < 8; i++) {
        const depositAmount = (await provider.getBalance(accounts[i].address)).mul(7).div(10);
        await foundingEvent.connect(accounts[i]).depositBNB({ value: depositAmount });
      }
      expect(await eerc20.balanceOf(foundingEvent.address), 'unexpected let balance').to.equal(0);
    });
    it('Should create liquidity if presaleEndBlock is reached or exceeded', async function () {
      await foundingEvent.setupEvent(100000000000);
      await mine(100000000000);
      await foundingEvent.setSwapToBNB(true);
      const depositAmount = ethers.BigNumber.from(10000000);
      await foundingEvent.depositBNB({ value: depositAmount });
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
      const depositAmount = (await busd.balanceOf(accounts[0].address)).div(100000);
      await foundingEvent.setupEvent(1111111111111);
      await foundingEvent.depositBNB({ value: depositAmount });
      const contractBalance = await busd.balanceOf(foundingEvent.address);
      await foundingEvent.toggleEmergency();
      const balanceAfterDeposit = await busd.balanceOf(accounts[0].address);
      await foundingEvent.withdraw();
      expect(await busd.balanceOf(accounts[0].address), 'unexpected busd balance').to.equal(balanceAfterDeposit.add(contractBalance));
      expect(await foundingEvent.deposits(accounts[0].address), 'unexpected deposits[msg.sender]').to.equal(0);
    });
  });
});
