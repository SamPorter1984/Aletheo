pragma solidity >=0.7.0 <0.9.0;

// Author: Sam Porter

// What CORE team did is something really interesting, with LGE it's now possible
// to create fairer distribution and fund promising projects without VC vultures at all.
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
	bool private _stkngNtSt;
///////variables for testing purposes
	uint private _rewardsGenesis; // hardcoded block.number
	address payable private _deployer; // hardcoded

	constructor() {_deployer = msg.sender;_rewardsGenesis = block.number + 5;_lgeOngoing = true;_stkngNtSt = true;}

	function depositEth() external payable {
		require(_lgeOngoing == true);
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_deployer.transfer(deployerShare);
		contributions[msg.sender] += amount;
		if (block.number >= _rewardsGenesis) {_createLiquidity();}
	}

	function _createLiquidity() internal {
		delete _lgeOngoing;
		address token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8; // testing
		address WETH = 0x2E9d30761DB97706C536A112B9466433032b28e3;
		address staking = _staking;
		uint ETHDeposited = address(this).balance;
		IWETH(WETH).deposit{value: ETHDeposited}();
		address tknETHLP = getPair[token][WETH];
		if (tknETHLP == address(0)) {IUniswapV2Factory(0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66).createPair(token, WETH);}
		IERC20(token).transfer(tknETHLP, 1e27);
		IERC20(WETH).transfer(tknETHLP, ETHDeposited);
		IUniswapV2Pair(tknETHLP).mint(staking);
		IStaking(staking).init(ETHDeposited, tknETHLP);
		IERC20(token).init(staking);
	}

	function setStakingContract(address contr) public {require(msg.sender == _deployer && _stkngNtSt == true); _staking = contr; delete _stkngNtSt;}
}
