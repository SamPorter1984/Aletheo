const poolABI = require('./UniswapV2Pair.json'); ///UniswapV2Pair.json
const { DAIFixture } = require('./DAIFixtures');
const { WETHFixture } = require('./WETHFixtures');

async function uniswapFixture() {
  const accounts = await ethers.getSigners();
  const WETH = await WETHFixture();
  const uniswapV2Factory = await (await ethers.getContractFactory('UniswapV2Factory')).connect(accounts[19]).deploy(accounts[19].address);
  const uniswapV2Router02 = await (await ethers.getContractFactory('UniswapV2Router02')).connect(accounts[19]).deploy(uniswapV2Factory.address, WETH.address);
  return [uniswapV2Router02, uniswapV2Factory, WETH, accounts];
}

async function uniswapFixtureWithETHUSDPool() {
  const [uniswapV2Router02, uniswapV2Factory, WETH, accounts] = await uniswapFixture();
  const DAI = await DAIFixture();
  await uniswapV2Factory.createPair(WETH.address, DAI.address);
  const ETHDAIPoolAddress = await uniswapV2Factory.getPair(WETH.address, DAI.address);
  const uniswapV2Pair = await (await ethers.getContractFactory('UniswapV2Pair')).connect(accounts[19]).deploy();
  const ETHDAIPool = await uniswapV2Pair.attach(ETHDAIPoolAddress);
  const amount = ethers.BigNumber.from('100000000000000000000');
  await WETH.deposit({ value: amount });
  await WETH.approve(uniswapV2Router02.address, ethers.constants.MaxUint256);
  await DAI.approve(uniswapV2Router02.address, ethers.constants.MaxUint256);
  await uniswapV2Router02.connect(accounts[0]).addLiquidity(WETH.address, DAI.address, amount, amount, 0, 0, accounts[0].address, ethers.constants.MaxUint256);
  return [uniswapV2Router02, uniswapV2Factory, WETH, DAI, ETHDAIPool];
}

module.exports = {
  uniswapFixture,
  uniswapFixtureWithETHUSDPool,
};
