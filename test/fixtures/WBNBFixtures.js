async function wbnbFixture() {
  return await (await ethers.getContractFactory('WBNB')).deploy();
}

module.exports = {
  wbnbFixture,
};
