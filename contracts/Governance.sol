pragma solidity >=0.7.0;
// Author: SamPorter1984
// You could find some resemblance with Compound governance. It's heavily modified, simplified, cheaper version with very high minimum quorum.
// Again, as little store writes as possible, accuracy is expensive, therefore it's cheaper to allow founders and liquidity providers
// freely check their privelege regularly, instead of maintaining expensive accurate computation.
// This version is not fundamentally pure yet.
import "./ITreasury.sol";
import "./IFoundingEvent.sol";
import "./IERC20.sol";

contract Governance {
	event ProposalCreated(uint id, address proposer, address destination, bytes data, uint endBlock);
	event ExecuteProposal(uint id,address dstntn,bytes dt);
	
	struct Proposal {
		address destination;
		uint endBlock;
		bool executed;
		uint forVotes;
		uint againstVotes;
		bytes data;
		mapping (address => bool) votes;
	}

	uint private _proposalCount;
	address private _initializer;
	address private _token;
	address private _founding;
	address private _treasury;
	mapping(address => uint) private _votingPower;
	mapping(address => uint) private _totalVotingPower;
	mapping(address => uint) private _lock;
	mapping(address => uint) private _lastPrivelegeCheck;
	mapping(address => uint) private _lastVoted;
	mapping(uint => Proposal) public proposals;
	bool private _l;

	constructor(){_initializer = msg.sender;} // anybody can deploy logic to propose it as an upgrade, except it depends on particular case, it could be initializer has to be proxyAdmin
	function init() public {require(msg.sender == _initializer); delete _initializer;}

	function propose(address dstntn,bytes memory dt) public {
		uint vote;
		if(block.number < _lastPrivelegeCheck[msg.sender] + 172800) {vote = _totalVotingPower[msg.sender];} else {vote = _votingPower[msg.sender];}
		require(vote > 10000e18 && dstntn != address(0) && dt.length > 0 && _lock[msg.sender] - 1036800 >= block.number);
		_proposalCount++;
		uint id = _proposalCount;
		uint endBlock = block.number + 172800;
		proposals[id].destination = dstntn;
		proposals[id].endBlock = endBlock;
		proposals[id].data = dt;
		proposals[id].forVotes = vote;
		proposals[id].votes[msg.sender] = true;		
		emit ProposalCreated(id, msg.sender, dstntn, dt, endBlock);
	}

	function castVote(uint id, bool support) external {
		uint vote;
		if(block.number < _lastPrivelegeCheck[msg.sender] + 172800) {vote = _totalVotingPower[msg.sender];} else {vote = _votingPower[msg.sender];} 
		require(block.number<proposals[id].endBlock&&vote>0&&proposals[id].votes[msg.sender]==false&&_lock[msg.sender]-1036800>=block.number&&_lastVoted[msg.sender]+10<block.number);
		_lastVoted[msg.sender] = block.number;
		if(support==true) {proposals[id].forVotes += vote;} else {proposals[id].againstVotes += vote;}
		proposals[id].votes[msg.sender] = true;
	}

	function lockFor3years(uint amount, bool ok) external {
		require(ok == true && IERC20(_token).balanceOf(msg.sender) >= amount);
		IERC20(_token).transferFrom(msg.sender,address(this),amount);
		_votingPower[msg.sender] += amount;
		_lock[msg.sender] += 6307200;
	}

	function unstake(uint amount) external {
		require(_votingPower[msg.sender] >= amount && block.number>=_lock[msg.sender] && _l == false);
		_l = true;
		_votingPower[msg.sender] -= amount;
		IERC20(_token).transfer(msg.sender,amount);
		_l = false;
	}

	function resolveVoting(uint id) external {
		uint forVotes = proposals[id].forVotes;
		require(forVotes>=500e24 && block.number>=proposals[id].endBlock && proposals[id].executed == false);//500 mil, depends on founders if there will be any executed proposals in first year
		proposals[id].executed = true;
		uint totalVotes = forVotes + proposals[id].againstVotes;
		uint percent = 100*forVotes/totalVotes;
		if(percent > 60) {_execute(id);}
	}

	function checkPrivelege() external {
		require(_lastPrivelegeCheck[msg.sender]+100000 < block.number);
		_lastPrivelegeCheck[msg.sender] = block.number;
		uint totalVotingPower = 0;
		(uint amount,uint lock) = IFoundingEvent(_founding).getFounderTknAmntLckPt(msg.sender);
		if (lock == 0 || lock - 1036800 < block.number) {amount = 0;} 
		totalVotingPower= _votingPower[msg.sender] + amount;
		(amount,lock) = ITreasury(_treasury).getTknAmntLckPt(msg.sender);
		if (lock == 0 || lock - 1036800 < block.number) {amount = 0;} 
		totalVotingPower += amount;
		_totalVotingPower[msg.sender] = totalVotingPower;
	}

	function getLastVoted(address account) external view returns(uint lstVtd) {return _lastVoted[account];}

	function changeAddress(address oldAccount,address newAccount) external {
		_lastVoted[newAccount] = block.number;
		_votingPower[newAccount] = _votingPower[oldAccount];
		_lock[newAccount] = _lock[oldAccount];
		delete _votingPower[oldAccount];
		delete _lock[oldAccount];
		delete _lastVoted[oldAccount];
	}

	function _execute(uint id) internal{
		address dstntn = proposals[id].destination;
		bytes memory dt = proposals[id].data;
		dstntn.call(dt);
		emit ExecuteProposal(id,dstntn,dt);
	}
}
