const { extendEnvironment } = require('hardhat/config');
const { createProvider } = require('hardhat/internal/core/providers/construction');
const { EthersProviderWrapper } = require('@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper');

extendEnvironment(hre => {
  hre.setThrowOnTransactionFailures = function (throwOn) {
    this.config.networks.hardhat.throwOnTransactionFailures = throwOn;
    this.network.config = this.config.networks.hardhat;
    this.network.provider = createProvider('hardhat', this.config.networks.hardhat, this.config.paths, this.artifacts);
    this.ethers.provider = new EthersProviderWrapper(this.network.provider);
  };
});

module.exports = {
  extendEnvironment,
};
