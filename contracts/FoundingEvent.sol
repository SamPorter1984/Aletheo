pragma solidity >=0.7.0 <0.8.0;

// Author: Sam Porter

// With LGE it's now possible to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// Founders' liquidity is not locked, instead an incentive to keep it is introduced.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// Blockchain needs no VCs, no authorities.

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IWETH.sol";
import "./IERC20.sol";
import "./IStaking.sol";

contract FoundingEvent {
	mapping(address => uint) public contributions;
	address payable private _deployer;
	uint88 private _phase; // so what about potential 51% attack? so just in case we have to transfer in parts
	bool private _lgeOngoing;
	address private _staking;
	uint88 private _ETHDeposited;
	bool private _notInit;

	constructor() {_deployer = msg.sender;_notInit = true;}
	function init(address c) public {require(msg.sender == _deployer && _notInit == true);delete _notInit; _lgeOngoing = true; _staking = c;}

	function depositEth() external payable {
		require(_lgeOngoing == true);
		uint amount = msg.value;
		if (block.number >= 12550000) {
			uint phase = _phase;
			if (phase > 0) {_ETHDeposited += uint88(amount);}
			if(block.number >= phase+12550000){_phase = uint88(phase + 10000);_createLiquidity(phase);}
		}
		else {uint deployerShare = amount/200; amount -= deployerShare; _deployer.transfer(deployerShare);}
		contributions[msg.sender] += amount;
	}

	function _createLiquidity(uint phase) internal {
		address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
		address token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8;// hardcoded token address after erc20 will be deployed
		address staking = _staking; // has to be deployed before lge start
		address tknETHLP = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair[token][WETH];
		if (phase == 0) {_ETHDeposited = uint88(address(this).balance); if (tknETHLP == address(0)) {IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).createPair(token, WETH);}}
		uint ethToDeposit = _ETHDeposited*3/5;
		uint tokenToDeposit = 1e23;
		if (phase == 90000) {
			ethToDeposit = address(this).balance; IStaking(staking).init(_ETHDeposited, tknETHLP);
			delete _staking; delete _lgeOngoing; delete _ETHDeposited; delete _phase; delete _deployer;
		}
		IWETH(WETH).deposit{value: ethToDeposit}();
		IERC20(token).transfer(tknETHLP, tokenToDeposit);
		IERC20(WETH).transfer(tknETHLP, ethToDeposit);
		IUniswapV2Pair(tknETHLP).mint(staking);
	}
}
