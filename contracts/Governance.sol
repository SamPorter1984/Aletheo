pragma solidity >=0.7.0;
// Author: SamPorter1984
// For now architecture sucks, this contract is probably insecure
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

	struct Voter {uint128 votingPower;uint128 lock;uint128 totalVotingPower;uint128 lastPrivelegeCheck;uint lastVoted;}

	mapping(address => Voter) private _voters;
	mapping(uint => Proposal) public prpsls;

	constructor(){_initializer = msg.sender;} // a way for anybody to deploy logic, propose it as an upgrade, except it depends on particular case, sometimes initializer has to be proxyAdmin
	function init() public {require(msg.sender == _initializer); delete _initializer;}

	function propose(address dstntn,bytes memory dt) public {// probably propose will mostly be oracles job in the future of this governance
		uint vote;
		if(block.number < _voters[msg.sender].lastPrivelegeCheck + 172800) {vote = _voters[msg.sender].totalVotingPower;} else {vote = _voters[msg.sender].votingPower;}
		require(vote > 10000e18 && dstntn != address(0) && dt.length > 0 && _voters[msg.sender].lock - 1036800 >= block.number);
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
		uint vote;
		if(block.number < _voters[msg.sender].lastPrivelegeCheck + 172800) {vote = _voters[msg.sender].totalVotingPower;} else {vote = _voters[msg.sender].votingPower;} 
		require(block.number<prpsls[id].endBlock&&vote>0&&prpsls[id].votes[msg.sender]==false&&_voters[msg.sender].lock-1036800>=block.number&&_voters[msg.sender].lastVoted+10<block.number);
		_voters[msg.sender].lastVoted = block.number;
		if(support==true) {prpsls[id].forVotes += uint40(vote/1e18);} else {prpsls[id].againstVotes += vote;}
		prpsls[id].votes[msg.sender] = true;
	}

	function resolveVoting(uint id) external {
		uint forVotes = prpsls[id].forVotes;
		require(forVotes*1e18>=500e24 && block.number>=prpsls[id].endBlock && prpsls[id].executed == false);//500 mil, not sure about this number
		prpsls[id].executed = true;
		uint totalVotes = forVotes*1e18 + prpsls[id].againstVotes;
		uint percent = 100*forVotes/totalVotes;
		if(percent > 60) {_execute(id);}
	}

	function checkPrivelege() external { // i still think it's suboptimal. could instead use earliestLock variable or something
		require(_voters[msg.sender].lastPrivelegeCheck+100000 < block.number);
		_voters[msg.sender].lastPrivelegeCheck = uint128(block.number);
		uint votingPower = _voters[msg.sender].votingPower;
		(uint amount,uint lock) = IStaking(_staking).getTknAmntLckPt(msg.sender);
		if (lock == 0 || lock - 1036800 < block.number) {amount = 0;}
		_voters[msg.sender].totalVotingPower = uint128(votingPower + amount);
	}

	function changeAddress(address oldAccount,address newAccount) external {//can change address only if didn't vote for a month. that's cheaper than creating iteration through all prpsls
		require(msg.sender == _staking);
		_voters[newAccount].lastVoted = block.number;
		uint128 votingPower = _voters[oldAccount].votingPower;
		uint128 lock = _voters[oldAccount].lock;
		delete _voters[oldAccount];
		if (votingPower != 0) {_voters[newAccount].votingPower = votingPower;_voters[newAccount].lock = lock;}
	}

	function getLastVoted(address account) external view returns(uint lstVtd) {return _voters[account].lastVoted;}
	function _execute(uint id) internal{address dstntn = prpsls[id].destination;bytes memory dt = prpsls[id].data;dstntn.call(dt);emit ExecuteProposal(id,dstntn,dt);}
	function _isContract(address account) internal view returns(bool) {uint256 size;assembly {size := extcodesize(account)}return size > 0;}
}
