async function busdFixture() {
  return await (await ethers.getContractFactory('BEP20TokenMock')).deploy();
}

module.exports = {
  busdFixture,
};
