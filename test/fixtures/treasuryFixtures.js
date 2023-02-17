const {
  foundingEventFixture,
  foundingEventConcludedWithUniswapFixture,
  foundingEventWithUniswapFixture,
  foundingEventInitializedFixture,
} = require('./foundingEventFixtures');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');

async function treasuryFixture() {
  const [foundingEvent, eerc20, WETH, DAI, accounts] = await foundingEventInitializedFixture();
  const treasury = await (await ethers.getContractFactory('Treasury')).deploy();
  return [treasury, eerc20, WETH, DAI, accounts, foundingEvent];
}

async function treasuryInitializedFixture() {
  const [treasury, eerc20, WETH, DAI, accounts, foundingEvent] = await treasuryFixture();
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
    router: mockRouter.address,
    factory: mockFactory.address,
    stableCoin: DAI.address,
    otcMarket: accounts[11].address,
    WETH: WETH.address,
  });
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
  });

  const provider = ethers.provider;
  return [treasury, eerc20, WETH, DAI, accounts, foundingEvent, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider];
}

async function treasuryMockWithLowBalanceFixture() {
  let [treasury, eerc20, WETH, DAI, accounts, foundingEvent] = await treasuryFixture();
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
    router: mockRouter.address,
    factory: mockFactory.address,
    stableCoin: DAI.address,
    otcMarket: accounts[11].address,
    WETH: WETH.address,
  });
  eerc20 = await (await ethers.getContractFactory('MockEERC20')).deploy();
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
  });

  const provider = ethers.provider;
  return [treasury, eerc20, WETH, DAI, accounts, foundingEvent, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider];
}

async function treasuryWithUniswapAndFoundingEventNotConcludedFixture() {
  const [foundingEvent, eerc20, WETH, DAI, accounts, uniswapV2Router02, uniswapV2Factory, ETHDAIPool] = await foundingEventWithUniswapFixture();
  const treasury = await (await ethers.getContractFactory('Treasury')).deploy();
  await treasury.connect(accounts[19]).init({
    governance: accounts[0].address,
    aggregator: accounts[10].address,
    letToken: eerc20.address,
    foundingEvent: foundingEvent.address,
    router: uniswapV2Router02.address,
    factory: uniswapV2Factory.address,
    stableCoin: WETH.address, //
    otcMarket: accounts[11].address,
    WETH: WETH.address,
  });
  //await eerc20.connect(accounts[19]).init(accounts[2].address, accounts[3].address, foundingEvent.address, accounts[0].address);
  await foundingEvent.connect(accounts[0]).setupEvent(111111111);
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: treasury.address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
  });
  return [treasury, eerc20, WETH, DAI, accounts, foundingEvent, uniswapV2Router02, uniswapV2Factory, ETHDAIPool];
}

module.exports = {
  treasuryFixture,
  treasuryInitializedFixture,
  treasuryMockWithLowBalanceFixture,
  treasuryWithUniswapAndFoundingEventNotConcludedFixture,
};
