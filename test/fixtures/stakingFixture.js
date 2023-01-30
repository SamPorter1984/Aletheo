async function stakingFixture() {
  return await (await ethers.getContractFactory('StakingContract')).deploy();
}

module.exports = {
  stakingFixture,
};
