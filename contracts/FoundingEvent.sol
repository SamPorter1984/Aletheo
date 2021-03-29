pragma solidity >=0.7.0 <0.8.0;

// Author: Sam Porter

// With LGE it's now possible to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// Founders' liquidity is not locked, instead an incentive to keep it is introduced.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// Blockchain needs no VCs, no authorities.
// Tokens will be staked by default after liquidity will be created, so there is no stake function, and unstaking means losing Founder rewards forever.
// I have moved rewards claiming and changing addresses logic to staking contract, which makes up for more efficient architecture. This contract is lighter
// and so much easier to audit for investors.

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IWETH.sol";
import "./IERC20.sol";
import "./IStaking.sol";

contract FoundingEvent {
	mapping(address => uint) public contributions;
	address private _staking;
	address private _token;
	bool private _lgeOngoing;
	bool private _notInit;
///////variables for testing purposes
	address payable private _deployer; // hardcoded


	constructor() {_deployer = msg.sender;_lgeOngoing = true;_notInit = true;}

	function depositEth() external payable {
		require(_lgeOngoing == true);
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_deployer.transfer(deployerShare);
		contributions[msg.sender] += amount;
		if (block.number >= 12550000) {_createLiquidity();}
	}

	function _createLiquidity() internal {
		delete _lgeOngoing;
		address token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8;// hardcoded token address after erc20 will be deployed
		address WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
		address staking = _staking; // has to be deployed before lge end
		uint ETHDeposited = address(this).balance;
		IWETH(WETH).deposit{value: ETHDeposited}();
		address tknETHLP = getPair[token][WETH];
		if (tknETHLP == address(0)) {IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).createPair(token, WETH);}
		IERC20(token).transfer(tknETHLP, 1e24);
		IERC20(WETH).transfer(tknETHLP, ETHDeposited);
		IUniswapV2Pair(tknETHLP).mint(staking);
		IStaking(staking).init(ETHDeposited, tknETHLP);
		delete _staking;
	}

	function init(address c) public {require(msg.sender == _deployer && _notInit == true);delete _notInit; _staking = c;}
}
