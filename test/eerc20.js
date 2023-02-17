const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { expect } = require('chai');
const { ethers } = require('hardhat');

const { EERC20Fixture, erc20Fixture, EERC20ProxiedFixture } = require('./fixtures/eerc20Fixtures.js');

let eerc20,
  erc20,
  eerc20Proxied = {},
  accounts = [];

describe('EERC20', function () {
  beforeEach('deploy fixture', async () => {
    [eerc20, accounts] = await loadFixture(EERC20Fixture);
  });

  describe('init()', function () {
    it('Initializes correctly', async function () {

      const latestBlock = await ethers.provider.getBlock("latest");
      console.log(latestBlock.timestamp)
      expect(await eerc20.ini(), 'unexpected ini value').to.equal(true);
      expect(await eerc20.name(), 'unexpected name value').to.equal('Aletheo');
      expect(await eerc20.symbol(), 'unexpected symbol value').to.equal('LET');
      const ab = await eerc20.ab();
      expect(ab.liquidityManager, 'unexpected liquidityManager value').to.equal(accounts[2].address);
      expect(ab.treasury, 'unexpected treasury value').to.equal(accounts[3].address);
      expect(ab.foundingEvent, 'unexpected foundingEvent value').to.equal(accounts[4].address);
      expect(ab.governance, 'unexpected governance value').to.equal(accounts[0].address);
      expect(await eerc20.totalSupply(), 'unexpected totalSupply value').to.equal(ethers.BigNumber.from('135000000000000000000000'));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected governance balance').to.equal(ethers.BigNumber.from('15000000000000000000000'));
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(ethers.BigNumber.from('50000000000000000000000'));
      expect(await eerc20.balanceOf(accounts[4].address), 'unexpected foundingEvent balance').to.equal(ethers.BigNumber.from('70000000000000000000000'));
    });
    it('Cant be initialized more than once', async () => {
      await expect(
        eerc20.init({
          liquidityManager: accounts[2].address,
          treasury: accounts[3].address,
          foundingEvent: accounts[4].address,
          governance: accounts[0].address,
          factory: accounts[0].address,
          helper: accounts[0].address,
          WETH: accounts[0].address,
        })
      ).to.be.reverted;
    });
  });

  describe('allowance()', function () {
    it('Has false by default', async function () {
      expect(await eerc20.allowance(accounts[1].address, accounts[0].address)).to.equal(0);
    });
    it('Has pancake router allowance by default', async function () {
      expect(await eerc20.allowance(accounts[1].address, '0x10ED43C718714eb63d5aA57B78B54704E256024E')).to.equal(ethers.constants.MaxUint256);
    });
  });

  describe('approve()', function () {
    it('Sets allowance to true', async function () {
      await eerc20.approve(accounts[1].address, 1);
      expect(await eerc20.allowance(accounts[0].address, accounts[1].address)).to.equal(ethers.constants.MaxUint256);
    });
    it('Unable to set pancake router allowance', async function () {
      expect(await eerc20.allowance(accounts[0].address, '0x10ED43C718714eb63d5aA57B78B54704E256024E')).to.equal(ethers.constants.MaxUint256);
      await eerc20.approve('0x10ED43C718714eb63d5aA57B78B54704E256024E', 1);
      expect(await eerc20.allowance(accounts[0].address, '0x10ED43C718714eb63d5aA57B78B54704E256024E')).to.equal(ethers.constants.MaxUint256);
    });
  });

  describe('disallow()', function () {
    it('Sets allowance to false', async function () {
      await eerc20.approve(accounts[1].address, 1);
      expect(await eerc20.allowance(accounts[0].address, accounts[1].address)).to.equal(ethers.constants.MaxUint256);
      await eerc20.disallow(accounts[1].address);
      expect(await eerc20.allowance(accounts[0].address, accounts[1].address)).to.equal(0);
    });
    it('Unable to set pancake router allowance', async function () {
      expect(await eerc20.allowance(accounts[0].address, '0x10ED43C718714eb63d5aA57B78B54704E256024E')).to.equal(ethers.constants.MaxUint256);
      await eerc20.disallow('0x10ED43C718714eb63d5aA57B78B54704E256024E');
      expect(await eerc20.allowance(accounts[0].address, '0x10ED43C718714eb63d5aA57B78B54704E256024E')).to.equal(ethers.constants.MaxUint256);
    });
  });

  describe('decimals()', function () {
    it('Return correct decimals number', async function () {
      expect(await eerc20.decimals()).to.equal(18);
    });
  });

  describe('addPool()', function () {
    it('Sets pools to true for address if called by liquidityManager', async function () {
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address)).not.to.be.reverted;
      expect(await eerc20.pools(accounts[1].address)).to.equal(true);
    });
    it('Fails to set Pool to true if called by not liquidityManager', async function () {
      await expect(eerc20.addPool(accounts[1].address)).to.be.reverted;
      expect(await eerc20.pools(accounts[1].address)).to.equal(false);
    });
  });

  describe('setSellTax()', function () {
    it('Sets sellTax if called by governance', async function () {
      const arg = 1;
      await expect(eerc20.setSellTax(arg)).not.to.be.reverted;
      expect(await eerc20.sellTax()).to.equal(arg);
    });
    it('Fails to set sellTax if called by not governance', async function () {
      failToSetGovernance(1, accounts[2]);
    });
    it('Fails to set sellTax above 50 if called by governance', async function () {
      failToSetGovernance(51, accounts[0]);
    });
  });

  describe('mint()', function () {
    it('Mints gazillions if called by treasury', async function () {
      const arg = ethers.BigNumber.from('999999999999999999999999999999999999');
      const initialValue = await eerc20.totalSupply();
      const tx = eerc20.connect(accounts[3]).mint(accounts[0].address, arg);
      await expect(tx, 'unexpected revert').not.to.be.reverted;
      await expect(tx, 'emit event failed').to.emit(eerc20, 'Transfer');
      const receipt = await (await tx).wait();
      expect(await eerc20.totalSupply(), 'unexpected totalSupply').to.equal(initialValue.add(arg));
    });
    it('Fails to mint if called by not treasury', async function () {
      failToMint(1, accounts[2]);
    });
    it('Fails to overflow uint256 if called by treasury', async function () {
      failToMint(ethers.constants.MaxUint256, accounts[3]);
    });
    it('Fails to mint 0 if called by treasury', async function () {
      failToMint(0, accounts[3]);
    });
  });

  describe('transfer()', function () {
    it('Successfully transfers', async function () {
      const arg = 5;
      const initialBalance = await eerc20.balanceOf(accounts[0].address);
      const initialRecipientBalance = await eerc20.balanceOf(accounts[1].address);
      const tx = eerc20.transfer(accounts[1].address, arg);
      await expect(tx, 'event wasnt emitted').to.emit(eerc20, 'Transfer');
      const receipt = await (await tx).wait();
      await expect(receipt.status, 'first transfer failed').to.equal(1);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected recipient balance').to.equal(initialBalance.sub(arg));
      const tx1 = await eerc20.transfer(accounts[1].address, 1);
      const receipt1 = await tx1.wait();
      await expect(receipt1.status, 'second transfer failed').to.equal(1);
      console.log('         first attempt gas:' + receipt.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt1.cumulativeGasUsed);
    });
    it('Reverts if balance is lower than amount', async function () {
      await expect(eerc20.transfer(accounts[1].address, ethers.constants.MaxUint256)).to.be.reverted;
    });
    it('Sets correct balances in transfers not involving trading pools if sellTax is not 0', async function () {
      const arg = 5;
      const { initialBalance, initialRecipientBalance } = await transferHelper(accounts[0], accounts[1], 50, arg);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
    });
    it('Sets correct balances for sender, pool and treasury if sellTax is not 0', async function () {
      const arg = 1000,
        sellTax = 50;
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address)).not.to.be.reverted;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferHelper(accounts[0], accounts[1], sellTax, arg);
      const fee = (arg * sellTax) / 1000;
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg).sub(fee));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance.add(fee));
    });
    it('Ignores sellTax if sender is FoundingEvent and if sellTax is not 0', async function () {
      const arg = 1000,
        sellTax = 50;
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address)).not.to.be.reverted;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferHelper(accounts[4], accounts[1], sellTax, arg);
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
    });
    it('Ignores sellTax if sender is LiquidityManager and if sellTax is not 0', async function () {
      await eerc20.transfer(accounts[2].address, 100000);
      const arg = 1000,
        sellTax = 50;
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address)).not.to.be.reverted;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferHelper(accounts[4], accounts[1], sellTax, arg);
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
    });
  });

  describe('transferFrom()', function () {
    it('Successfully transfers from', async function () {
      await eerc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      const initialBalance = await eerc20.balanceOf(accounts[0].address);
      const initialRecipientBalance = await eerc20.balanceOf(accounts[1].address);
      const arg = 5;
      const tx1 = eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, arg);

      const receipt1 = await (await tx1).wait();
      expect(tx1, 'event wasnt emitted').to.emit(eerc20, 'Transfer');
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));

      const tx2 = await eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2);
      const receipt2 = await tx2.wait();
      await expect(receipt1.status, 'tx1 failed').to.equal(1);
      await expect(receipt2.status, 'tx2 failed').to.equal(1);
      console.log('         first attempt gas:' + receipt1.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt2.cumulativeGasUsed);
    });
    it('Reverts if balance is lower than amount', async function () {
      await eerc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      await expect(eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, ethers.constants.MaxUint256)).to.be.reverted;
    });
    it('Reverts if allowance is false', async function () {
      await expect(eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2)).to.be.reverted;
    });
    it('Sets correct balances for normal accounts if sellTax is not 0', async function () {
      await eerc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      const arg = 5,
        sellTax = 20;
      const { initialBalance, initialRecipientBalance } = await transferFromHelper(accounts[1], accounts[0].address, accounts[1].address, sellTax, arg);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
    });
    it('Sets correct balances for sender, pool and treasury if sellTax is not 0', async function () {
      await eerc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address), 'addPool failed').not.to.be.reverted;
      const arg = 1000,
        sellTax = 20;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferFromHelper(accounts[1], accounts[0].address, accounts[1].address, sellTax, arg);
      const fee = (arg * sellTax) / 1000;
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance.add(fee));
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg).sub(fee));
      expect(await eerc20.balanceOf(accounts[0].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
    });
    it('Ignores sellTax if sender is FoundingEvent and if sellTax is not 0', async function () {
      await eerc20.connect(accounts[4]).approve(accounts[1].address, ethers.constants.MaxUint256);
      const arg = 1000,
        sellTax = 50;
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address), 'addPool failed').not.to.be.reverted;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferFromHelper(accounts[1], accounts[4].address, accounts[1].address, sellTax, arg);
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[4].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
    });
    it('Ignores sellTax if sender is LiquidityManager and if sellTax is not 0', async function () {
      await eerc20.transfer(accounts[2].address, 100000);
      await eerc20.connect(accounts[2]).approve(accounts[1].address, ethers.constants.MaxUint256);
      const arg = 1000,
        sellTax = 50;
      await expect(eerc20.connect(accounts[2]).addPool(accounts[1].address), 'addPool failed').not.to.be.reverted;
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      const { initialBalance, initialRecipientBalance } = await transferFromHelper(accounts[1], accounts[2].address, accounts[1].address, sellTax, arg);
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance);
      expect(await eerc20.balanceOf(accounts[1].address), 'unexpected recipient balance').to.equal(initialRecipientBalance.add(arg));
      expect(await eerc20.balanceOf(accounts[2].address), 'unexpected sender balance').to.equal(initialBalance.sub(arg));
    });
  });

  describe('transferBatch()', function () {
    it('Successfully transfers Batch', async function () {
      let sender = accounts[0];
      let recipients = accounts;
      let power = 1;
      let addresses = [];
      let amounts = [];
      let initialValues = [];
      let totalAmount = 0;
      for (let n = 0; n < recipients.length; n++) {
        addresses.push(recipients[n].address);
        amounts.push(n ** power);
        initialValues.push(await eerc20.balanceOf(recipients[n].address));
        totalAmount += n ** power;
      }
      let initialBalance = await eerc20.balanceOf(sender.address);
      const tx = eerc20.connect(sender).transferBatch(addresses, amounts);
      expect(tx, 'event wasnt emitted').to.emit(eerc20, 'Transfer');
      const receipt = await (await tx).wait();
      console.log('         first attempt gas:' + receipt.cumulativeGasUsed);
      await expect(receipt.status, 'transferBatch failed').to.equal(1);
      for (let n = 1; n < addresses.length; n++) {
        expect(await eerc20.balanceOf(accounts[n].address), 'unexpected balance for accounts[' + n + ']').to.equal(
          initialValues[n].add(ethers.BigNumber.from(amounts[n]))
        );
      }
      expect(await eerc20.balanceOf(sender.address), 'unexpected sender balance').to.equal(initialBalance.sub(totalAmount));
    });
    it('Reverts if sender balance is lower than sum of amounts', async function () {
      let addresses = [];
      let amounts = [];
      let initialValues = [];
      let totalAmount = 0;
      for (let n = 0; n < accounts.length; n++) {
        addresses.push(accounts[n].address);
        amounts.push(ethers.BigNumber.from(n).mul(ethers.BigNumber.from('99999999999999999999999999')));
        initialValues.push(await eerc20.balanceOf(accounts[n].address));
        totalAmount += ethers.BigNumber.from(n).mul(ethers.BigNumber.from('99999999999999999999999999'));
      }
      await expect(eerc20.transferBatch(addresses, amounts)).to.be.reverted;
    });
    it('Ignores sellTax', async function () {
      await eerc20.setSellTax(50);
      const initialTreasuryBalance = await eerc20.balanceOf(accounts[3].address);
      let { addresses, initialValues, amounts } = await transferBatchHelper(accounts[0], accounts, 1);
      for (let n = 1; n < addresses.length; n++) {
        expect(await eerc20.balanceOf(accounts[n].address), 'unexpected balance for accounts[' + n + ']').to.equal(
          initialValues[n].add(ethers.BigNumber.from(amounts[n]))
        );
      }
      expect(await eerc20.balanceOf(accounts[3].address), 'unexpected treasury balance').to.equal(initialTreasuryBalance.add(amounts[3]));
    });
  });
});

