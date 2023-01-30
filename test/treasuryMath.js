const { expect } = require('chai');
const { loadFixture, mine, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { treasuryWithUniswapAndFoundingEventNotConcludedFixture } = require('./fixtures/treasuryFixtures.js');
const { ethers } = require('hardhat');
const { ONE, TEN_MILLION, cc } = require('./constants.js');
const {
  tcJSON,
  createTestCase,
  getAmountOut,
  calculateLetAmountInToken,
  calculateRateLocally,
  calculateAirdropAvailable,
  calculatePosterRewardsAvailable,
  calculatePosterRewardsWithBonus,
  calculateFounderRewardsAvailable,
} = require('./utils.js');

const ITERATIONS = 10;

const provider = ethers.provider;
let treasury = {},
  eerc20 = {},
  wbnb = {},
  busd = {},
  foundingEvent = {},
  staking = {},
  router = {},
  factory = {},
  letBNBpool = {},
  pool = {},
  bnbBUSDPool = {},
  accounts = [];

describe('TREASURY RANDOMIZED MATH TESTS', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, router, factory, bnbBUSDPool] = await loadFixture(
      treasuryWithUniswapAndFoundingEventNotConcludedFixture
    );
    await setBalance(accounts[0].address, ethers.utils.parseEther(TEN_MILLION));
    let toDeposit = ethers.BigNumber.from(ONE).mul('49999');
    await foundingEvent.connect(accounts[0]).depositBNB({ value: toDeposit });
    await foundingEvent.connect(accounts[0]).triggerLaunch();
    pool = await (await ethers.getContractFactory('UniswapV2Pair')).connect(accounts[19]).deploy();
    const poolAddress = await factory.getPair(wbnb.address, eerc20.address);
    letBNBpool = await pool.attach(poolAddress);
  });

  describe('getRate()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations getRate()', async function g() {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 20);
        const nAddress = accounts[n].address;
        const randBlocks = Math.floor(Math.random() * 100000000);
        const randAmount = ethers.BigNumber.from(Math.floor(Math.random() * 10000000 + 1))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 10000000)))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 20000))); ///+0000 for max
        await setBalance(nAddress, ethers.utils.parseEther(TEN_MILLION));
        await mine(randBlocks);
        const baseDeposit = randAmount;
        const mod = 10;
        let toDeposit = baseDeposit.div(mod);
        let trade = 0;
        while (trade < 9) {
          await router.swapExactETHForTokens(0, [wbnb.address, eerc20.address], nAddress, ethers.constants.MaxUint256, { value: toDeposit });
          const rand = Math.floor(Math.random() * 2) + 2;
          toDeposit = toDeposit.mul(9).div(10);
          toDeposit = toDeposit.div(rand);
          const rate = await treasuryUtils.calculateRateLocally();
          const rateReturned = await treasury.getRate();
          const tc = createTestCase({ i, n, nAddress, randBlocks, randAmount, baseDeposit, mod, toDeposit, trade, rand, rate, rateReturned });
          expect(rateReturned, 'rates dont match. Failed test case:\n' + tcJSON(tc)).to.equal(rate);
          trade++;
        }
      }
    });
  });

  describe('claimBenRewards()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimBenRewards()', async function () {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 20);
        const nAddress = accounts[n].address;
        const randBlocks = Math.floor(Math.random() * 1000);
        const randAmount = ethers.BigNumber.from(Math.floor(Math.random() * 1000000000 + 1));
        const randEmission = ethers.BigNumber.from(Math.floor(Math.random() * 1000000000 + 1));
        await treasury.connect(accounts[0]).addBeneficiary(nAddress, randAmount, randEmission);
        await mine(randBlocks);
        const initial = await eerc20.balanceOf(nAddress);
        const lastClaim = (await treasury.bens(nAddress)).lastClaim;
        const amount = (await treasury.bens(nAddress)).amount;
        const rate = await treasuryUtils.calculateRateLocally(1);
        const totalBenEmission = await treasury.totBenEmission();
        const benRate = rate.mul(randEmission).div(totalBenEmission);
        const blockNumber = await provider.getBlockNumber();
        const blocksPassed = ethers.BigNumber.from(blockNumber).add(1).sub(lastClaim);
        let toClaim = blocksPassed.mul(benRate);
        const treasuryBalance = await eerc20.balanceOf(treasury.address);
        const smaller = treasuryBalance.gt(amount) ? amount : treasuryBalance;
        toClaim = toClaim.gt(smaller) ? smaller : toClaim;
        const tx = treasury.connect(accounts[n]).claimBenRewards();

        const tc = createTestCase({
          i,
          n,
          nAddress,
          randBlocks,
          randAmount,
          randEmission,
          initial,
          lastClaim,
          amount,
          rate,
          totalBenEmission,
          benRate,
          blockNumber,
          blocksPassed,
          treasuryBalance,
          smaller,
          //tx,
        });

        await expect(tx, 'claimBenRewards() failed for beneficiary.').not.to.be.reverted;
        const receipt = await (await tx).wait();
        expect(
          ethers.BigNumber.from(await eerc20.balanceOf(nAddress)).sub(initial),
          'unexpected beneficiary balance after rewards claiming.' + tcJSON(tc)
        ).to.equal(toClaim);
        currentAmount = (await treasury.bens(nAddress)).amount;
        expect(toClaim, 'unexpected bens[accounts[' + n + '].address].amount standing after rewards claiming.' + tcJSON(tc)).to.equal(
          amount.sub(currentAmount)
        );
        expect(receipt.blockNumber, 'unexpected bens[accounts[' + n + '].address].lastClaim after rewards claiming.' + tcJSON(tc)).to.equal(
          (await treasury.bens(nAddress)).lastClaim
        );
      }
    });
    it('Reverts if not beneficiary', async () => {
      await expect(treasury.connect(accounts[1]).claimBenRewards()).to.be.reverted;
    });
  });

  describe('airdropAvailable()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for airdropAvailable()', async function () {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 20);
        const nAddress = accounts[n].address;
        const randBlocks = Math.floor(Math.random() * 100000000);
        const randAmount = ethers.BigNumber.from(Math.floor(Math.random() * 10000000 + 1))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 10000000)))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 20000))); ///+0000 for max
        await treasury.addAirdropBulk([nAddress], [randAmount]);
        const toClaimOrNotToClaim = Math.floor(Math.random() * 2);
        if (toClaimOrNotToClaim == 1) {
          await treasury.connect(accounts[n]).claimAirdrop();
        }
        await mine(randBlocks);
        const airdropAvailableReturned = (await treasury.airdropAvailable(nAddress))[0];
        const airdropAvailable = await treasuryUtils.calculateAirdropAvailable(n, 0);
        const tc = createTestCase({ i, n, nAddress, randBlocks, randAmount, toClaimOrNotToClaim, airdropAvailableReturned, airdropAvailable });
        expect(airdropAvailableReturned, tcJSON(tc)).to.equal(airdropAvailable);
      }
    });
  });

  describe('claimAirdrop()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimAirdrop(). Claims airdrop of 1 token on first claim', async function () {
      await claimTest('claimAirdrop', false, iterations);
    });
    it(iterations + ' random iterations for claimAirdrop(). Claims according to emission on consequent claims', async function () {
      await claimTest('claimAirdrop', false, iterations, true);
    });
    it('Reverts if not eligible for airdrop', async () => {
      await expect(treasury.connect(accounts[1]).claimAirdrop()).to.be.reverted;
    });
    it('Deletes airdrop record if all airdrop was claimed', async () => {
      await claimTest('claimAirdrop', false, iterations, false, true);
    });
  });

  describe('claimAirdropFor(address[])', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimAirdropFor([]). Claims airdrop of 1 token on first claim', async function () {
      await claimTest('claimAirdropFor', true, iterations);
    });

    it(iterations + ' random iterations for claimAirdropFor([]). Claims airdrop according to emission on consequent claims', async function () {
      await claimTest('claimAirdropFor', true, iterations, true);
    });
    it('Reverts if not eligible for airdrop', async () => {
      await expect(treasury.connect(accounts[1]).claimAirdrop()).to.be.reverted;
    });
    it('Deletes airdrop record if all airdrop was claimed', async () => {
      await claimTest('claimAirdropFor', true, iterations, false, true);
    });
  });

  describe('posterRewardsAvailable()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for posterRewardsAvailable()', async function () {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 20);
        const nAddress = accounts[n].address;
        const randBlocks = Math.floor(Math.random() * 100000000);
        const randAmount = ethers.BigNumber.from(Math.floor(Math.random() * 10000000 + 1))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 10000000)))
          .mul(ethers.BigNumber.from(Math.floor(Math.random() * 20000000)));
        await treasury.connect(accounts[10]).addPosters([nAddress], [randAmount]);
        await treasury.approvePosters([nAddress]);
        await mine(randBlocks);
        const posterRewardsAvailableReturned = await treasury.posterRewardsAvailable(nAddress);
        const posterRewardsAvailableLocal = await treasuryUtils.calculatePosterRewardsAvailable(n);
        const tc = createTestCase({ i, n, nAddress, randBlocks, randAmount, posterRewardsAvailableReturned, posterRewardsAvailableLocal });
        expect(posterRewardsAvailableReturned, tcJSON(tc)).to.equal(posterRewardsAvailableLocal);
      }
    });
  });

  describe('claimPosterRewards()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimPosterRewards()', async function () {
      await claimTest('claimPosterRewards', false, iterations);
    });

    it(iterations + " random iterations for claimPosterRewards when poster' balance is low(sends gas back instead of tokens)", async function () {
      await claimTest('claimPosterRewards', false, iterations, false, false, true);
    });
    it('Reverts if not eligible for poster rewards', async () => {
      await expect(treasury.connect(accounts[1]).claimPosterRewards()).to.be.reverted;
    });
  });

  describe('claimPosterRewardsFor(address[])', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimPosterRewardsFor()', async function () {
      await claimTest('claimPosterRewardsFor', true, iterations);
    });
    it(iterations + " random iterations for claimPosterRewardsFor when poster' balance is low(sends gas back instead of tokens)", async function () {
      await claimTest('claimPosterRewardsFor', true, iterations, false, false, true);
    });
    it('Reverts if not eligible for poster rewards', async () => {
      await expect(treasury.connect(accounts[0]).claimPosterRewardsFor([accounts[0].address])).to.be.reverted;
    });
  });
  /*
  describe('claimPosterRewardsWithSignature()', function () {
    const iterations = 0 + ITERATIONS;
    const chainId = 31337;
    const DOMAIN_TYPEHASH = ethers.utils.solidityKeccak256(['string'], ['EIP712Domain(string name,uint256 chainId,address verifyingContract)']);
    it(iterations + ' random iterations for claimPosterRewardsWithSignature()', async function () {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 19);
        const nAddress = accounts[n].address;
        const signer = accounts[Math.floor(Math.random() * 19)];
        await treasury.connect(accounts[10]).addPosters([nAddress], ['11111111111111111']);
        await treasury.approvePosters([nAddress]);
        await mine(172800);
        const domainSeparator = ethers.utils.solidityKeccak256(
          ['bytes32', 'uint', 'string', 'address'],
          [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
        );
        const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', nAddress]);
        const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
        const signature = await accounts[n].signMessage(ethers.utils.arrayify(message));
        const tx = await treasury.connect(signer).claimPosterRewardsWithSignature(nAddress, signature);
        const receipt = await tx.wait();
        const tc = createTestCase({ i, n, nAddress, signer, domainSeparator, hashStruct, message, signature, tx, receipt });
        expect(receipt.status, tcJSON(tc)).to.equal(1);
      }
    });
    it('Reverts if not eligible for poster rewards', async () => {
      const nAddress = accounts[0].address;
      const signer = accounts[Math.floor(Math.random() * 19)];
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'claimPosterRewardsWithSignature()', treasury.address]
      );
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', nAddress]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[0].signMessage(ethers.utils.arrayify(message));

      const tc = createTestCase({ nAddress, signer, domainSeparator, hashStruct, message, signature });
      await expect(treasury.connect(signer).claimPosterRewardsWithSignature(nAddress, signature), tcJSON(tc)).to.be.reverted;
    });
    it('Reverts if recovered signer address and passed arg address dont match or signature is invalid', async () => {
      const nAddress = accounts[0].address;
      const signer = accounts[Math.floor(Math.random() * 19)];
      const domainSeparator = ethers.utils.solidityKeccak256(
        ['bytes32', 'uint', 'string', 'address'],
        [DOMAIN_TYPEHASH, chainId, 'INVALID_STRING', treasury.address]
      );
      await treasury.connect(accounts[10]).addPosters([nAddress], [1]);
      await treasury.approvePosters([nAddress]);
      const hashStruct = ethers.utils.solidityKeccak256(['string', 'address'], ['Aletheo 1000 EOY', nAddress]);
      const message = ethers.utils.solidityKeccak256(['bytes32', 'bytes32'], [domainSeparator, hashStruct]);
      const signature = await accounts[0].signMessage(ethers.utils.arrayify(message));

      const tc = createTestCase({ nAddress, signer, domainSeparator, hashStruct, message, signature });
      await expect(treasury.connect(signer).claimPosterRewardsWithSignature(nAddress, signature), tcJSON(tc)).to.be.reverted;
    });
  });*/
});

