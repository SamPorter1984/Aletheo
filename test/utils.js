const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { ONE, HARDHAT_BLOCK_TIME, EMISSION_BASERATE_START_TIMESTAMP } = require('./constants');

function createTestCase(testCase) {
  const keys = Object.keys(testCase);
  const tc = {};
  for (n = 0; n < keys.length; n++) {
    tc[keys[n]] = testCase[keys[n]];
  }
  return tc;
}

function tcJSON(testCase) {
  return (
    '\nFAILED TEST CASE:' +
    JSON.stringify(
      testCase,
      (key, value) => {
        return key == 'hex' ? String(BigInt(value)) : value;
      },
      2
    )
  );
}

async function getAmountOut(amountIn, tkn, options) {
  const { eerc20, letETHpool } = options;
  const tknSize = ethers.BigNumber.from(tkn.address);
  const eerc20Size = ethers.BigNumber.from(eerc20.address);
  const [token0, token1] = tknSize.gt(eerc20Size) ? [eerc20.address, tkn.address] : [tkn.address, eerc20.address];
  const reserves = await letETHpool.getReserves();
  const [reserveLET, reserveTOKEN] = eerc20.address == token0 ? [reserves[0], reserves[1]] : [reserves[1], reserves[0]];
  const reserveIn = reserveLET;
  const reserveOut = reserveTOKEN;
  const amountInWithFee = amountIn.mul('997');
  const numerator = amountInWithFee.mul(reserveOut);
  const denominator = reserveIn.mul('1000').add(amountInWithFee);
  const amountOut = numerator.div(denominator);

  return amountOut;
}

async function calculateLetAmountInToken(stringValue, tkn, options) {
  const { eerc20, letETHpool } = options;
  const WETHSize = ethers.BigNumber.from(tkn.address);
  const eerc20Size = ethers.BigNumber.from(eerc20.address);
  const [token0, token1] = WETHSize.gt(eerc20Size) ? [eerc20.address, tkn.address] : [tkn.address, eerc20.address];
  const reserves = await letETHpool.getReserves();
  const [reserveLET, reserveTOKEN] = tkn.address == token0 ? [reserves[0], reserves[1]] : [reserves[1], reserves[0]];
  const amount = ethers.BigNumber.from(stringValue).mul(reserveLET).div(reserveTOKEN);

  return amount;
}

async function calculateRateLocally(blockAdjust, options) {
  const { provider, treasury, WETH } = options;
  if (!blockAdjust) {
    blockAdjust = 0;
  }
  let rate;
  const baseRate = await treasury.baseRate();
  //console.log("baseRateJS:",baseRate)
  const price = await calculateLetAmountInToken(ONE, WETH, options);
  const priceSqrt = sqrt(price)
  //console.log("priceSqrt:",priceSqrt)
  const timestamp = (await provider.getBlock(await provider.getBlockNumber())).timestamp + HARDHAT_BLOCK_TIME * blockAdjust;
  const timeSecs = ethers.BigNumber.from(timestamp).sub(EMISSION_BASERATE_START_TIMESTAMP);
  //console.log("timeSecs:",timeSecs)
  rate = price.gt(ethers.BigNumber.from(ONE)) ? (baseRate.div(priceSqrt)).div(timeSecs) : (baseRate.div(sqrt(ONE))).div(timeSecs);
  //console.log("rate:",rate)
  //console.log('block.numberJS:', await provider.getBlockNumber());
  return rate;
}

function sqrt(value) {
  const ONE = ethers.BigNumber.from(1);
  const TWO = ethers.BigNumber.from(2);
  x = ethers.BigNumber.from(value);
  let z = x.add(ONE).div(TWO);
  let y = x;
  while (z.sub(y).isNegative()) {
      y = z;
      z = x.div(z).add(z).div(TWO);
  }
  return y;
}

async function calculateAirdropAvailable(n, blockAdjust, options) {
  const { provider, treasury, eerc20, accounts } = options;
  if (!blockAdjust) {
    blockAdjust = 0;
  }
  let available;
  const treasuryBalance = await eerc20.balanceOf(treasury.address);
  const airdropAmount = (await treasury.airdrops(accounts[n].address)).amount;
  const reserved = (await treasury.airdrops(accounts[n].address)).reserved;
  const included = (await treasury.airdrops(accounts[n].address)).emissionIncluded;
  const freeAmount = airdropAmount.sub(reserved);
  const smaller = freeAmount.gt(treasuryBalance) ? treasuryBalance : freeAmount;
  if (!included) {
    available = airdropAmount.gt(ONE) ? ethers.BigNumber.from(ONE) : airdropAmount;
  } else {
    const rate = await calculateRateLocally(blockAdjust, options);
    let airdropRate = rate.div(await treasury.totalAirdropEmissions());
    if (airdropRate.gt('20000000000000')) {
      airdropRate = ethers.BigNumber.from('20000000000000');
    }
    const lastClaim = (await treasury.airdrops(accounts[n].address)).lastClaim;
    const blocksPassed = ethers.BigNumber.from(await provider.getBlockNumber())
      .add(blockAdjust)
      .sub(lastClaim);
    
    //console.log("blocksPassed:",blocksPassed)
    //console.log("airdropRate:",airdropRate)
    available = blocksPassed.mul(airdropRate);
  }
  available = available.gt(smaller) ? smaller : available;
  //console.log("available",available)
  return available;
}

