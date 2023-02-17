const { expect } = require('chai');
const { loadFixture, time, mine } = require('@nomicfoundation/hardhat-network-helpers');
const { treasuryInitializedFixture, treasuryMockWithLowBalanceFixture } = require('./fixtures/treasuryFixtures.js');
let { ethers } = require('hardhat');
const { cc } = require('./constants.js');

let provider = ethers.provider;
let treasury,
  eerc20,
  foundingEvent,
  WETH,
  mockFactory,
  mockPool,
  mockFoundingEvent,
  mockRouter,
  DAI = {},
  accounts = [];

describe('TREASURY UNIT TESTS', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, WETH, DAI, accounts, foundingEvent, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider] = await loadFixture(
      treasuryInitializedFixture
    );
  });
  describe('init()', function () {
    it('Initializes state variables correctly', async function () {
      expect(await treasury.posterRate(), 'unexpected posterRate').to.equal(2000);
      expect(await treasury.baseRate(), 'unexpected baseRate').to.equal(ethers.BigNumber.from('10000000000000000000000000000000'));
      const ab = await treasury.ab();
      expect(await ab.governance, 'unexpected governance').to.equal(accounts[0].address);
      expect(await ab.letToken, 'unexpected letToken').to.equal(eerc20.address);
      expect(await ab.foundingEvent, 'unexpected foundingEvent').to.equal(mockFoundingEvent.address);
      expect(await ab.factory, 'unexpected factory').to.equal(mockFactory.address);
      expect(await ab.stableCoin, 'unexpected stableCoin').to.equal(DAI.address);
      expect(await ab.router, 'unexpected router').to.equal(mockRouter.address);
    });
    it('Sets correct initial allowance to router for letToken', async () => {
      expect(await eerc20.allowance(treasury.address, mockRouter.address), 'unexpected let token allowance').to.equal(ethers.constants.MaxUint256);
    });
  });
  /*
  describe('setGovernance()', function () {
    it('Sets governance if called by governance', async function () {
      await expect(treasury.setGovernance(accounts[1].address)).not.to.be.reverted;
      expect(await treasury._governance(), 'unexpected governance').to.equal(accounts[1].address);
    });
    it('Fails to set governance if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).setGovernance(accounts[1].address)).to.be.reverted;
    });
  });

  describe('setAggregator()', function () {
    it('Sets aggregator if called by governance', async function () {
      await expect(treasury.setAggregator(accounts[1].address)).not.to.be.reverted;
      expect(await treasury._aggregator(), 'unexpected aggregator').to.equal(accounts[1].address);
    });
    it('Fails to set aggregator if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).setAggregator(accounts[1].address)).to.be.reverted;
    });
  });
*/
  describe('setPosterRate()', function () {
    it('Sets posterRate if called by governance', async function () {
      const arg = 100;
      await expect(treasury.setPosterRate(arg)).not.to.be.reverted;
      expect(await treasury.posterRate(), 'unexpected posterRate').to.equal(arg);
    });
    it('Fails to set posterRate if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).setPosterRate(100)).to.be.reverted;
    });
    it('Fails to set posterRate if called by governance and value is above than 2000', async function () {
      await expect(treasury.connect(accounts[2]).setPosterRate(29999)).to.be.reverted;
    });
    it('Fails to set posterRate if called by governance and value is below than 100', async function () {
      await expect(treasury.connect(accounts[2]).setPosterRate(1)).to.be.reverted;
    });
  });

  describe('setBaseRate()', function () {
    it('Sets baseRate if called by governance', async function () {
      const arg = ethers.BigNumber.from('100000000000000000001');
      await expect(treasury.setBaseRate(arg)).not.to.be.reverted;
      expect(await treasury.baseRate(), 'unexpected baseRate').to.equal(arg);
    });
    it('Fails to set baseRate if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).setBaseRate(ethers.BigNumber.from('30000000000000'))).to.be.reverted;
    });
    it('Fails to set baseRate if called by governance and value is above previous baseRate', async function () {
      const initial = await treasury.baseRate();
      await expect(treasury.connect(accounts[2]).setBaseRate(initial.add(1))).to.be.reverted;
    });
    it('Fails to set baseRate if called by governance and value is below than 1e13', async function () {
      await expect(treasury.connect(accounts[2]).setBaseRate(1)).to.be.reverted;
    });
  });

  describe('addBeneficiary()', function () {
    it('Adds beneficiary if called by governance', async function () {
      const initial = await treasury.totBenEmission();
      const arg = ethers.BigNumber.from('30000000000000');
      const arg2 = ethers.BigNumber.from('30000000');
      await expect(treasury.addBeneficiary(accounts[0].address, arg, arg2)).not.to.be.reverted;
      expect((await treasury.bens(accounts[0].address)).amount, 'unexpected amount').to.equal(arg);
      expect((await treasury.bens(accounts[0].address)).lastClaim, 'unexpected lastClaim').to.equal(await time.latestBlock());
      expect((await treasury.bens(accounts[0].address)).emission, 'unexpected emission').to.equal(arg2);
      expect(await treasury.totBenEmission(), 'unexpected totBenEmission').to.equal(initial.add(arg2));
    });
    it('Fails to addBeneficiary if called by not governance', async function () {
      const arg = ethers.BigNumber.from('30000000000000');
      await expect(treasury.connect(accounts[2]).addBeneficiary(accounts[0].address, arg, 1)).to.be.reverted;
    });
    it('Fails if totBenEmission is above 1e22 and called by governance', async function () {
      const arg = ethers.BigNumber.from('30000000000000');
      const arg2 = ethers.BigNumber.from('300000000000000000000000000');
      await expect(treasury.addBeneficiary(accounts[0].address, arg, arg2)).to.be.reverted;
    });
  });

  describe('addAirdropBulk()', function () {
    it('Adds airdrops bulk if called by governance', async function () {
      const arg = ethers.BigNumber.from('30000000000000');
      await expect(treasury.addAirdropBulk([accounts[0].address], [arg])).not.to.be.reverted;
      expect((await treasury.airdrops(accounts[0].address)).amount, 'unexpected airdrops[address].amount').to.equal(arg);
      expect((await treasury.airdrops(accounts[0].address)).lastClaim, 'unexpected airdrops[address].lastClaim').to.equal(await time.latestBlock());
    });
    it('Fails to addAirdropBulk if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).addAirdropBulk([accounts[0].address], [ethers.BigNumber.from('30000000000000')])).to.be.reverted;
    });
    it('Fails to addAirdropBulk if called by governance and arg arrays lengths do not match', async function () {
      await expect(treasury.addAirdropBulk([accounts[0].address], [ethers.BigNumber.from('30000000000000'), 5])).to.be.reverted;
    });
    it('Fails to addAirdropBulk if called by governance and emission if one of the amounts is higher than 20000e18', async function () {
      await expect(treasury.addAirdropBulk([accounts[0].address, accounts[1].address], [ethers.BigNumber.from('30000000000000000000000000000'), 5])).to.be
        .reverted;
    });
  });

  describe('addPosters()', function () {
    beforeEach('deploy fixture', async () => {});
    it('Adds posters if called by aggregator', async function () {
      const arg = ethers.BigNumber.from('30000000000000');
      await expect(treasury.connect(accounts[10]).addPosters([accounts[0].address], [arg])).not.to.be.reverted;
      expect((await treasury.posters(accounts[0].address)).unapprovedAmount, 'unexpected unapprovedAmount').to.equal(arg);
    });
    it('Fails to addPosters if called by not aggregator', async function () {
      await expect(treasury.connect(accounts[2]).addPosters([accounts[0].address], [ethers.BigNumber.from('30000000000000')])).to.be.reverted;
    });
    it('Fails to addPosters if called by aggregator and arg arrays lengths do not match', async function () {
      await expect(treasury.connect(accounts[10]).addPosters([accounts[0].address], [ethers.BigNumber.from('30000000000000'), 5])).to.be.reverted;
    });
    it('Fails to addPosters if called by aggregator and emission of one of the amounts is higher than 2000e18', async function () {
      await expect(
        treasury.connect(accounts[10]).addPosters([accounts[0].address, accounts[1].address], [ethers.BigNumber.from('30000000000000000000000000000'), 5])
      ).to.be.reverted;
    });
  });

  describe('editUnapprovedPosters()', function () {
    // governance should not be able to bypass aggregator this easily
    beforeEach('deploy fixture', async () => {});
    it('Edits unapprovedPosters if called by governance', async function () {
      const arg = ethers.BigNumber.from('30000000000000');
      await expect(treasury.editUnapprovedPosters([accounts[0].address], [arg])).not.to.be.reverted;
      expect((await treasury.posters(accounts[0].address)).unapprovedAmount, 'unexpected unapprovedAmount').to.equal(arg);
    });
    it('Fails to editUnapprovedPosters if called by not governance', async function () {
      await expect(treasury.connect(accounts[2]).editUnapprovedPosters([accounts[0].address], [ethers.BigNumber.from('30000000000000')])).to.be.reverted;
    });
    it('Fails to editUnapprovedPosters if called by governance and arg arrays lengths do not match', async function () {
      await expect(treasury.editUnapprovedPosters([accounts[0].address], [ethers.BigNumber.from('30000000000000'), 5])).to.be.reverted;
    });
    it('Fails to editUnapprovedPosters if called by governance and emission if one of the amounts is higher than 2000e18', async function () {
      await expect(treasury.editUnapprovedPosters([accounts[0].address, accounts[1].address], [ethers.BigNumber.from('30000000000000000000000000000'), 5])).to
        .be.reverted;
    });
  });

  describe('approvePosters()', function () {
    beforeEach('deploy fixture', async () => {});
    it('Approves posters if called by governance', async function () {
      const arg = 15;
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [arg]);
      await expect(treasury.connect(accounts[0]).approvePosters([accounts[0].address])).not.to.be.reverted;
      expect((await treasury.posters(accounts[0].address)).amount, 'unexpected posters[address].amount').to.equal(arg);
      expect((await treasury.posters(accounts[0].address)).unapprovedAmount, 'unexpected unapprovedAmount').to.equal(0);
    });
    it('Sets lastClaim to block.number if it was zero and if called by governance', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [15]);
      await expect(treasury.approvePosters([accounts[0].address])).not.to.be.reverted;
      expect((await treasury.posters(accounts[0].address)).lastClaim, 'unexpected lastClaim').to.equal(await time.latestBlock());
    });
    it('Adds to totalPosterRewards', async function () {
      const initial = await treasury.totalPosterRewards();
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [15]);
      await expect(treasury.approvePosters([accounts[0].address])).not.to.be.reverted;
      expect(await treasury.totalPosterRewards(), 'unexpected totalPosterRewards').to.equal(initial.add(15));
    });
    it('Fails if called by not governance', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [15]);
      await expect(treasury.connect(accounts[2]).approvePosters([accounts[0].address])).to.be.reverted;
    });
  });

  describe('claimBenRewards()', function () {
    it('Gets beneficiary rewards if called by beneficiary', async function () {
      await treasury.connect(accounts[0]).addBeneficiary(accounts[0].address, 555555, 5555555);
      const tx = treasury.connect(accounts[0]).claimBenRewards();
      await expect(tx).not.to.be.reverted;
    });
    it('Fails if called by not beneficiary', async function () {
      await expect(treasury.claimBenRewards()).to.be.revertedWith('not beneficiary');
    });
  });

  describe('claimAirdrop()', function () {
    it('Gets airdrop if called by eligible', async function () {
      await treasury.addAirdropBulk([accounts[0].address], [555555]);
      const tx = treasury.connect(accounts[0]).claimAirdrop();
      await expect(tx).not.to.be.reverted;
    });
    it('Fails if called by not eligible', async function () {
      await expect(treasury.claimAirdrop()).to.be.reverted;
    });
    it('Fails if foundingEvent hasnt concluded', async function () {
      await mockFoundingEvent.setGenesisBlock(0);
      await treasury.addAirdropBulk([accounts[0].address], [555555]);
      const tx = treasury.connect(accounts[0]).claimAirdrop();
      await expect(tx).to.be.reverted;
    });
  });

  describe('claimAirdropFor()', function () {
    it('Gets airdrop if called for eligible', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [555555]);
      const tx = treasury.connect(accounts[0]).claimAirdropFor([accounts[1].address]);
      await expect(tx).not.to.be.reverted;
    });
    it('Fails if called for not eligible', async function () {
      await expect(treasury.claimAirdropFor([accounts[1].address])).to.be.reverted;
    });
    it('Fails if foundingEvent hasnt concluded', async function () {
      await mockFoundingEvent.setGenesisBlock(0);
      await treasury.addAirdropBulk([accounts[1].address], [555555]);
      const tx = treasury.connect(accounts[0]).claimAirdropFor([accounts[1].address]);
      await expect(tx).to.be.reverted;
    });
  });

  describe('airdropAvailable()', function () {
    it('Gets airdropAvailable for eligible', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [555555]);
      const airdropAvailableReturned = (await treasury.airdropAvailable(accounts[1].address))[0];
      await expect(airdropAvailableReturned).to.equal(555555);
    });
    it('Returns 0 if called for not eligible', async function () {
      const airdropAvailableReturned = (await treasury.airdropAvailable(accounts[1].address))[0];
      expect(airdropAvailableReturned).to.equal(0);
    });
  });

  describe('claimPosterRewards()', function () {
    it('Gets poster rewards if called by poster with amount above 0', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [1111111111]);
      await treasury.approvePosters([accounts[0].address]);
      const tx = treasury.connect(accounts[0]).claimPosterRewards();
      await expect(tx).not.to.be.reverted;
    });
    it('Sends bonus if eligible for airdrop', async function () {
      await treasury.addAirdropBulk([accounts[0].address], [555555]);
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [1111111111]);
      await treasury.approvePosters([accounts[0].address]);
      const tx = treasury.connect(accounts[0]).claimPosterRewards();
      await expect(tx).not.to.be.reverted;
      (await tx).wait();
      expect((await treasury.airdrops(accounts[0].address))[0]).to.be.below(555555);
    });
    it('Sends bonus if eligible for founder rewards', async function () {
      await mockFoundingEvent.setDeposit(accounts[0].address, 555555);
      await mockFoundingEvent.setGenesisBlock(5);
      await treasury.claimFounderRewards();
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [1111111111]);
      await treasury.approvePosters([accounts[0].address]);
      const tx = treasury.connect(accounts[0]).claimPosterRewards();
      await expect(tx).not.to.be.reverted;
      (await tx).wait();
      expect((await treasury.founders(accounts[0].address))[0]).to.be.below(555555);
    });
    it('Fails if called by not poster or poster with 0', async function () {
      await expect(treasury.claimPosterRewards()).to.be.reverted;
    });
  });

  describe('claimPosterRewardsFor()', function () {
    it('Gets poster rewards if called for eligible', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], [1111111111]);
      await treasury.approvePosters([accounts[1].address]);
      const tx = treasury.connect(accounts[0]).claimPosterRewardsFor([accounts[1].address]);
      await expect(tx).not.to.be.reverted;
    });

    it('Fails if called for not eligible', async function () {
      await expect(treasury.claimPosterRewardsFor([accounts[1].address])).to.be.reverted;
    });
  });

  describe('posterRewardsAvailable()', function () {
    it('Returns rewards available for eligible', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], [91111111111111]);
      await treasury.approvePosters([accounts[1].address]);
      await mine(1);
      const posterRewardsAvailable = await treasury.posterRewardsAvailable(accounts[1].address);
      await expect(posterRewardsAvailable).to.be.above(0);
    });
    it('Returns 0 if called for not eligible', async function () {
      const posterRewardsAvailable = await treasury.posterRewardsAvailable(accounts[1].address);
      expect(posterRewardsAvailable).to.equal(0);
    });
  });

  describe('claimFounderRewards()', function () {
    it('Gets founder rewards if called by founder', async function () {
      await mockFoundingEvent.setDeposit(accounts[0].address, 5);
      const tx = treasury.claimFounderRewards();
      await expect(tx).not.to.be.reverted;
    });
    it('Fails if called by not founder', async function () {
      await expect(treasury.connect(accounts[1]).claimFounderRewards()).to.be.reverted;
    });
    it('Fails if foundingEvent hasnt concluded', async function () {
      await mockFoundingEvent.setDeposit(accounts[0].address, 5);
      await mockFoundingEvent.setGenesisBlock(0);
      const tx = treasury.claimFounderRewards();
      await expect(tx).to.be.reverted;
    });
  });

  describe('claimFounderRewardsFor()', function () {
    it('Gets founder rewards if called for founders', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, 5);
      const tx = treasury.claimFounderRewardsFor([accounts[1].address]);
      await expect(tx).not.to.be.reverted;
    });
    it('Fails if called for not founders', async function () {
      await expect(treasury.claimFounderRewardsFor([accounts[1].address])).to.be.reverted;
    });
    it('Fails if foundingEvent hasnt concluded', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, 5);
      await mockFoundingEvent.setGenesisBlock(0);
      const tx = treasury.claimFounderRewardsFor([accounts[1].address]);
      await expect(tx).to.be.reverted;
    });
  });

  describe('getRate()', function () {
    it('Returns current emission rate', async function () {
      const rateReturned = await treasury.getRate();
      await expect(rateReturned).to.be.above(0);
    });
    it('Emission rate approaches 0 as time goes', async function () {
      await mine('0xffffffffffffffffffffffffffffffffffffffffffff');
      const rateReturned = await treasury.getRate();
      await expect(rateReturned).to.equal(0);
    });
    it('Emission rate approaches 0 as price increases', async function () {
      const stableCoin = (await treasury.ab()).stableCoin;
      const letToken = (await treasury.ab()).letToken;
      const letSize = ethers.BigNumber.from(stableCoin);
      const stableCoinSize = ethers.BigNumber.from(letToken);
      const token0 = letSize.gt(stableCoinSize) ? stableCoin : letToken;
      if (letToken == token0) {
        await mockPool.setReserves("999999999999999999999999999999999", 50);
      } else {
        await mockPool.setReserves(50, "999999999999999999999999999999999");
      }
      const rateReturned = await treasury.getRate();
      await expect(rateReturned).to.equal(0);
    });
    it('If the price is below 1 USD, it is ignored in emission rate formula', async function () {
      const stableCoin = (await treasury.ab()).stableCoin;
      const letToken = (await treasury.ab()).letToken;
      const letSize = ethers.BigNumber.from(stableCoin);
      const stableCoinSize = ethers.BigNumber.from(letToken);
      const token0 = letSize.gt(stableCoinSize) ? stableCoin : letToken;
      if (letToken == token0) {
        await mockPool.setReserves(5, 5000);
      } else {
        await mockPool.setReserves(5000, 5);
      }
      const tr = treasury;
      const rateReturned = await treasury.getRate();
      await mockPool.setReserves(5000, 5000);
      const rateReturned1 = await treasury.getRate();
      await expect(rateReturned).to.be.closeTo(rateReturned1, 5555500); // a bit of time passed
    });
  });
});