describe('EERC20Proxied', function () {
  beforeEach('deploy fixture', async () => {
    [eerc20, accounts] = await loadFixture(EERC20ProxiedFixture);
  });
  describe('transfer()', function () {
    it('Successfully transfers', async function () {
      const tx = await eerc20.transfer(accounts[1].address, 1);
      const receipt = await tx.wait();
      const tx1 = await eerc20.transfer(accounts[1].address, 1);
      const receipt1 = await tx1.wait();
      await expect(receipt.status, 'tx failed').to.equal(1);
      await expect(receipt1.status, 'tx1 failed').to.equal(1);
      console.log('         first attempt gas:' + receipt.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt1.cumulativeGasUsed);
    });
  });
  describe('transferFrom()', function () {
    it('Successfully transfers from', async function () {
      await eerc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      const tx1 = await eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2);
      const receipt1 = await tx1.wait();
      const tx2 = await eerc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2);
      const receipt2 = await tx2.wait();
      await expect(receipt1.status, 'tx1 failed').to.equal(1);
      await expect(receipt2.status, 'tx2 failed').to.equal(1);
      console.log('         first attempt gas:' + receipt1.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt2.cumulativeGasUsed);
    });
  });
  describe('transferBatch()', function () {
    it('Should successfully transferBatch', async function () {
      await transferBatchHelper(accounts[0], accounts, 1);
    });
  });
});