async function calculatePosterRewardsAvailable(n, blockAdjust, options) {
  const { treasury, eerc20, accounts } = options;
  if (!blockAdjust) {
    blockAdjust = 0;
  }
  const poster = await treasury.posters(accounts[n].address);
  const lastClaim = poster.lastClaim;
  const posterAmount = poster.amount;
  const reserved = poster.reserved;
  const freeAmount = posterAmount.sub(reserved);
  const totalPosterRewards = await treasury.totalPosterRewards();
  const posterRate = await treasury.posterRate();
  const treasuryBalance = await eerc20.balanceOf(treasury.address);
  const rate = await calculateRateLocally(blockAdjust, options);
  const posterRewardsRate = rate.mul(posterAmount).div(totalPosterRewards).mul(posterRate).div(1000);
  const blockNumber = ethers.BigNumber.from(await time.latestBlock());
  let posterRewardsAvailable = (blockNumber.add(blockAdjust).sub(lastClaim)).mul(posterRewardsRate);
  const smaller = freeAmount.gt(treasuryBalance) ? treasuryBalance : freeAmount;
  posterRewardsAvailable = posterRewardsAvailable.gt(smaller) ? smaller : posterRewardsAvailable;
  return posterRewardsAvailable;
}

async function calculatePosterRewardsWithBonus(n, blockAdjust, options) {
  const { treasury, eerc20, accounts } = options;
  if (!blockAdjust) {
    blockAdjust = 0;
  }
  const toClaimInitial = await calculatePosterRewardsAvailable(n, blockAdjust, options);
  const treasuryBalance = await eerc20.balanceOf(treasury.address);
  const airdropAmount = (await treasury.airdrops(accounts[n].address)).amount;
  let bonus = 0;
  let toClaimWithBonus = toClaimInitial;
  if (airdropAmount.gt(0)) {
    bonus = airdropAmount.gte(toClaimInitial) ? toClaimInitial : airdropAmount;
    if (treasuryBalance.gte(toClaimInitial.add(bonus))) {
      toClaimWithBonus = toClaimInitial.add(bonus);
    } else {
      toClaimWithBonus = toClaimInitial.add(treasuryBalance);
    }
  }
  const founderAmount = (await treasury.founders(accounts[n].address)).amount;
  if (founderAmount.gt(0)) {
    bonus = founderAmount.gte(toClaimInitial) ? toClaimInitial : founderAmount;
    if (treasuryBalance.gte(toClaimWithBonus.add(bonus))) {
      toClaimWithBonus = toClaimWithBonus.add(bonus);
    } else {
      toClaimWithBonus = treasuryBalance;
    }
  }
  return { toClaimInitial, toClaimWithBonus };
}

async function calculateFounderRewardsAvailable(n, blockAdjust, firstClaim, options) {
  const { treasury, foundingEvent, eerc20, accounts } = options;
  if (!blockAdjust) {
    blockAdjust = 0;
  }
  const founder = await treasury.founders(accounts[n].address);
  if (founder.amount.isZero() && !firstClaim) {
    return ethers.BigNumber.from(0);
  }
  const lastClaim = firstClaim ? ethers.BigNumber.from(await foundingEvent.genesisBlock()) : founder.lastClaim;
  const founderAmount = firstClaim ? await foundingEvent.deposits(accounts[n].address) : founder.amount;
  const reserved = founder.reserved;
  const freeAmount = founderAmount.sub(reserved);
  const treasuryBalance = await eerc20.balanceOf(treasury.address);
  const totalFounderRewardsTreasury = await treasury.totalFounderRewards();
  const totalFounderRewards = totalFounderRewardsTreasury.gt('0') ? totalFounderRewardsTreasury : await foundingEvent.sold();
  const rate = await calculateRateLocally(blockAdjust, options);
  const founderRewardsRate = rate.mul(founderAmount).mul('5').div(totalFounderRewards);
  const blockNumber = ethers.BigNumber.from(await time.latestBlock());
  let blocksPassed = blockNumber.add(blockAdjust).sub(lastClaim);
  let founderRewardsAvailable = blocksPassed.mul(founderRewardsRate);
  const smaller = freeAmount.gt(treasuryBalance) ? treasuryBalance : freeAmount;
  founderRewardsAvailable = founderRewardsAvailable.gt(smaller) ? smaller : founderRewardsAvailable;
  return founderRewardsAvailable;
}

module.exports = {
  tcJSON,
  getAmountOut,
  createTestCase,
  calculateRateLocally,
  calculateLetAmountInToken,
  calculateAirdropAvailable,
  calculatePosterRewardsAvailable,
  calculatePosterRewardsWithBonus,
  calculateFounderRewardsAvailable,
};