describe('TREASURY UNIT TESTS: DOUBLE CLAIM IN ONE BLOCK.\n', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, WETH, DAI, accounts, foundingEvent, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider] = await loadFixture(
      treasuryInitializedFixture
    );
  });
  it('claimBenRewards() fails if called second time in one block by the same beneficiary', async function () {
    await treasury.connect(accounts[0]).addBeneficiary(accounts[0].address, 555555555555555, 5555555);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimBenRewards();
    await treasury.claimBenRewards();
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimAirdrop() fails if called second time in one block by the same eligible', async function () {
    await treasury.addAirdropBulk([accounts[0].address], [5555556666666666]);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimAirdrop();
    await treasury.claimAirdrop();
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimAirdropFor() fails if called second time in one block for the same eligible', async function () {
    await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimAirdropFor([accounts[1].address]);
    await treasury.claimAirdropFor([accounts[1].address]);
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimPosterRewards() fails if called second time in one block by the same eligible', async function () {
    await treasury.connect(accounts[10]).addPosters([accounts[0].address], ['11111111111111111111']);
    await treasury.approvePosters([accounts[0].address]);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.connect(accounts[0]).claimPosterRewards();
    await treasury.claimPosterRewards();
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimPosterRewardsFor() fails if called second time in one block for the same eligible', async function () {
    await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['11111111111111111']);
    await treasury.approvePosters([accounts[1].address]);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimPosterRewardsFor([accounts[1].address]);
    await treasury.claimPosterRewardsFor([accounts[1].address]);
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimFounderRewards() fails if called second time in one block by the same founder', async function () {
    await mockFoundingEvent.setDeposit(accounts[0].address, 5);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimFounderRewards();
    await treasury.claimFounderRewards();
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
  it('claimFounderRewardsFor() fails if called second time in one block for the same founder', async function () {
    await mockFoundingEvent.setDeposit(accounts[1].address, 5);
    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.claimFounderRewardsFor([accounts[1].address]);
    await treasury.claimFounderRewardsFor([accounts[1].address]);
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });
});
