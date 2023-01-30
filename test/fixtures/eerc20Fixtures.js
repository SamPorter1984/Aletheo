const EERC20ABI = require('../../artifacts/contracts/EERC20.sol/EERC20.json');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function EERC20FixtureNotInitialized() {
  return await (await ethers.getContractFactory('EERC20')).deploy();
}

async function EERC20Fixture() {
  const eerc20 = await EERC20FixtureNotInitialized();
  const accounts = await ethers.getSigners();
  await eerc20.connect(accounts[19]).init({
    liquidityManager: accounts[2].address,
    treasury: accounts[3].address,
    foundingEvent: accounts[4].address,
    governance: accounts[0].address,
    factory: accounts[0].address,
    helper: accounts[0].address,
    WETH: accounts[0].address,
  });
  return [eerc20, accounts];
}

async function EERC20ProxiedFixture() {
  const accounts = await ethers.getSigners();
  const trustMinimizedProxy = await (await ethers.getContractFactory('TrustMinimizedProxy')).connect(accounts[19]).deploy();
  const eerc20 = await EERC20FixtureNotInitialized();
  const iEERC20 = new ethers.utils.Interface(EERC20ABI.abi);
  const initData = iEERC20.encodeFunctionData('init', [
    {
      liquidityManager: accounts[2].address,
      treasury: accounts[3].address,
      foundingEvent: accounts[4].address,
      governance: accounts[0].address,
      factory: accounts[0].address,
      helper: accounts[0].address,
      WETH: accounts[0].address,
    },
  ]);
  await trustMinimizedProxy.connect(accounts[19]).proposeTo(eerc20.address, initData);
  const eerc20Proxied = await eerc20.attach(trustMinimizedProxy.address);
  return [eerc20Proxied, accounts];
}

async function erc20Fixture() {
  const accounts = await ethers.getSigners();
  const erc20 = await (await ethers.getContractFactory('ERC20')).deploy('unlockTime', '{ value: lockedAmount }');
  return [erc20, accounts];
}

module.exports = {
  EERC20Fixture,
  erc20Fixture,
  EERC20ProxiedFixture,
  EERC20FixtureNotInitialized,
};