describe('ERC20', function () {
  beforeEach('deploy fixture', async () => {
    [erc20, accounts] = await loadFixture(erc20Fixture);
  });
  describe('transfer()', async function () {
    it('Should successfully transfer', async function () {
      const tx = await erc20.transfer(accounts[1].address, 1);
      const receipt = await tx.wait();
      const tx1 = await erc20.transfer(accounts[1].address, 1);
      const receipt1 = await tx1.wait();
      await expect(receipt.status).to.equal(1);
      await expect(receipt1.status).to.equal(1);
      console.log('         first attempt gas:' + receipt.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt1.cumulativeGasUsed);
    });
  });
  describe('transferFrom()', async function () {
    it('Should successfully transferFrom', async function () {
      await erc20.approve(accounts[1].address, ethers.constants.MaxUint256);
      const tx1 = await erc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2);
      const receipt1 = await tx1.wait();
      const tx2 = await erc20.connect(accounts[1]).transferFrom(accounts[0].address, accounts[1].address, 2);
      const receipt2 = await tx2.wait();
      await expect(receipt1.status).to.equal(1);
      await expect(receipt2.status).to.equal(1);
      console.log('         first attempt gas:' + receipt1.cumulativeGasUsed);
      console.log('         second attempt gas:' + receipt2.cumulativeGasUsed);
    });
  });
});

