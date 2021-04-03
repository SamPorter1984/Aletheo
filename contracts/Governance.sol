pragma solidity >=0.7.0;
// You could find some resemblance with Compound governance. It's heavily modified, simplified, cheaper version with very high minimum quorum.
// Again, as little store writes as possible, accuracy is expensive, therefore it's cheaper to allow founders and liquidity providers
// freely check their privelege regularly, instead of maintaining expensive accurate computation.
// This version is not fundamentally pure yet. Also I didn't yet thought very well about minimum quorum, in here it's crazy, but the contract is upgradeable before deadline, so.
// The contract might never be published on mainnet, maybe we need to finalize governance model first
import "./IStaking.sol";

contract Governance {
	event ProposalCreated(uint id, address proposer, address destination, bytes data, uint endBlock);
	event ExecuteProposal(uint id,address dstntn,bytes dt);
	
	struct Proposal {
		address destination;//a consideration to increase address length to 32 exists, it's somewhere on ethresearch or ethereum magicians
		uint48 endBlock;
		uint40 forVotes;
		bool executed;
		bytes data;
		uint againstVotes;
		mapping (address => bool) votes;
	}

	uint private _proposalCount;
	address private _initializer;
	address private _staking;

	struct Voter {uint96 votingPower; uint80 nextPrivelegeCheck; uint80 lastVoted;}

	mapping(address => Voter) private _voters;
	mapping(uint => Proposal) public prpsls;

	constructor(){}
	function init() public {require(msg.sender == _initializer); delete _initializer;}

	function propose(address dstntn,bytes memory dt) public {// probably propose will mostly be oracles job in the future of this governance
		uint vote = _voters[msg.sender].votingPower;
		uint privelegeCheck = _voters[msg.sender].nextPrivelegeCheck;
		require(vote > 10000e18 && dstntn != address(0) && dt.length > 0 && privelegeCheck - 1036800 >= block.number);
		_proposalCount++;
		uint id = _proposalCount;
		uint endBlock = block.number + 172800;
		prpsls[id].destination = dstntn;
		prpsls[id].endBlock = uint48(endBlock);
		prpsls[id].forVotes = uint40(vote/1e18);
		prpsls[id].votes[msg.sender] = true;
		prpsls[id].data = dt;
		emit ProposalCreated(id, msg.sender, dstntn, dt, endBlock);
	}

	function expressOpinionBasicallyVote(uint id, bool support) external {//method id: 0ed1d7ec
		uint vote = _voters[msg.sender].votingPower;
		uint lastVoted = _voters[msg.sender].lastVoted;
		uint privelegeCheck = _voters[msg.sender].nextPrivelegeCheck;
		require(block.number<prpsls[id].endBlock&&vote>0&&prpsls[id].votes[msg.sender]==false&&privelegeCheck>=block.number&&lastVoted+10<block.number);
		_voters[msg.sender].lastVoted = block.number;
		if(support==true) {prpsls[id].forVotes += uint40(vote/1e18);} else {prpsls[id].againstVotes += vote;}
		prpsls[id].votes[msg.sender] = true;
	}

	function resolveVoting(uint id) external {
		uint forVotes = prpsls[id].forVotes;
		require(forVotes*1e18>=300e21 && block.number>=prpsls[id].endBlock && prpsls[id].executed == false);//300k
		prpsls[id].executed = true;
		uint totalVotes = forVotes*1e18 + prpsls[id].againstVotes;
		uint percent = 100*forVotes/totalVotes;
		if(percent > 60) {_execute(id);}
	}

	function checkPrivelege() external {
		(uint128 tknAmount, uint128 lpShare,uint128 lockedAmount,uint128 lockUpTo,uint128 amount,uint128 tLockUpTo) = IStaking(_staking).getVoter(msg.sender);
		require(lockUpTo>block.number || tLockUpTo>block.number);
		uint votingPower;
		if (lockUpTo > block.number){votingPower = lockedAmount*tknAmount/lpShare;}
		if (tLockUpTo > block.number){votingPower += amount;}
		if (lockUpTo < tLockUpTo){lockUpTo = tLockUpTo;}
		_voters[msg.sender].votingPower = uint80(votingPower);
		_voters[msg.sender].nextPrivelegeCheck = uint80(lockUpTo-1036800);
	}

	function getLastVoted(address account) external view returns(uint lstVtd) {return _voters[account].lastVoted;}
	function _execute(uint id) internal{address dstntn = prpsls[id].destination;bytes memory dt = prpsls[id].data;dstntn.call(dt);emit ExecuteProposal(id,dstntn,dt);}
	function _isContract(address account) internal view returns(bool) {uint256 size;assembly {size := extcodesize(account)}return size > 0;}
}