describe('TREASURY Founders', function () {
  beforeEach('deploy fixture', async () => {
    [treasury, eerc20, wbnb, busd, accounts, foundingEvent, staking, router, factory, bnbBUSDPool] = await loadFixture(
      treasuryWithUniswapAndFoundingEventNotConcludedFixture
    );
    for (let i = 0; i < accounts.length - 1; i++) {
      await setBalance(accounts[i].address, ethers.utils.parseEther(TEN_MILLION));
      // prettier-ignore
      const toDeposit = ethers.BigNumber.from(ONE).mul('' + (Math.floor(Math.random() * 20 + 30)));
      await foundingEvent.connect(accounts[i]).depositBNB({ value: toDeposit });
    }
    await foundingEvent.connect(accounts[0]).triggerLaunch();
    pool = await (await ethers.getContractFactory('UniswapV2Pair')).connect(accounts[19]).deploy();
    const poolAddress = await factory.getPair(wbnb.address, eerc20.address);
    letBNBpool = await pool.attach(poolAddress);
  });

  describe('founderRewardsAvailable()', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for founderRewardsAvailable()', async function () {
      for (let i = 0; i < iterations; i++) {
        const n = Math.floor(Math.random() * 19);
        const nAddress = accounts[n].address;
        const randBlocks = Math.floor(Math.random() * 100000000);
        const toClaimOrNotToClaim = Math.floor(Math.random() * 2);
        if (toClaimOrNotToClaim == 1) {
          await treasury.connect(accounts[n]).claimFounderRewards();
        }
        await mine(randBlocks);
        const rewardsAvailableReturned = await treasury.founderRewardsAvailable(nAddress);
        const rewardsAvailable = await treasuryUtils.calculateFounderRewardsAvailable(n, 0);
        const tc = createTestCase({ i, n, nAddress, randBlocks, rewardsAvailableReturned, rewardsAvailable });
        expect(rewardsAvailableReturned, tcJSON(tc)).to.equal(rewardsAvailable);
      }
    });
  });

  describe('claimFounderRewards()', async function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimFounderRewards()', async function () {
      await claimTest('claimFounderRewards', false, iterations);
    });
    it('reverts if not founder', async function () {
      await expect(treasury.connect(accounts[19]).claimFounderRewards()).to.be.reverted;
    });
  });
  describe('claimFounderRewardsFor(address[])', function () {
    const iterations = 0 + ITERATIONS;
    it(iterations + ' random iterations for claimFounderRewardsFor()', async function () {
      await claimTest('claimFounderRewardsFor', true, iterations);
    });
    it('reverts if not founder', async function () {
      await expect(treasury.connect(accounts[0]).claimFounderRewardsFor([accounts[19].address])).to.be.reverted;
    });
  });
});

