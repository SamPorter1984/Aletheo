const { expect } = require('chai');
const { loadFixture, time, mine } = require('@nomicfoundation/hardhat-network-helpers');
const { treasuryInitializedFixture, treasuryMockWithLowBalanceFixture } = require('./fixtures/treasuryFixtures.js');
let { ethers } = require('hardhat');
const { cc } = require('./constants.js');

let provider = ethers.provider;
let treasury,
  eerc20,
  foundingEvent,
  staking,
  wbnb,
  mockFactory,
  mockPool,
  mockFoundingEvent,
  mockRouter,
  busd = {},
  accounts = [];

describe('TREASURY UNIT TESTS', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider] = await loadFixture(
      treasuryInitializedFixture
    );
    staking = accounts[11];
  });
  describe('init()', function () {
    it('Initializes state variables correctly', async function () {
      expect(await treasury.posterRate(), 'unexpected posterRate').to.equal(1000);
      expect(await treasury.baseRate(), 'unexpected baseRate').to.equal(ethers.BigNumber.from('950000000000000000000000000000000000'));
      const ab = await treasury._ab();
      expect(await ab.governance, 'unexpected governance').to.equal(accounts[0].address);
      expect(await ab.letToken, 'unexpected letToken').to.equal(eerc20.address);
      expect(await ab.foundingEvent, 'unexpected foundingEvent').to.equal(mockFoundingEvent.address);
      expect(await ab.factory, 'unexpected factory').to.equal(mockFactory.address);
      expect(await ab.stableCoin, 'unexpected stableCoin').to.equal(busd.address);
      expect(await ab.staking, 'unexpected staking').to.equal(staking.address);
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
      const arg = ethers.BigNumber.from('30000000000000');
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

  describe('getStakingRewards()', function () {
    it('Gets staking rewards if called by staking', async function () {
      const initial = await eerc20.balanceOf(accounts[0].address);
      await expect(treasury.connect(accounts[11]).getStakingRewards(accounts[0].address, 15)).not.to.be.reverted;
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected let balance').to.equal(initial.add(15));
    });
    it('Fails if called by not staking', async function () {
      await expect(treasury.getStakingRewards(accounts[0].address, 15)).to.be.reverted;
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
    it('Sends gas instead if poster balance is below 1e17', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[0].address], [1111111111]);
      await treasury.approvePosters([accounts[0].address]);
      const balanceBeforeSpending = await provider.getBalance(accounts[0].address);
      if (balanceBeforeSpending.gt(100000000000000000n)) {
        const toSpend = balanceBeforeSpending.sub(100000000000000000n);
        await accounts[0].sendTransaction({
          to: mockRouter.address,
          value: toSpend,
        });
      }
      const initialETHBalance = await provider.getBalance(accounts[0].address);
      const tx = treasury.connect(accounts[0]).claimPosterRewards();
      await expect(tx).not.to.be.reverted;
      (await tx).wait();
      expect(initialETHBalance).to.be.below(await provider.getBalance(accounts[0].address));
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
    it('Sends gas instead if poster balance is below 1e17', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], [11111111111111]);
      await treasury.approvePosters([accounts[1].address]);
      const balanceBeforeSpending = await provider.getBalance(accounts[1].address);
      if (balanceBeforeSpending.gt(100000000000000000n)) {
        const toSpend = balanceBeforeSpending.sub(100000000000000000n);
        await accounts[1].sendTransaction({
          to: mockRouter.address,
          value: toSpend,
        });
      }
      const initialETHBalance = await provider.getBalance(accounts[1].address);
      const tx = treasury.connect(accounts[0]).claimPosterRewardsFor([accounts[1].address]);
      await expect(tx).not.to.be.reverted;
      await (await tx).wait();
      expect(initialETHBalance).to.be.below(await provider.getBalance(accounts[1].address));
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
  /*
  describe('claimPosterRewardsWithSignature()', function () {
    const chainId = 31337;
    const DOMAIN_TYPEHASH = ethers.utils.solidityKeccak256(['string'], ['EIP712Domain(string name,uint256 chainId,address verifyingContract)']);

    it('Gets poster rewards if called with signature of eligible', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1999000000000000000000']);

      await treasury.approvePosters([accounts[1].address]);
      await mine(172800);
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
      );
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', accounts[1].address]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[1].signMessage(ethers.utils.arrayify(message));
      const tx = await treasury.connect(accounts[0]).claimPosterRewardsWithSignature(accounts[1].address, signature);
      await expect(tx).not.to.be.reverted;
    });
    it('Sends gas instead if signatory balance is below 1e17', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1999000000000000000000']);

      await treasury.approvePosters([accounts[1].address]);
      await mine(172800);
      const balanceBeforeSpending = await provider.getBalance(accounts[1].address);
      if (balanceBeforeSpending.gt(100000000000000000n)) {
        const toSpend = balanceBeforeSpending.sub(100000000000000000n);
        await accounts[1].sendTransaction({
          to: mockRouter.address,
          value: toSpend,
        });
      }
      const initialETHBalance = await provider.getBalance(accounts[1].address);
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
      );
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', accounts[1].address]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[1].signMessage(ethers.utils.arrayify(message));
      const tx = await treasury.connect(accounts[0]).claimPosterRewardsWithSignature(accounts[1].address, signature);
      await expect(tx).not.to.be.reverted;
      await (await tx).wait();
      expect(initialETHBalance).to.be.below(await provider.getBalance(accounts[1].address));
    });
    it('Fails if signatory is not eligible', async function () {
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
      );
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', accounts[1].address]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[1].signMessage(ethers.utils.arrayify(message));
      const tx = treasury.connect(accounts[0]).claimPosterRewardsWithSignature(accounts[1].address, signature);
      await expect(tx).to.be.reverted;
    });
    it('Fails if signature is invalid', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], [1111111111]);
      await treasury.approvePosters([accounts[1].address]);
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', ethers.constants.AddressZero]
      );
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', accounts[1].address]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[1].signMessage(ethers.utils.arrayify(message));
      const tx = treasury.connect(accounts[0]).claimPosterRewardsWithSignature(accounts[1].address, signature);
      await expect(tx).to.be.reverted;
    });
  });
*/
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
      const stableCoin = (await treasury._ab()).stableCoin;
      const letToken = (await treasury._ab()).letToken;
      const letSize = ethers.BigNumber.from(stableCoin);
      const stableCoinSize = ethers.BigNumber.from(letToken);
      const token0 = letSize.gt(stableCoinSize) ? stableCoin : letToken;
      if (letToken == token0) {
        await mockPool.setReserves('99999999999999999999999999999999', 5);
      } else {
        await mockPool.setReserves(5, '99999999999999999999999999999999');
      }
      const rateReturned = await treasury.getRate();
      await expect(rateReturned).to.equal(0);
    });
    it('If the price is below 1 USD, it is ignored in emission rate formula', async function () {
      const stableCoin = (await treasury._ab()).stableCoin;
      const letToken = (await treasury._ab()).letToken;
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
      await expect(rateReturned).to.be.closeTo(rateReturned1, 2500); // a bit of time passed
    });
  });

  describe('reserveForOTC()', function () {
    it('Reserves founder shares if called by otcMarket', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111111111111111111111155555555555');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 0);
      expect((await treasury.founders(accounts[1].address)).reserved).to.equal(111111);
    });
    it('Reserves poster unclamed rewards if called by otcMarket', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 1);
      expect((await treasury.posters(accounts[1].address)).reserved).to.equal(111111);
    });
    it('Reserves unclamed airdrop if called by otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 2);
      expect((await treasury.airdrops(accounts[1].address)).reserved).to.equal(111111);
    });
    it('Fails to reserve founder shares if argument exceeds free amount', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      const tx = treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '91111111111', 0);
      await expect(tx).to.be.reverted;
    });
    it('Fails to reserve poster unclamed rewards if argument exceeds free amount', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      const tx = treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '9111111111111111559', 1);
      await expect(tx).to.be.reverted;
    });
    it('Fails to reserve unclamed airdrop if argument exceeds free amount', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      const tx = treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 8555556666666669, 2);
      await expect(tx).to.be.reverted;
    });
    it('Reverts if called by not otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      const tx = treasury.connect(accounts[0]).reserveForOTC(accounts[1].address, 866669, 2);
      await expect(tx).to.be.reverted;
    });
  });
  /*
  describe('withdrawFromOTC()', function () {
    it('Withdraws founder shares if called by otcMarket', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111111111111111111111155555555555');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 0);
      expect((await treasury.founders(accounts[1].address)).reserved).to.equal(111111);
      await treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, 111111, 0);
      expect((await treasury.founders(accounts[1].address)).reserved).to.equal(0);
    });
    it('Withdraws poster unclamed rewards if called by otcMarket', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 1);
      expect((await treasury.posters(accounts[1].address)).reserved).to.equal(111111);
      await treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, 111111, 1);
      expect((await treasury.posters(accounts[1].address)).reserved).to.equal(0);
    });
    it('Withdraws unclamed airdrop if called by otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 2);
      expect((await treasury.airdrops(accounts[1].address)).reserved).to.equal(111111);
      await treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, 111111, 2);
      expect((await treasury.airdrops(accounts[1].address)).reserved).to.equal(0);
    });
    it('Fails to withdraw founder shares if argument exceeds reserved amount', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111111111111111111111155555555555');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '11111111111111111111115555555555', 0);
      const tx = treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, '911111111111111111111155555555555', 0);
      await expect(tx).to.be.reverted;
    });
    it('Fails to withdraw poster unclamed rewards if argument exceeds reserved amount', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '1111111111111111555', 1);
      const tx = treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, '9111111111111111559', 1);
      await expect(tx).to.be.reverted;
    });
    it('Fails to withdraw unclamed airdrop if argument exceeds reserved amount', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 5555556666666666, 2);
      const tx = treasury.connect(accounts[11]).withdrawFromOTC(accounts[1].address, '9555556666666669', 2);
      await expect(tx).to.be.reverted;
    });
    it('Reverts if called by not otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 866669, 2);
      const tx = treasury.connect(accounts[0]).withdrawFromOTC(accounts[1].address, 866669, 2);
      await expect(tx).to.be.reverted;
    });
  });
*/
  describe('reassignOTCShare()', function () {
    it('Reassigns founder shares if called by otcMarket', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111111111111111111111155555555555');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      const initialAmount = (await treasury.founders(accounts[1].address)).amount;
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 0);
      await treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, 111111, 0);
      expect((await treasury.founders(accounts[1].address)).reserved).to.equal(0);
      expect((await treasury.founders(accounts[1].address)).amount).to.equal(initialAmount.sub(111111));
      expect((await treasury.founders(accounts[0].address)).amount).to.equal(111111);
      const blockNumber = (await provider.getBlock('latest')).number;
      expect((await treasury.founders(accounts[0].address)).lastClaim).to.equal(blockNumber);
    });
    it('Reassigns poster unclamed rewards if called by otcMarket', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      const initialAmount = (await treasury.posters(accounts[1].address)).amount;
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 1);
      await treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, 111111, 1);
      expect((await treasury.posters(accounts[1].address)).reserved).to.equal(0);
      expect((await treasury.posters(accounts[1].address)).amount).to.equal(initialAmount.sub(111111));
      expect((await treasury.posters(accounts[0].address)).amount).to.equal(111111);
      const blockNumber = (await provider.getBlock('latest')).number;
      expect((await treasury.posters(accounts[0].address)).lastClaim).to.equal(blockNumber);
    });
    it('Reassigns unclamed airdrop if called by otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      const initialAmount = (await treasury.airdrops(accounts[1].address)).amount;
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 111111, 2);
      expect((await treasury.airdrops(accounts[1].address)).reserved).to.equal(111111);
      await treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, 111111, 2);
      expect((await treasury.airdrops(accounts[1].address)).reserved).to.equal(0);
      expect((await treasury.airdrops(accounts[1].address)).amount).to.equal(initialAmount.sub(111111));
      expect((await treasury.airdrops(accounts[0].address)).amount).to.equal(111111);
      const blockNumber = (await provider.getBlock('latest')).number;
      expect((await treasury.airdrops(accounts[0].address)).lastClaim).to.equal(blockNumber);
    });
    it('Fails to reassign founder shares if argument exceeds reserved amount', async function () {
      await mockFoundingEvent.setDeposit(accounts[1].address, '111111111111111111111');
      await treasury.claimFounderRewardsFor([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '11111111111111111', 0);
      const tx = treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, '911111111111111111111', 0);
      await expect(tx).to.be.reverted;
    });
    it('Fails to reassign poster unclamed rewards if argument exceeds reserved amount', async function () {
      await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['1111111111111111555']);
      await treasury.approvePosters([accounts[1].address]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, '1111111111111111555', 1);
      const tx = treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, '9111111111111111555', 1);
      await expect(tx).to.be.reverted;
    });
    it('Fails to reassign unclamed airdrop if argument exceeds reserved amount', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 5555556666666666, 2);
      const tx = treasury.connect(accounts[11]).reassignOTCShare(accounts[1].address, accounts[0].address, '9555556666666669', 2);
      await expect(tx).to.be.reverted;
    });
    it('Reverts if called by not otcMarket', async function () {
      await treasury.addAirdropBulk([accounts[1].address], [5555556666666666]);
      await treasury.connect(accounts[11]).reserveForOTC(accounts[1].address, 866669, 2);
      const tx = treasury.connect(accounts[0]).reassignOTCShare(accounts[1].address, accounts[0].address, 866669, 2);
      await expect(tx).to.be.reverted;
    });
  });
});

