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

contract FoundingEvent {
	// I believe this is required for the safety of investors and other developers joining the project
	string public AgreementTerms = "I understand that this contract is provided with no warranty of any kind. \n I agree to not hold the contract creator, RAID team members or anyone associated with this event liable for any damage monetary and otherwise I might onccur. \n I understand that any smart contract interaction carries an inherent risk.";
	uint public foundingETHDeposited;
	uint public foundingLPtokensMinted;
	address public tokenETHLP; // create2 and hardcode too?
	mapping(address => uint) public contributions;
	bool private _lgeOngoing;
	address private _staking;
	bool private _stkngNtSt;
///////variables for testing purposes
	uint private _rewardsGenesis; // hardcoded block.number
	address payable private _deployer; // hardcoded

	constructor() {
		_deployer = msg.sender;
		_rewardsGenesis = block.number + 5;
		_lgeOngoing = true;
		_stkngNtSt = true;
	}

	function depositEth(bool iAgreeToPublicStringAgreementTerms) external payable {
		require(_lgeOngoing == true && iAgreeToPublicStringAgreementTerms == true && _isContract(msg.sender) == false);
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
		address uniFactory = 0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66;
		uint ETHDeposited = address(this).balance;
		IWETH(WETH).deposit{value: ETHDeposited}();
		address tknETHLP = IUniswapV2Factory(_uniswapFactory).createPair(token, WETH);
		IERC20(token).transfer(tknETHLP, 1e27);
		IERC20(WETH).transfer(tknETHLP, ETHDeposited);
		IUniswapV2Pair(tknETHLP).mint(_staking);
		foundingLPtokensMinted = IERC20(tknETHLP).balanceOf(address(this));
		foundingETHDeposited = ETHDeposited;
		tokenETHLP = tknETHLP;
	}

	function setStakingContract(address contr) public {require(msg.sender == _deployer && _stkngNtSt == true); _staking = contr; delete _stkngNtSt;}
	function _isContract(address a) internal view returns(bool) {uint s;assembly {s := extcodesize(a)}return s > 0;}
}
