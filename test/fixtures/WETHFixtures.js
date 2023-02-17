async function WETHFixture() {
  return await (await ethers.getContractFactory('WETH')).deploy();
}

module.exports = {
  WETHFixture,
};
