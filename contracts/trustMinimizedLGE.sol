pragma solidity >=0.6.0;

// Author: Sam Porter

// Trustless or trust minimized for accuracy.
// What CORE team did is something really interesting, with LGE it's now possible 
// to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// Founders' liquidity is not locked, instead an incentive to keep it is introduced.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// Blockchain needs no VCs, no authorities.

import "./SafeMath.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ILGE2.sol";
import "./IlpOraclesFund.sol";
import "./IWETH.sol";
import "./IERC20.sol";

contract FoundingEvent {
	using SafeMath for uint;

	// I believe this is required for the safety of investors and other developers joining the project
	string public agreementTerms = "I understand that this contract is provided with no warranty of any kind. \n I agree to not hold the contract creator, RAID team members or anyone associated with this event liable for any damage monetary and otherwise I might onccur. \n I understand that any smart contract interaction carries an inherent risk.";
	uint private _totalETHDeposited;
	uint private _ETHDeposited;
	uint private _totalLGELPtokensMinted;
	bool private _lgeOngoing = true;
	address private _tokenETHLP; // maybe just precompute create2 and hardcode too?
	uint private _rewardsRate;
	bool private _voting;
	uint private _lgeStart; // it's not required. remove and replace with hardcoded approximate blocknumbers to save transaction cost for users
	address private constant _WETH = 0x2E9d30761DB97706C536A112B9466433032b28e3;// testing
	address payable private _governance;
	address private _governanceContract;
	uint private _linkLimit;
	uint private _lockTime;
	uint private _reentrancyStatus;
	uint private _rewardsToRecompute;

///////variables for testing purposes
	address private _uniswapFactory = 0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66;
	uint private _rewardsGenesis; // = hardcoded block.number
	address private _token; // = hardcoded address
	address private _lpOraclesFund;
//////
	constructor() {
		_governance = msg.sender;
		_rewardsRate = 63e18; // aprox 1 billion tokens in 7,5 years
		_linkLimit = 1e17; // 0.1 ether
		_token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8; // testing
		_rewardsGenesis = block.number + 5;
		_lockTime = 6307200;
	}

	struct Founder {
		uint ethContributed;
		bool firstClaim;
		uint rewardsLeft;
		uint tokenAmount; // will be required for generic staking if lge rewards run out
		uint lockUpTo;
	}

	mapping(address => Founder) private _founders;
	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _takenAddresses;

	event AddressLinked(address indexed address1, address indexed address2);
	event LiquidityPoolCreated(address indexed liquidityPair);

	modifier onlyFounder() {
		require(_founders[msg.sender].ethContributed > 0 && _reentrancyStatus != 1, "Not a Founder or reentrancy guard");
		_reentrancyStatus = 1;
		_;
		_reentrancyStatus = 0;
	}

	modifier onlyGovernance() { // proposal delegator
		require(msg.sender == _governance, "not governance");
		_;
	}

	modifier onlyGovernanceContract() {
		require(msg.sender == _governanceContract, "not governance contract");
		_;
	}	

	function isFounder(address account) public view returns(bool) {
		if (_founders[account].ethContributed > 0) {return true;} else {return false;}
	}

	function depositEth(bool iAgreeToPublicStringAgreementTerms) external payable {
		require(_lgeOngoing == true && iAgreeToPublicStringAgreementTerms == true, "LGE has already ended or didn't start, or no agreement provided");
		require(msg.value > 0 && _isContract(msg.sender) == false, "amount must be bigger than 0 ot contracts can't be Founders");
		if (_takenAddresses[msg.sender] == true) {
			address linkedAddress = _linkedAddresses[msg.sender];
			delete _linkedAddresses[linkedAddress];
			delete _linkedAddresses[msg.sender];
			delete _takenAddresses[msg.sender];
		}
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_governance.transfer(deployerShare);
		IWETH(_WETH).deposit{value: amount}();
		_founders[msg.sender].ethContributed += amount;
		_totalETHDeposited += amount; // could use WETH balanceOf instead?
		if (block.number >= _rewardsGenesis) {_createLiquidity();}
	}

	function lock() public onlyFounder {
		require(_founders[msg.sender].firstClaim == true, "first you have to claim rewards");
		_founders[msg.sender].lockUpTo = block.number + _lockTime;
	}

	function unstakeLP() public onlyFounder {
		require(_founders[msg.sender].lockUpTo <= block.number && _founders[msg.sender].firstClaim == true && block.number > (_rewardsGenesis + 100000), "tokens locked or claim rewards");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/_totalETHDeposited;
		require(lpShare <= IERC20(_tokenETHLP).balanceOf(address(this)),"withdrawing too much");
		_ETHDeposited = _totalETHDeposited - ethContributed;
		_rewardsToRecompute += _founders[msg.sender].rewardsLeft;
		IERC20(_tokenETHLP).transfer(address(msg.sender), lpShare);
		delete _founders[msg.sender];
	}

	function claimLGERewards() public onlyFounder { // most popular function, has to have first Method Id or close to
		uint rewardsGenesis = _rewardsGenesis;
		require(block.number > rewardsGenesis, "too soon");
		uint rewardsToClaim;
		if (_founders[msg.sender].firstClaim == false) {
			_founders[msg.sender].firstClaim = true;
			uint share = _founders[msg.sender].ethContributed*5e27/_totalETHDeposited;
			_founders[msg.sender].rewardsLeft = share;
			_founders[msg.sender].tokenAmount = share;
			rewardsToClaim = (block.number - rewardsGenesis)*_rewardsRate*share/5e27;
		} else {
			uint tokenAmount = _founders[msg.sender].tokenAmount;
			rewardsToClaim = (block.number - rewardsGenesis)*_rewardsRate*tokenAmount/5e27;
			uint rewardsClaimed = tokenAmount - _founders[msg.sender].rewardsLeft;
			rewardsToClaim = rewardsToClaim.sub(rewardsClaimed);
		}
		require(rewardsToClaim <= IERC20(_token).balanceOf(address(this)), "nothing to claim or withdrawing too much");
		_founders[msg.sender].rewardsLeft -= rewardsToClaim;
		IERC20(_token).transfer(address(msg.sender), rewardsToClaim);
	}

	function migrate(address contract_) public onlyFounder {
		require(_founders[msg.sender].firstClaim == true && _voting == false, "claim rewards before this or voting is ongoing");
		require(_founders[msg.sender].rewardsLeft == 0, "still rewards left");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/_totalETHDeposited;
		IERC20(_tokenETHLP).transfer(_lpOraclesFund, lpShare);
		IlpOraclesFund(_lpOraclesFund).stakeFromLgeContract(msg.sender,lpShare,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);
		delete _founders[msg.sender];
	}

	function changeAddress(address account) public onlyFounder {
		require(_isContract(account) == false && _voting == false, "contracts can't be founders or voting is ongoing");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint rewardsLeft = _founders[msg.sender].rewardsLeft;
		bool firstClaim = _founders[msg.sender].firstClaim;
		uint tokenAmount = _founders[msg.sender].tokenAmount;
		uint lockUpTo = _founders[msg.sender].lockUpTo;
		delete _founders[msg.sender];
		_founders[account].ethContributed = ethContributed;
		_founders[account].rewardsLeft = rewardsLeft;
		_founders[account].firstClaim = firstClaim;
		_founders[account].tokenAmount = tokenAmount;
		_founders[account].lockUpTo = lockUpTo;
	}

	function setRewardsRate(uint rate) public onlyGovernance {
		require(rate >= 50e18 && rate <= 100e18, "can't override hardlimit");
		_rewardsRate = rate;
	}

	function _createLiquidity() internal {
		delete _lgeOngoing;
		_tokenETHLP = IUniswapV2Factory(_uniswapFactory).createPair(_token, _WETH);
		IWETH(_WETH).transfer(_tokenETHLP, IWETH(_WETH).balanceOf(address(this)));
		IERC20(_token).transfer(_tokenETHLP, IERC20(_token).balanceOf(address(this))/6);
		IUniswapV2Pair(_tokenETHLP).mint(address(this));
		_totalLGELPtokensMinted = IUniswapV2Pair(_tokenETHLP).balanceOf(address(this));
		emit LiquidityPoolCreated(_tokenETHLP);
	}

	function setLockTime(uint lockTime_) public onlyGovernance {
		require(lockTime_ >= 6307200 && lockTime_ <= 10512000, "can't override hardlimits"); // between 3 and 5 years
		_lockTime = lockTime_;
	}

	function _isContract(address account) internal view returns (bool) {
			uint256 size;
			assembly { size := extcodesize(account) }
			return size > 0;
	}

	function setGovernance(address payable account) public onlyGovernance {
		_governance = account;
	}

	function setGovernanceContract(address account) public onlyGovernance {
		_governanceContract = account;
	}

	function toggleVoting() public onlyGovernanceContract {
		if (_voting == false) {_voting = true;} else {_voting = false;}
	}

	function recomputeRewardsLeft() public onlyFounder {
		if(_rewardsToRecompute > 0) {
			uint share = _founders[msg.sender].ethContributed*rewardsToRecompute/_ETHDeposited;
			_founders[msg.sender].rewardsLeft += share;
		}
	}

// VIEW FUNCTIONS ========================================================================================

	function getFounder(address account) external view returns (uint ethContributed, uint rewardsLeft, bool firstClaim, uint tokenAmount, uint lockUpTo) {
		return (_founders[account].ethContributed,_founders[account].rewardsLeft,_founders[account].firstClaim,_founders[account].tokenAmount,_founders[account].lockUpTo);
	}
	function getLgeInfo() external view returns (bool lgeOng,uint rewGenesis,uint rewRate,uint totalEthDepos) {
		return (_lgeOngoing,_rewardsGenesis,_rewardsRate,_totalETHDeposited);
	}

// IN CASE OF SPAM BOTS ============================================

	function linkAddress(address account) external onlyFounder { // can be used to limit the amount of testers to only approved addresses
		require(_linkedAddresses[msg.sender] != account && _takenAddresses[account] == false, "already linked these or somebody already uses this");
		require(isFounder(account) == false && _founders[msg.sender].ethContributed >= _linkLimit, "can't link founders or not enough eth deposited");
		if (_linkedAddresses[msg.sender] != address(0)) {
			address linkedAddress = _linkedAddresses[msg.sender];
			delete _linkedAddresses[msg.sender];
			delete _linkedAddresses[linkedAddress];
			delete _takenAddresses[linkedAddress];
		}
		_linkedAddresses[msg.sender] = account;
		_linkedAddresses[account] = msg.sender;
		_takenAddresses[account] = true;
		emit AddressLinked(msg.sender,account);
	}

	function setLinkLimit(uint value) external onlyGovernance {
		require(value >= 0 && value < 1e18, "can't override hard limit");
		_linkLimit = value;
	}
}
