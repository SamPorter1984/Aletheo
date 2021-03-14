pragma solidity >=0.6.0;

// Author: Sam Porter

// What CORE team did is something really interesting, with LGE it's now possible 
// to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// Founders' liquidity is not locked, instead an incentive to keep it is introduced.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// Blockchain needs no VCs, no authorities.

// Tokens will be staked by default after liquidity will be created, so there is no stake function, and unstaking means losing Founder rewards forever.

import "./SafeMath.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ITreasury.sol";
import "./IWETH.sol";
import "./IERC20.sol";
import "./IGovernance.sol";

contract FoundingEvent {
	using SafeMath for uint;

	// I believe this is required for the safety of investors and other developers joining the project
	string public agreementTerms = "I understand that this contract is provided with no warranty of any kind. \n I agree to not hold the contract creator, RAID team members or anyone associated with this event liable for any damage monetary and otherwise I might onccur. \n I understand that any smart contract interaction carries an inherent risk.";
	uint private _totalETHDeposited;
	uint private _ETHDeposited;
	uint private _totalLGELPtokensMinted;
	bool private _lgeOngoing = true;
	address private _tokenETHLP; // create2 and hardcode too?
	address payable private _governance;
	uint private _linkLimit;
	uint private _lockTime;
	uint private _reentrancyStatus;
	uint private _rewardsToRecompute;

///////variables for testing purposes
	address private constant _WETH = 0x2E9d30761DB97706C536A112B9466433032b28e3;// testing
	address private _uniswapFactory = 0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66;
	uint private _rewardsGenesis; // = hardcoded block.number
	address private _token; // = hardcoded address
	address private _treasury;
	uint private _lgeStart; // not required. replace with hardcoded blocknumbers
	uint private _totalTokenAmount;
//////
	constructor() {
		_governance = msg.sender;
		_linkLimit = 1e17; // 0.1 ether
		_token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8; // testing
		_rewardsGenesis = block.number + 5;
		_lockTime = 10512000;
		_totalTokenAmount = 1e27;
	}

	struct Founder {uint ethContributed; bool firstClaim; uint claimed; uint tokenAmount; uint lockUpTo;}

	mapping(address => Founder) private _founders;
	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _takenAddresses;

	event AddressLinked(address indexed address1, address indexed address2);

	modifier onlyFounder() {require(_founders[msg.sender].ethContributed > 0 && _reentrancyStatus != 1, "Not a Founder or reentrancy guard");_reentrancyStatus = 1;_;_reentrancyStatus = 0;}
	modifier onlyGovernance() {require(msg.sender == _governance, "not governance");_;}

	function depositEth(bool iAgreeToPublicStringAgreementTerms) external payable {
		require(_lgeOngoing == true && iAgreeToPublicStringAgreementTerms == true, "LGE has already ended or didn't start, or no agreement provided");
		require(_isContract(msg.sender) == false, "contracts can't be Founders");
		if (_takenAddresses[msg.sender] == true) {
			address linkedAddress = _linkedAddresses[msg.sender]; delete _linkedAddresses[linkedAddress]; delete _linkedAddresses[msg.sender]; delete _takenAddresses[msg.sender];
		}
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_governance.transfer(deployerShare);
		_founders[msg.sender].ethContributed += amount;
		if (block.number >= _rewardsGenesis) {_createLiquidity();}
	}

	function unstakeLP() public onlyFounder {
		require(_founders[msg.sender].lockUpTo <= block.number && _founders[msg.sender].firstClaim == true, "tokens locked or claim rewards");
		uint totalETHDeposited = _totalETHDeposited;
		if (_ETHDeposited == 0) {_ETHDeposited = totalETHDeposited;}
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/totalETHDeposited;
		uint inStock = IERC20(_tokenETHLP).balanceOf(address(this));
		if (lpShare > inStock) {lpShare = inStock;}
		_ETHDeposited -= ethContributed;
		_totalTokenAmount -= _founders[msg.sender].tokenAmount;
		IERC20(_tokenETHLP).transfer(address(msg.sender), lpShare);
		delete _founders[msg.sender];
	}

	function claimLGERewards() public onlyFounder { // has to have first Method Id or close to
		uint rewardsGenesis = _rewardsGenesis;
		require(block.number > rewardsGenesis, "too soon");
		uint toClaim;
		uint halver = block.number/10000000;uint rewardsRate = 100;if (halver>1) {for (uint i=1;i<halver;i++) {rewardsRate=rewardsRate*5/6;}}
		if(_founders[msg.sender].firstClaim==false){_founders[msg.sender].firstClaim=true;_founders[msg.sender].tokenAmount=_founders[msg.sender].ethContributed*1e27/_totalETHDeposited;}
		toClaim = (block.number - rewardsGenesis)*rewardsRate*1e18*_founders[msg.sender].tokenAmount/_totalTokenAmount;
		toClaim = toClaim.s(_founders[msg.sender].claimed);
		_founders[msg.sender].claimed += toClaim;
		ITreasury(_treasury).claimFounderRewards(address(msg.sender), toClaim);
	}

	function migrate() public onlyFounder {
		require(_founders[msg.sender].firstClaim == true && IGovernance(_governance).getVoting() == false, "claim rewards before this or voting is ongoing");
		require(_founders[msg.sender].claimed == 0, "still rewards left");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/_ETHDeposited;
		uint inStock = IERC20(_tokenETHLP).balanceOf(address(this));
		if (lpShare > inStock) {lpShare = inStock;}
		IERC20(_tokenETHLP).transfer(_treasury, lpShare);
		ITreasury(_treasury).stakeFromLgeContract(msg.sender,lpShare,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);// should tokenAmount be cut in half here?
		delete _founders[msg.sender];
	}

	function changeAddress(address account) public onlyFounder {
		require(_isContract(account) == false && IGovernance(_governance).getVoting() == false, "contracts can't be founders or voting is ongoing");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint claimed = _founders[msg.sender].claimed;
		bool firstClaim = _founders[msg.sender].firstClaim;
		uint tokenAmount = _founders[msg.sender].tokenAmount;
		uint lockUpTo = _founders[msg.sender].lockUpTo;
		delete _founders[msg.sender];
		_founders[account].ethContributed = ethContributed;
		_founders[account].claimed = claimed;
		_founders[account].firstClaim = firstClaim;
		_founders[account].tokenAmount = tokenAmount;
		_founders[account].lockUpTo = lockUpTo;
	}

	function _createLiquidity() internal {
		delete _lgeOngoing;
		uint ETHDeposited = address(this).balance;
		IWETH(_WETH).deposit{value: ETHDeposited}();
		_tokenETHLP = IUniswapV2Factory(_uniswapFactory).createPair(_token, _WETH);
		IERC20(_WETH).transfer(_tokenETHLP, ETHDeposited);
		IERC20(_token).transfer(_tokenETHLP, 1e27);
		IUniswapV2Pair(_tokenETHLP).mint(address(this));
		_totalLGELPtokensMinted = IERC20(_tokenETHLP).balanceOf(address(this));
		_totalETHDeposited = ETHDeposited;
	}

	function lock() public onlyFounder {require(_founders[msg.sender].firstClaim == true, "first you have to claim rewards");_founders[msg.sender].lockUpTo = block.number + _lockTime;}
	function isFounder(address account) public view returns(bool) {if (_founders[account].ethContributed > 0) {return true;} else {return false;}}
	function setLinkLimit(uint value) external onlyGovernance {require(value >= 0 && value < 1e18, "can't override hard limit");_linkLimit = value;}
	function setLockTime(uint lockTime_) public onlyGovernance {require(lockTime_ >= 6307200 && lockTime_ <= 10512000, "can't override hardlimits");_lockTime = lockTime_;} // between 3 and 5 years
	function _isContract(address account) internal view returns (bool) {uint256 size;assembly {size := extcodesize(account)}return size > 0;}
	function setGovernance(address payable account) public onlyGovernance {_governance = account;}

	function linkAddress(address account) external onlyFounder { // can be used to limit the amount of testers to only approved addresses
		require(_linkedAddresses[msg.sender] != account && _takenAddresses[account] == false, "already linked these or somebody already uses this");
		require(isFounder(account) == false && _founders[msg.sender].ethContributed >= _linkLimit, "can't link founders or not enough eth deposited");
		if (_linkedAddresses[msg.sender] != address(0)) {
			address linkedAddress = _linkedAddresses[msg.sender]; delete _linkedAddresses[msg.sender]; delete _linkedAddresses[linkedAddress]; delete _takenAddresses[linkedAddress];
		}
		_linkedAddresses[msg.sender] = account;
		_linkedAddresses[account] = msg.sender;
		_takenAddresses[account] = true;
		emit AddressLinked(msg.sender,account);
	}
// VIEW FUNCTIONS ==================================================
	function getFounder(address account) external view returns (uint ethContributed, uint claimed, bool firstClaim, uint lockUpTo, address linked) {
		return (_founders[account].ethContributed,_founders[account].claimed,_founders[account].firstClaim,_founders[account].lockUpTo,_linkedAddresses[account]);
	}

	function getFounderTknAmount(address account) external view returns (uint tknAmount) {return _founders[account].tokenAmount;}

	function getLgeInfo() external view returns (bool lgeOng,uint rewGenesis,uint rewRate,uint totEthDepos, uint EthDepos, uint totTknAmount, uint rewToRecompute,uint totLGELPMinted) {
		uint halver=block.number/10000000;uint rewardsRate=100;if (halver>1) {for (uint i=1;i<halver;i++) {rewardsRate=rewardsRate*5/6;}}
		return (_lgeOngoing,_rewardsGenesis,rewardsRate,_totalETHDeposited,_ETHDeposited,_totalTokenAmount,_rewardsToRecompute,_totalLGELPtokensMinted);
	}
}