const treasuryUtils = {
  getAmountOut: async (amountIn, tkn) => {
    return getAmountOut(amountIn, tkn, { eerc20, letBNBpool });
  },
  calculateLetAmountInToken: async (stringValue, tkn) => {
    return calculateLetAmountInToken(stringValue, tkn, { eerc20, letBNBpool });
  },
  calculateRateLocally: async blockAdjust => {
    return calculateRateLocally(blockAdjust, { provider, treasury, eerc20, wbnb, letBNBpool });
  },
  calculateAirdropAvailable: async (n, blockAdjust) => {
    return calculateAirdropAvailable(n, blockAdjust, { provider, treasury, eerc20, wbnb, letBNBpool, accounts });
  },
  calculatePosterRewardsAvailable: async (n, blockAdjust) => {
    return calculatePosterRewardsAvailable(n, blockAdjust, { provider, treasury, eerc20, wbnb, letBNBpool, accounts });
  },
  calculatePosterRewardsWithBonus: async (n, blockAdjust) => {
    return calculatePosterRewardsWithBonus(n, blockAdjust, { provider, treasury, eerc20, wbnb, letBNBpool, accounts });
  },
  calculateFounderRewardsAvailable: async (n, blockAdjust, willClaim) => {
    return calculateFounderRewardsAvailable(n, blockAdjust, willClaim, { provider, treasury, foundingEvent, eerc20, wbnb, letBNBpool, accounts });
  },
};

