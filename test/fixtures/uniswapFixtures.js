const poolABI = require('./UniswapV2Pair.json'); ///UniswapV2Pair.json
const { busdFixture } = require('./BUSDFixtures');
const { wbnbFixture } = require('./WBNBFixtures');

async function uniswapFixture() {
  const accounts = await ethers.getSigners();
  const wbnb = await wbnbFixture();
  const uniswapV2Factory = await (await ethers.getContractFactory('UniswapV2Factory')).connect(accounts[19]).deploy(accounts[19].address);
  const uniswapV2Router02 = await (await ethers.getContractFactory('UniswapV2Router02')).connect(accounts[19]).deploy(uniswapV2Factory.address, wbnb.address);
  return [uniswapV2Router02, uniswapV2Factory, wbnb, accounts];
}

async function uniswapFixtureWithBNBUSDPool() {
  const [uniswapV2Router02, uniswapV2Factory, wbnb, accounts] = await uniswapFixture();
  const busd = await busdFixture();
  await uniswapV2Factory.createPair(wbnb.address, busd.address);
  const bnbBUSDPoolAddress = await uniswapV2Factory.getPair(wbnb.address, busd.address);
  const uniswapV2Pair = await (await ethers.getContractFactory('UniswapV2Pair')).connect(accounts[19]).deploy();
  const bnbBUSDPool = await uniswapV2Pair.attach(bnbBUSDPoolAddress);
  const amount = ethers.BigNumber.from('100000000000000000000');
  await wbnb.deposit({ value: amount });
  await wbnb.approve(uniswapV2Router02.address, ethers.constants.MaxUint256);
  await busd.approve(uniswapV2Router02.address, ethers.constants.MaxUint256);
  await uniswapV2Router02.connect(accounts[0]).addLiquidity(wbnb.address, busd.address, amount, amount, 0, 0, accounts[0].address, ethers.constants.MaxUint256);
  return [uniswapV2Router02, uniswapV2Factory, wbnb, busd, bnbBUSDPool];
}

module.exports = {
  uniswapFixture,
  uniswapFixtureWithBNBUSDPool,
};
