async function DAIFixture() {
  return await (await ethers.getContractFactory('BEP20TokenMock')).deploy();
}

module.exports = {
  DAIFixture,
};