async function claimTest(methodName, hasIndependentSigner, iterations, firstClaimOccurred, lastClaimLeft, lowETHbalance) {
  let entity = await initEntity(methodName, firstClaimOccurred, lastClaimLeft, lowETHbalance);
  for (let i = 0; i < iterations; i++) {
    const n = Math.floor(Math.random() * 19);
    const nAddress = accounts[n].address;
    const signer = hasIndependentSigner ? accounts[Math.floor(Math.random() * 19)] : accounts[n];
    const randBlocks = Math.floor(Math.random() * 1000 + 1);
    const randAmount = ethers.BigNumber.from(Math.floor(Math.random() * 10000000 + 1000000))
      .mul(ethers.BigNumber.from(Math.floor(Math.random() * 10000000 + 1000000)))
      .mul(ethers.BigNumber.from(Math.floor(Math.random() * entity.randAmountMod + 1000000)));

    entity = await specificTestSetup(entity, nAddress, n, randAmount);

    await mine(randBlocks);
    const initialRecipientBalance = await eerc20.balanceOf(nAddress);
    const initialTreasuryBalance = await eerc20.balanceOf(treasury.address);

    entity = await specificJustBeforeTx(entity, nAddress, n);
    const tx = hasIndependentSigner ? treasury.connect(signer)[methodName]([accounts[n].address]) : treasury.connect(signer)[methodName]();
    const receipt = await (await tx).wait();
    const currentAmount = (await treasury[entity.name + 's'](nAddress)).amount;
    const currentLastClaim = (await treasury[entity.name + 's'](nAddress)).lastClaim;
    const recipientBalanceAfter = await eerc20.balanceOf(nAddress);
    let tc = {};
    tc = createTestCase({ methodName, i, n, nAddress, signer, randBlocks, randAmount, initialRecipientBalance, initialTreasuryBalance, entity, currentAmount });
    entity = await specificAfter(
      entity,
      signer,
      accounts,
      n,
      receipt,
      nAddress,
      tc,
      recipientBalanceAfter,
      initialRecipientBalance,
      initialTreasuryBalance,
      currentAmount
    );

    tc = createTestCase({ methodName, i, n, nAddress, signer, randBlocks, randAmount, initialRecipientBalance, initialTreasuryBalance, entity, currentAmount });
    expect(entity.toClaim, 'unexpected recipient balance.' + tcJSON(tc)).to.equal(recipientBalanceAfter.sub(initialRecipientBalance));
    expect(entity.toClaim, 'unexpected treasury balance.' + tcJSON(tc)).to.equal(initialTreasuryBalance.sub(await eerc20.balanceOf(treasury.address)));
    if (entity.name != 'poster') {
      expect(entity.toClaim, 'unexpected current amount.' + tcJSON(tc)).to.equal(entity.amount.sub(currentAmount)); //possible bonus case
    }
    if (entity.name != 'airdrop') {
      expect(receipt.blockNumber, 'unexpected lastClaim block.number.' + tcJSON(tc)).to.equal(currentLastClaim); //possible deletion after everything is claimed
    }
  }
}