async function failToSetGovernance(arg, caller) {
  const initialValue = await eerc20.sellTax();
  await expect(eerc20.connect(caller).setSellTax(arg)).to.be.reverted;
  expect(await eerc20.sellTax()).to.equal(initialValue);
}

async function failToMint(arg, signer) {
  const initialValue = await eerc20.totalSupply();
  await expect(eerc20.connect(signer).mint(accounts[0].address, arg)).to.be.reverted;
  expect(await eerc20.totalSupply(), 'unexpected totalSupply').to.equal(initialValue);
}

async function transferHelper(sender, recipient, sellTax, arg) {
  await eerc20.setSellTax(sellTax);
  const initialBalance = await eerc20.balanceOf(sender.address);
  const initialRecipientBalance = await eerc20.balanceOf(recipient.address);
  const tx = await eerc20.connect(sender).transfer(recipient.address, arg);
  const receipt = await tx.wait();
  return { initialBalance, initialRecipientBalance };
}

async function transferFromHelper(caller, sender, recipient, sellTax, arg) {
  await eerc20.setSellTax(sellTax);
  const initialBalance = await eerc20.balanceOf(sender);
  const initialRecipientBalance = await eerc20.balanceOf(recipient);
  const tx = await eerc20.connect(caller).transferFrom(sender, recipient, arg);
  const receipt = await tx.wait();
  return { initialBalance, initialRecipientBalance };
}

async function transferBatchHelper(sender, recipients, power) {
  let addresses = [];
  let amounts = [];
  let initialValues = [];
  let totalAmount = 0;
  for (let n = 0; n < recipients.length; n++) {
    addresses.push(recipients[n].address);
    amounts.push(n ** power);
    initialValues.push(await eerc20.balanceOf(recipients[n].address));
    totalAmount += n ** power;
  }
  let initialBalance = await eerc20.balanceOf(sender.address);
  const tx = await eerc20.connect(sender).transferBatch(addresses, amounts);
  const receipt = await tx.wait();
  console.log('         first attempt gas:' + receipt.cumulativeGasUsed);
  await expect(receipt.status, 'transferBatch failed').to.equal(1);
  expect(await eerc20.balanceOf(sender.address), 'unexpected sender failed').to.equal(initialBalance.sub(totalAmount));
  return { addresses, initialValues, amounts };
}