describe('TREASURY UNIT TESTS: DOUBLE CLAIM IN ONE BLOCK.\n', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider] = await loadFixture(
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
  /*  it('claimPosterRewardsWithSignature() fails if called second time in one block for the same signatory', async function () {
    const chainId = 31337;
    const DOMAIN_TYPEHASH = ethers.utils.solidityKeccak256(['string'], ['EIP712Domain(string name,uint256 chainId,address verifyingContract)']);

    await treasury.connect(accounts[10]).addPosters([accounts[1].address], ['11111111111111111']);
    await treasury.approvePosters([accounts[1].address]);
    await mine(172800);
    const domainSeparator = ethers.utils.solidityKeccak256(
      ['bytes32', 'uint', 'string', 'address'],
      [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
    );
    const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', accounts[1].address]);
    const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
    const signature = await accounts[1].signMessage(ethers.utils.arrayify(message));

    await provider.send('evm_setAutomine', [false]);
    const tx = await treasury.connect(accounts[0]).claimPosterRewardsWithSignature(accounts[1].address, signature);
    await treasury.claimPosterRewardsWithSignature(accounts[1].address, signature);
    await mine(1);
    const receipt = await tx.wait();
    const latestBlock = await provider.getBlock(receipt.blockNumber);
    expect(receipt.status).to.equal(1);
    const failedHash = latestBlock.transactions[1] != receipt.transactionHash ? latestBlock.transactions[1] : latestBlock.transactions[0];
    const failedTrace = await provider.send('debug_traceTransaction', [failedHash]);
    expect(failedTrace.failed).to.be.equal(true);
    await provider.send('evm_setAutomine', [true]);
  });*/
});