async function initEntity(methodName, firstClaimOccurred, lastClaimLeft, lowETHbalance) {
  const entity = {};
  if (methodName.indexOf('Airdrop') != -1) {
    entity.name = 'airdrop';
    entity.emissionsIncluded = [];
    entity.randAmountMod = 20000000;
    entity.firstClaimOccurred = firstClaimOccurred;
    entity.lastClaimLeft = lastClaimLeft;
  } else if (methodName.indexOf('Founder') != -1) {
    entity.name = 'founder';
    entity.firstClaim;
    entity.randAmountMod = 20000000;
  } else if (methodName.indexOf('Poster') != -1) {
    entity.name = 'poster';
    entity.hasAirdrop;
    entity.isFounder;
    entity.lowETHbalance = lowETHbalance;
    entity.randAmountMod = 200000;
  }
  return entity;
}

async function specificTestSetup(entity, nAddress, n, randAmount) {
  if (entity.name == 'airdrop') {
    entity = await airdropTestSetup(entity, nAddress, n, randAmount);
  } else if (entity.name == 'poster') {
    entity = await posterTestSetup(entity, nAddress, randAmount);
  }
  return entity;
}

async function posterTestSetup(entity, nAddress, randAmount) {
  entity.hasAirdrop = Math.floor(Math.random() * 2) == 1 ? true : false;
  if (entity.hasAirdrop == true) {
    const randAirdrop = ethers.BigNumber.from(Math.floor(Math.random() * 99999999999 + 1));
    await treasury.addAirdropBulk([nAddress], [randAirdrop]);
  }
  await treasury.connect(accounts[10]).addPosters([nAddress], [randAmount]);
  await treasury.approvePosters([nAddress]);
  return entity;
}

