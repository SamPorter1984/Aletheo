module.exports = {
    skipFiles: [
      "shared/TrustMinimizedProxy.sol","shared/WETH.sol","uniswap/ERC20.sol","mocks/DAIMock.sol","mocks/MockEERC20.sol","mocks/MockFactory.sol",
      "mocks/MockFoundingEvent.sol","mocks/MockPool.sol","mocks/MockRouter.sol","mocks/WETHMock.sol","uniswap/UniswapV2Factory.sol",
      'uniswap/UniswapV2Router02.sol',
    ],
    viaIR: true
  };