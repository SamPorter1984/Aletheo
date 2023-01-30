const {
  foundingEventFixture,
  foundingEventConcludedWithUniswapFixture,
  foundingEventWithUniswapFixture,
  foundingEventInitializedFixture,
} = require('./foundingEventFixtures');
const { stakingFixture } = require('./stakingFixture');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');

async function treasuryFixture() {
  const [foundingEvent, eerc20, wbnb, busd, accounts] = await foundingEventInitializedFixture();
  const staking = await stakingFixture();
  const treasury = await (await ethers.getContractFactory('Treasury')).deploy();
  return [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking];
}

async function treasuryInitializedFixture() {
  const [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking] = await treasuryFixture();
  const mockRouter = await (await ethers.getContractFactory('MockRouter')).deploy();
  const mockFoundingEvent = await (await ethers.getContractFactory('MockFoundingEvent')).deploy();
  const mockFactory = await (await ethers.getContractFactory('MockFactory')).deploy();
  const mockPool = await (await ethers.getContractFactory('MockPool')).deploy();
  await mockFoundingEvent.setGenesisBlock(1);
  await mockFactory.setPair(mockPool.address);
  await treasury.connect(accounts[19]).init({
    governance: accounts[0].address,
    aggregator: accounts[10].address,
    letToken: eerc20.address,
    foundingEvent: mockFoundingEvent.address,
    staking: accounts[11].address,
    router: mockRouter.address,
    factory: mockFactory.address,
    stableCoin: busd.address,
    otcMarket: accounts[11].address,
    wbnb: wbnb.address,
  });

  await staking
    .connect(accounts[19])
    .init({ letToken: eerc20.address, treasury: treasury.address, otcMarket: accounts[5].address, campaignMarket: accounts[5].address });
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
    factory: accounts[0].address,
    helper: accounts[0].address,
    WETH: accounts[0].address,
  });

  const provider = ethers.provider;
  return [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider];
}

async function treasuryMockWithLowBalanceFixture() {
  let [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking] = await treasuryFixture();
  const mockRouter = await (await ethers.getContractFactory('MockRouter')).deploy();
  const mockFoundingEvent = await (await ethers.getContractFactory('MockFoundingEvent')).deploy();
  const mockFactory = await (await ethers.getContractFactory('MockFactory')).deploy();
  const mockPool = await (await ethers.getContractFactory('MockPool')).deploy();
  await mockFoundingEvent.setGenesisBlock(1);
  await mockFactory.setPair(mockPool.address);
  await treasury.connect(accounts[19]).init({
    governance: accounts[0].address,
    aggregator: accounts[10].address,
    letToken: eerc20.address,
    foundingEvent: mockFoundingEvent.address,
    staking: accounts[11].address,
    router: mockRouter.address,
    factory: mockFactory.address,
    stableCoin: busd.address,
    otcMarket: accounts[11].address,
    wbnb: wbnb.address,
  });

  await staking
    .connect(accounts[19])
    .init({ letToken: eerc20.address, treasury: treasury.address, otcMarket: accounts[5].address, campaignMarket: accounts[5].address });
  eerc20 = await (await ethers.getContractFactory('MockEERC20')).deploy();
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
    factory: accounts[0].address,
    helper: accounts[0].address,
    WETH: accounts[0].address,
  });

  const provider = ethers.provider;
  return [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider];
}

async function treasuryWithUniswapAndFoundingEventNotConcludedFixture() {
  const [foundingEvent, eerc20, wbnb, busd, accounts, uniswapV2Router02, uniswapV2Factory, bnbBUSDPool] = await foundingEventWithUniswapFixture();
  const staking = await stakingFixture();
  const treasury = await (await ethers.getContractFactory('Treasury')).deploy();
  await treasury.connect(accounts[19]).init({
    governance: accounts[0].address,
    aggregator: accounts[10].address,
    letToken: eerc20.address,
    foundingEvent: foundingEvent.address,
    staking: accounts[11].address,
    router: uniswapV2Router02.address,
    factory: uniswapV2Factory.address,
    stableCoin: wbnb.address, //
    otcMarket: accounts[11].address,
    wbnb: wbnb.address,
  });
  await staking
    .connect(accounts[19])
    .init({ letToken: eerc20.address, treasury: treasury.address, otcMarket: accounts[5].address, campaignMarket: accounts[5].address });
  //await eerc20.connect(accounts[19]).init(accounts[2].address, accounts[3].address, foundingEvent.address, accounts[0].address);
  await foundingEvent.connect(accounts[0]).setupEvent(111111111);
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
    factory: accounts[0].address,
    helper: accounts[0].address,
    WETH: accounts[0].address,
  });
  return [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, uniswapV2Router02, uniswapV2Factory, bnbBUSDPool];
}

module.exports = {
  treasuryFixture,
  treasuryInitializedFixture,
  treasuryMockWithLowBalanceFixture,
  treasuryWithUniswapAndFoundingEventNotConcludedFixture,
};