async function airdropTestSetup(entity, nAddress, n, randAmount) {
  let toAdd = entity.lastClaimLeft == true ? 1111 : randAmount;
  await treasury.addAirdropBulk([nAddress], [toAdd]);
  if (entity.firstClaimOccurred == true) {
    await treasury.connect(accounts[n]).claimAirdrop();
  }
  return entity;
}

async function specificJustBeforeTx(entity, nAddress, n) {
  if (entity.name == 'founder') {
    entity = await founderBeforeTx(entity, nAddress, n);
  } else if (entity.name == 'airdrop') {
    entity = await airdropBeforeTx(entity, nAddress, n);
  } else if (entity.name == 'poster') {
    entity = await posterBeforeTx(entity, nAddress, n);
  }
  return entity;
}

async function founderBeforeTx(entity, nAddress, n) {
  entity.firstClaim = (await treasury.founders(nAddress)).registered ? false : true;
  entity.amount = entity.firstClaim ? await foundingEvent.deposits(nAddress) : (await treasury.founders(nAddress)).amount;
  entity.toClaim = await treasuryUtils.calculateFounderRewardsAvailable(n, 1, entity.firstClaim);
  return entity;
}

async function airdropBeforeTx(entity, nAddress, n) {
  entity.amount = (await treasury[entity.name + 's'](nAddress)).amount;
  entity.toClaim = await treasuryUtils.calculateAirdropAvailable(n, 1);
  return entity;
}

async function posterBeforeTx(entity, nAddress, n) {
  if (entity.lowBalance == true) {
    entity.balanceBeforeSpending = await provider.getBalance(nAddress);
    if (entity.balanceBeforeSpending.gt(100000000000000000n)) {
      entity.toSpend = entity.balanceBeforeSpending.sub(100000000000000000n);
      await accounts[n].sendTransaction({
        to: accounts[n + 1].address,
        value: entity.toSpend,
      });
    }
    entity.initialETHBalance = await provider.getBalance(nAddress);
  }
  const { toClaimInitial, toClaimWithBonus } = await treasuryUtils.calculatePosterRewardsWithBonus(n, 1); //might fail
  if (entity.lowBalance == true) {
    entity.amountToReceive = await treasuryUtils.getAmountOut(toClaimWithBonus, wbnb);
  }
  entity.amount = (await treasury[entity.name + 's'](nAddress)).amount;
  entity.toClaim = await treasuryUtils.calculateAirdropAvailable(n, 1);
  entity.initialTotalPosterRewards = await treasury.totalPosterRewards();
  entity.toClaimInitial = toClaimInitial;
  entity.toClaim = toClaimWithBonus;
  return entity;
}

