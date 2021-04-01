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
	bool private _lgeOngoing;
	bool private _notInit;
	address _token;
	address payable private _deployer;
	uint80 _ETHDeposited;
	uint16 _phase; // so what about potential 51% attack? so just in case we have to transfer in parts

	constructor() {_deployer = msg.sender;_notInit = true;}
	function init(address c, address t) public {require(msg.sender == _deployer && _notInit == true);delete _notInit; _lgeOngoing = true; _staking = c; _token = t;}

	function depositEth() external payable {
		require(_lgeOngoing == true);
		uint amount = msg.value;
		if (block.number >= 12550000) {
			uint phase = _phase;
			if (phase > 0) {_ETHDeposited += amount;}
			if(block.number >= phase+12550000){_phase = uint16(phase + 1000);_createLiquidity(phase);}
		}
		else {uint deployerShare = amount/200; amount -= deployerShare; _deployer.transfer(deployerShare);}
		contributions[msg.sender] += amount;
	}

	function _createLiquidity(uint phase) internal {
		address WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
		address token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8;// hardcoded token address after erc20 will be deployed
		address staking = _staking; // has to be deployed before lge start
		address tknETHLP = getPair[token][WETH];
		uint ethToDeposit = 1e15; // attempts to create one liquidity token first
		uint tokenToDeposit = 1e21;
		if (phase == 0) {_ETHDeposited = address(this).balance; if (tknETHLP == address(0)) {IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).createPair(token, WETH);}}
		else {ethToDeposit = _ETHDeposited/10;tokenToDeposit = 1e23;}
		if (phase == 9000) {
			ethToDeposit = address(this).balance;
			tokenToDeposit = IERC20(token).balanceOf(address(this));
			IStaking(staking).init(_ETHDeposited, tknETHLP);
			delete _staking; delete _lgeOngoing; delete _ETHDeposited; delete _phase;
		}
		IWETH(WETH).deposit{value: ethToDeposit}();
		IERC20(token).transfer(tknETHLP, tokenToDeposit);
		IERC20(WETH).transfer(tknETHLP, ethToDeposit);
		IUniswapV2Pair(tknETHLP).mint(staking);
	}
}
