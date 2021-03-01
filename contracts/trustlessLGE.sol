pragma solidity >=0.6.0;

// Author: Sam Porter

// What CORE team did is something really interesting, with LGE it's now possible 
// to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// As you can see, blockchain needs no VCs, no authorities.
// Minimized the code a bit in case if publishing a contract will cost a small fortune for you, will publish trustlessLGEmin.sol too

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ILGE2.sol";
import "./IlpOraclesFund.sol";
import "./IWETH.sol";
import "./IERC20.sol";

contract FoundingEvent {
	using SafeMath for uint;


	string public agreementTerms = "I understand that this contract is provided with no warranty of any kind. \n I agree to not hold the contract creator, RAID team members or anyone associated with this event liable for any damage monetary and otherwise I might onccur. \n I understand that any smart contract interaction carries an inherent risk.";
	uint private _totalETHDeposited;
	uint private _totalLGELPtokensMinted;
	uint private _totalLGEStaked;
	bool private _lgeOngoing = true;
	address private _tokenETHLP; // maybe just precompute create2 and hardcode too?
	uint private _rewardsRate;
	address private _approvedContract;
	address private _proposedContract;
	bool private _voting;
	bool private _canPropose = true;
	uint private _minimumRequiredVotes;
	uint private _lgeStart; // it's not required. remove and replace with hardcoded approximate blocknumbers to save transaction cost for users
	uint private _totalRewardsLeft;
	address private constant _WETH = 0x2E9d30761DB97706C536A112B9466433032b28e3;// testing
	address payable private _governance;
	uint private _votingEnd;
	uint private _totalVotes;
	uint private _linkLimit;
	uint private _lockTime;
	bool private _reentrancyStatus;

///////variables for testing purposes
	address private _uniswapFactory = 0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66;
	uint private _rewardsGenesis; // = hardcoded block.number
	address private _token; // = hardcoded address
	address private _lpOraclesFund;
//////
	constructor() {
		_governance = msg.sender;
		_totalRewardsLeft = 1e27;
		_rewardsRate = 95e18; // aprox 1 billion tokens in 5 years
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

	mapping(address => bool) private _votedAddresses;

	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _takenAddresses;
	mapping (address => bool) private _agreements;

	event AddressLinked(address indexed address1, address indexed address2);
	event ContractApproved(address indexed approvedContract);
	event LiquidityPoolCreated(address indexed liquidityPair);

	modifier onlyFounder() {
		require(_founders[msg.sender].ethContributed > 0 && _reentrancyStatus != 1, "Not an Founder or reentrant call");
        _reentrancyStatus = 1;
		_;
		_reentrancyStatus = 0;
	}

	modifier onlyGovernance() {
		require(msg.sender == _governance, "not governance");
		_;
	}

	function isFounder(address account) public view returns(bool) {
		if (_founders[account].ethContributed > 0) {return true;} else {return false;}
	}

	function depositEth(bool iAgreeToPublicStringAgreementTerms) external payable {
		require(_lgeOngoing == true && iAgreeToPublicStringAgreementTerms == true, "LGE has already ended or didn't start, or no agreement provided");
		require(msg.value > 0 && _isContract(msg.sender) == false, "amount must be bigger than 0 ot contracts can't be Founders");
		if (_takenAddresses[msg.sender] == true) {
			_takenAddresses[msg.sender] = false;
			address linkedAddress = _linkedAddresses[msg.sender];
			if (linkedAddress != address(0)) {
				_linkedAddresses[msg.sender] = address(0);
				_linkedAddresses[linkedAddress] = address(0);
			}
		}
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_governance.transfer(deployerShare);
		uint contribution = _founders[msg.sender].ethContributed;
		uint recentTotalContribution = contribution + amount;
		IWETH(_WETH).deposit{value: amount}();
		if (recentTotalContribution >= 1e18 && recentTotalContribution >= contribution) {
			_minimumRequiredVotes += (recentTotalContribution*13/20) - (contribution*13/20);
		}
		_founders[msg.sender].ethContributed += amount;
		_totalETHDeposited += amount; // could use WETH balanceOf instead?
		if (block.number >= _rewardsGenesis) {_createLiquidity();}
	}

	function lock() public onlyFounder {
		require(_founders[msg.sender].firstClaim == true, "first you have to claim rewards");
		_founders[msg.sender].lockUpTo = block.number + _lockTime;
	}

	function unstakeLP() public onlyFounder {
		require(_founders[msg.sender].lockUpTo <= block.number && _founders[msg.sender].firstClaim == true && _approvedContract == address(0), "tokens locked or need to claim first or migration is in the process");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/_totalETHDeposited;
		require(lpShare <= IERC20(_tokenETHLP).balanceOf(address(this)),"withdrawing too much");
		IERC20(_tokenETHLP).transfer(address(msg.sender), lpShare);
		_minimumRequiredVotes = _minimumRequiredVotes.sub(ethContributed*13/20);
		if (_votedAddresses[msg.sender] == true) {
			_totalVotes = _totalVotes.sub(ethContributed*13/20);
		}
		delete _founders[msg.sender];
	}

	function claimLGERewards() public onlyFounder { // most popular function, has to have first Method Id or close to
		uint rewardsGenesis = _rewardsGenesis;
		require(_approvedContract == address(0) && block.number > rewardsGenesis, "too soon or migration is in the process, claim from new contract");
		if (_founders[msg.sender].firstClaim == false) {
			_founders[msg.sender].firstClaim = true;
			uint share = _founders[msg.sender].ethContributed*1e27/_totalETHDeposited;
			_founders[msg.sender].rewardsLeft = share; // could use inaccurate storage in uint64?
			_founders[msg.sender].tokenAmount = share;
			uint rewardsToClaim = (block.number - rewardsGenesis)*_rewardsRate*share/1e27;
		} else {
			uint tokenAmount = _founders[msg.sender].tokenAmount;
			uint rewardsToClaim = (block.number - rewardsGenesis)*_rewardsRate*tokenAmount/1e27;
			uint rewardsClaimed = tokenAmount - _founders[msg.sender].rewardsLeft;
			rewardsToClaim = rewardsToClaim.sub(rewardsClaimed);
		}
		require(rewardsToClaim > 0 && rewardsToClaim <= IERC20(_token).balanceOf(address(this)), "nothing to claim or withdrawing too much");
		_founders[msg.sender].rewardsLeft = _founders[msg.sender].rewardsLeft.sub(rewardsToClaim);
		IERC20(_token).transfer(address(msg.sender), rewardsToClaim);
	}

	function migrate(address contract_) public onlyFounder {
		require(_founders[msg.sender].firstClaim == true, "claim your first rewards before calling this function");
		if (contract_ == _lpOraclesFund) {
			require(_founders[msg.sender].rewardsLeft == 0, "still rewards here left");
			uint ethContributed = _founders[msg.sender].ethContributed;
			uint lpShare = _totalLGELPtokensMinted*ethContributed/_totalETHDeposited;
			IlpOraclesFund(_lpOraclesFund).stakeFromLgeContract(msg.sender,lpShare,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);
			delete _founders[msg.sender];
			_minimumRequiredVotes = _minimumRequiredVotes.sub(ethContributed*13/20);
			if (_votedAddresses[msg.sender] == true) {
				_totalVotes = _totalVotes.sub(ethContributed*13/20);
			}
		} else if (contract_ == _approvedContract && contract != address(0)) {
			ILGE2(contract).migrate(msg.sender,_founders[msg.sender].ethContributed,_founders[msg.sender].rewardsLeft,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);
			delete _founders[msg.sender];
		} else {revert();}
	}

	function changeAddress(address account) public onlyFounder {
		require(_voting == false && _isContract(account) == false, "can't change during voting or contracts can't be founders");
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
		_lgeOngoing = false;
		_tokenETHLP = IUniswapV2Factory(_uniswapFactory).getPair(_token, _WETH); // should return address(0) anyway, but no investor wants epic fail
        if(_tokenETHLP == address(0)) {
            _tokenETHLP = IUniswapV2Factory(_uniswapFactory).createPair(_token, _WETH);
        }
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
// VIEW FUNCTIONS ========================================================================================

	function getFounder(address account) external view returns (uint ethContributed, uint rewardsLeft, bool firstClaim, uint tokenAmount, uint lockUpTo) {
		return (_founders[account].ethContributed,_founders[account].rewardsLeft,_founders[account].firstClaim,_founders[account].tokenAmount,_founders[account].lockUpTo);
	}
	function getLGEOngoing() external view returns (bool) {return _lgeOngoing;}
	function getRewardsGenesis() external view returns (uint) {return _rewardsGenesis;}
	function getRewardsRate() external view returns (uint) {return _rewardsRate;}
	function getTotalETHDeposited() external view returns (uint) {return _totalETHDeposited;}

// IN CASE OF A BUG IN THIS CONTRACT =====================================================================
// There is nothing fancy in the code, but let this be here just for investors' confidence.
	function setGovernance(address payable account) public onlyGovernance {
		_governance = account;
	}

	function proposeContract(address contract_) public onlyGovernance {
		require(_canPropose == true && block.number >= (_lgeStart + 180000), "previous voting is not yet finished or too soon");
		_proposedContract = contract_;
		_voting = true;
		_canPropose = false;
		_votingEnd = block.number + 10; // 90000 a bit less than two weeks
		_rewardsGenesis += 180000;
	}

	function voteForProposedContract() public onlyFounder {
		require(_founders[msg.sender].ethContributed > 1e18 && _voting == true && _votedAddresses[msg.sender] == false, "not enough eth deposited or nothing to vote for or already voted");
		_votedAddresses[msg.sender] = true;
		_totalVotes += _founders[msg.sender].ethContributed;
		if (block.number >= _votingEnd || _totalVotes >= _minimumRequiredVotes) {_resolveVoting();}
	}

	function _resolveVoting() internal {
		_voting = false;
		_canPropose = true;
		_votingEnd = 0;
		if (_totalVotes >= _minimumRequiredVotes) {
			_approvedContract = _proposedContract;
			address approvedContract = _approvedContract;
			address token = _token;
			address WETH = _WETH;
			address tokenETHLP = _tokenETHLP;
			if (IERC20(WETH).balanceOf(address(this)) > 0) {
				IERC20(WETH).transfer(approvedContract, IERC20(WETH).balanceOf(address(this)));
			}
			if (tokenETHLP != address(0) && IERC20(tokenETHLP).balanceOf(address(this)) > 0) {
				IERC20(tokenETHLP).transfer(approvedContract, IERC20(tokenETHLP).balanceOf(address(this)));
			}
			if (IERC20(token).balanceOf(address(this)) > 0) {
				IERC20(token).transfer(approvedContract, IERC20(token).balanceOf(address(this)));	
			}
			emit ContractApproved(approvedContract);
		}
		_totalVotes = 0;
	}

	function resetVotingPowerForNextVote() public onlyFounder { // very unlikely to be ever required
		require(_voting == false && _votedAddresses[msg.sender] == true, "voting is ongoing or wasn't voting");
		_votedAddresses[msg.sender] = false;
	}

// IN CASE OF SPAM BOTS OVERLOADING TESTNET FOR LEGIT TESTERS ============================================

	function linkAddress(address account) external onlyFounder { // can be used to limit the amount of testers to only approved addresses
		require(_linkedAddresses[msg.sender] != account && _takenAddresses[account] == false, "already linked these or somebody already uses this");
		require(isFounder(account) == false && _founders[msg.sender].ethContributed >= _linkLimit, "can't link founders or not enough eth deposited");
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
