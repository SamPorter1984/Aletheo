const foundingEventABI = require('../../artifacts/contracts/FoundingEvent.sol/FoundingEvent.json');
const { DAIFixture } = require('./DAIFixtures');
const { EERC20FixtureNotInitialized } = require('./eerc20Fixtures');
const { uniswapFixtureWithETHUSDPool } = require('./uniswapFixtures');
const { WETHFixture } = require('./WETHFixtures');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function foundingEventFixture() {
  const eerc20 = await EERC20FixtureNotInitialized();
  const WETH = await WETHFixture();
  const DAI = await DAIFixture();
  const accounts = await ethers.getSigners();
  const foundingEvent = await (await ethers.getContractFactory('FoundingEvent')).deploy();
  return [foundingEvent, eerc20, WETH, DAI, accounts];
}

async function foundingEventInitializedFixture() {
  const [foundingEvent, eerc20, WETH, DAI, accounts] = await foundingEventFixture();
  await foundingEvent.connect(accounts[19]).init({
    deployer: accounts[0].address,
    liquidityManager:accounts[11].address,
    letToken: eerc20.address,
    WETH: WETH.address,
    DAI: DAI.address,
    router: accounts[5].address,
    factory: accounts[6].address,
  });
  return [foundingEvent, eerc20, WETH, DAI, accounts];
}

async function foundingEventNotInitializedWithUniswapFixture() {
  const eerc20 = await EERC20FixtureNotInitialized();
  const [uniswapV2Router02, uniswapV2Factory, WETH, DAI, ETHDAIPool] = await uniswapFixtureWithETHUSDPool();
  const accounts = await ethers.getSigners();
  const foundingEvent = await (await ethers.getContractFactory('FoundingEvent')).deploy();
  return [foundingEvent, eerc20, WETH, DAI, accounts, uniswapV2Router02, uniswapV2Factory, ETHDAIPool];
}

async function foundingEventWithUniswapFixture() {
  const eerc20 = await EERC20FixtureNotInitialized();
  const [uniswapV2Router02, uniswapV2Factory, WETH, DAI, ETHDAIPool] = await uniswapFixtureWithETHUSDPool();
  const accounts = await ethers.getSigners();
  const foundingEvent = await (await ethers.getContractFactory('FoundingEvent')).deploy();
  const ab = {
    deployer: accounts[0].address,
    liquidityManager:accounts[11].address,
    letToken: eerc20.address,
    WETH: WETH.address,
    DAI: DAI.address,
    router: uniswapV2Router02.address,
    factory: uniswapV2Factory.address,
  }
  await foundingEvent.connect(accounts[19]).init(ab);
  
  return [foundingEvent, eerc20, WETH, DAI, accounts, uniswapV2Router02, uniswapV2Factory, ETHDAIPool];
}

async function foundingEventConcludedWithUniswapFixture() {
  const [foundingEvent, eerc20, WETH, DAI, accounts, uniswapV2Router02, uniswapV2Factory, ETHDAIPool] = await foundingEventWithUniswapFixture();
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: accounts[3].address,
    foundingEvent: foundingEvent.address,
    governance: accounts[0].address,
  });
  await foundingEvent.connect(accounts[0]).setupEvent(111111111);
  await foundingEvent.connect(accounts[0]).depositETH({ value: 11111111111111 });
  await foundingEvent.connect(accounts[0]).triggerLaunch();
  //console.log(await uniswapV2Factory.getPair())
  return [foundingEvent, eerc20, WETH, DAI, accounts, uniswapV2Router02, uniswapV2Factory, ETHDAIPool];
}

module.exports = {
  foundingEventFixture,
  foundingEventInitializedFixture,
  foundingEventWithUniswapFixture,
  foundingEventConcludedWithUniswapFixture,
  foundingEventNotInitializedWithUniswapFixture,
};