async function specificAfter(
  entity,
  signer,
  accounts,
  n,
  receipt,
  nAddress,
  tc,
  recipientBalanceAfter,
  initialRecipientBalance,
  initialTreasuryBalance,
  currentAmount
) {
  if (entity.name == 'airdrop') {
    entity = await airdropAfter(entity, { nAddress, tc, currentAmount });
  } else if (entity.name == 'poster') {
    entity = await posterAfter(entity, {
      signer,
      accounts,
      n,
      receipt,
      nAddress,
      tc,
      recipientBalanceAfter,
      initialRecipientBalance,
      initialTreasuryBalance,
      currentAmount,
    });
  }
  return entity;
}

async function airdropAfter(entity, options) {
  const { nAddress, tc, currentAmount } = options;
  if (entity.emissionsIncluded.indexOf(nAddress) == -1 && currentAmount.gt(0)) {
    entity.emissionsIncluded.push(nAddress);
    expect(entity.emissionsIncluded.length, 'emission wasnt included.' + tcJSON(tc)).to.equal(await treasury.totalAirdropEmissions());
    expect(true, 'emission wasnt included.' + tcJSON(tc)).to.equal((await treasury.airdrops(nAddress)).emissionIncluded);
  }
  if (currentAmount.isZero()) {
    const index = entity.emissionsIncluded.indexOf(nAddress);
    if (index != -1) {
      entity.emissionsIncluded[index] = entity.emissionsIncluded[entity.emissionsIncluded.length - 1];
      entity.emissionsIncluded.pop();
    }
    const airdrop = await treasury[entity.name + 's'](nAddress);
    expect(0, 'unexpected reserved amount after deletion.' + tcJSON(tc)).to.equal(airdrop.reserved);
    expect(0, 'unexpected lastClaim after deletion.' + tcJSON(tc)).to.equal(airdrop.lastClaim);
    expect(false, 'unexpected emissionIncluded after deletion.' + tcJSON(tc)).to.equal(airdrop.emissionIncluded);
    expect(0, 'unexpected airdrop.amount.' + tcJSON(tc)).to.equal(airdrop.amount);
  }
  return entity;
}

async function posterAfter(entity, options) {
  const { signer, accounts, n, receipt, nAddress, tc, recipientBalanceAfter, initialRecipientBalance, initialTreasuryBalance, currentAmount } = options;
  if (entity.lowBalance == true) {
    entity.gasUsed = receipt.cumulativeGasUsed.mul(receipt.effectiveGasPrice);
    entity.currentETHBalance = await provider.getBalance(nAddress);
    entity.expectedBalanceAfter = entity.initialETHBalance.add(entity.amountToReceive);
    if (signer == accounts[n]) {
      entity.expectedBalanceAfter = entity.expectedBalanceAfter.sub(entity.gasUsed);
    }
    expect(entity.expectedBalanceAfter, 'unexpected recepient ETH balance.' + tcJSON(tc)).to.equal(entity.currentETHBalance);
  } else {
    expect(entity.toClaim, 'unexpected recepient LET balance.' + tcJSON(tc)).to.equal(recipientBalanceAfter.sub(initialRecipientBalance));
  }
  expect(entity.initialTotalPosterRewards.sub(entity.toClaimInitial), 'totalPosterRewards werent changed.' + tcJSON(tc)).to.equal(
    await treasury.totalPosterRewards()
  );
  expect(entity.toClaim, 'unexpected treasury balance.' + tcJSON(tc)).to.equal(initialTreasuryBalance.sub(await eerc20.balanceOf(treasury.address)));
  expect(entity.toClaimInitial, 'unexpected change of poster.amount.' + tcJSON(tc)).to.equal(entity.amount.sub(currentAmount));
  return entity;
}