// treasury will probably be able to mint, but it's unclear how so far

/*describe.only('Treasury low on balance', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, mockFactory, mockPool, mockFoundingEvent, mockRouter, provider] = await loadFixture(
      treasuryMockWithLowBalanceFixture
    );
    staking = accounts[10];
  });
  it('getStakingRewards() fails if treasury has not enough funds', async function () {
    await expect(treasury.connect(staking).getStakingRewards(accounts[0].address, 1500000000000)).to.be.reverted;
  });
  it('claimBenRewards() fails if treasury has not enough funds', async function () {
    await treasury.connect(accounts[0]).addBeneficiary(accounts[0].address, '111111111111555555', '11111111111115555555');
    const tx = treasury.connect(accounts[0]).claimBenRewards();
    await expect(tx).to.be.reverted;
  });
  it('claimAirdrop() fails if treasury has not enough funds', async function () {
    await treasury.addAirdropBulk([accounts[0].address], [5555556666666666]);
    const tx = treasury.connect(accounts[0]).claimAirdrop();
    await expect(tx).to.be.reverted;
  });
  it('claimAirdropFor() fails if treasury has not enough funds', async function () {
    await treasury.addAirdropBulk([accounts[0].address], [5555556666666666]);
    const tx = treasury.connect(accounts[0]).claimAirdropFor([accounts[0].address]);
    await expect(tx).to.be.reverted;
  });
  it('claimPosterRewards() fails if treasury has not enough funds', async function () {
    await treasury.connect(accounts[10]).addPosters([accounts[0].address], ['11111111111111111111']);
    await treasury.approvePosters([accounts[0].address]);
    const tx = treasury.claimPosterRewards();
    await expect(tx).to.be.reverted;
  });
  it('claimPosterRewardsFor() fails if treasury has not enough funds', async function () {
    await treasury.connect(accounts[10]).addPosters([accounts[0].address], ['11111111111111111111']);
    await treasury.approvePosters([accounts[0].address]);
    const tx = treasury.claimPosterRewardsFor([accounts[0].address]);
    await expect(tx).to.be.reverted;
  });
});*/
