pragma solidity >=0.7.0;
// Author: SamPorter1984
// You could find some resemblance with Compound governance. It's heavily modified, simplified, cheaper version with very high minimum quorum.
// Again, as little store writes as possible, accuracy is expensive, therefore it's cheaper to allow founders and liquidity providers
// freely check their privelege regularly, instead of maintaining expensive accurate computation.
// This version is not fundamentally pure yet. Also I didn't yet thought very well about minimum quorum, in here it's crazy, but the contract is upgradeable before deadline, so.
import "./ITreasury.sol";
import "./IFoundingEvent.sol";
import "./IERC20.sol";

contract Governance is IGovernance {
	event ProposalCreated(uint id, address proposer, address destination, bytes data, uint endBlock);
	event ExecuteProposal(uint id,address dstntn,bytes dt);
	
	struct Proposal {
		address destination;//a consideration to increase address length to 32 exists, it's somewhere on ethresearch or ethereum magicians
		uint96 endBlock;
		bytes data;
		uint forVotes;
		bool executed;
		uint againstVotes;
		mapping (address => bool) votes;
	}

	uint private _proposalCount;
	address private _initializer;
	address private _token;
	address private _founding;
	address private _treasury;

	struct Voter {
		uint128 votingPower;
		uint128 lock;
		uint128 totalVotingPower;
		uint128 lastPrivelegeCheck;
		uint lastVoted;
	}
	mapping(address => Voter) private _voters;
	mapping(address => uint) private _votingPower;
	mapping(address => uint) private _totalVotingPower;
	mapping(address => uint) private _lock;
	mapping(address => uint) private _lastPrivelegeCheck;
	mapping(address => uint) private _lastVoted;
	mapping(uint => Proposal) public proposals;

	constructor(){_initializer = msg.sender;} // a way for anybody to deploy logic, propose it as an upgrade, except it depends on particular case, sometimes initializer has to be proxyAdmin
	function init() public {require(msg.sender == _initializer); delete _initializer;}

	function propose(address dstntn,bytes memory dt) public {// probably propose will mostly be oracles job in the future of this governance
		uint vote;
		if(block.number < _voters[msg.sender].lastPrivelegeCheck + 172800) {vote = _voters[msg.sender].totalVotingPower;} else {vote = _voters[msg.sender].votingPower;}
		require(vote > 10000e18 && dstntn != address(0) && dt.length > 0 && _voters[msg.sender].lock - 1036800 >= block.number);
		_proposalCount++;
		uint id = _proposalCount;
		uint endBlock = block.number + 172800;
		proposals[id].destination = dstntn;
		proposals[id].endBlock = uint96(endBlock);
		proposals[id].data = dt;
		proposals[id].forVotes = vote;
		proposals[id].votes[msg.sender] = true;
		emit ProposalCreated(id, msg.sender, dstntn, dt, endBlock);
	}

	function castVote(uint id, bool support) external {
		uint vote;
		if(block.number < _voters[msg.sender].lastPrivelegeCheck + 172800) {vote = _voters[msg.sender].totalVotingPower;} else {vote = _voters[msg.sender].votingPower;} 
		require(block.number<proposals[id].endBlock&&vote>0&&proposals[id].votes[msg.sender]==false&&_voters[msg.sender].lock-1036800>=block.number&&_voters[msg.sender].lastVoted+10<block.number);
		_voters[msg.sender].lastVoted = block.number;
		if(support==true) {proposals[id].forVotes += vote;} else {proposals[id].againstVotes += vote;}
		proposals[id].votes[msg.sender] = true;
	}

	function lockFor3years(uint128 amount, bool ok) external {
		require(ok == true && IERC20(_token).balanceOf(msg.sender) >= amount && _isContract(msg.sender) == false);
		IERC20(_token).transferFrom(msg.sender,address(this),amount);
		_voters[msg.sender].votingPower += amount;
		_voters[msg.sender].lock = uint128(block.number + 6307200);
	}

	function unstake(uint128 amount) external {
		require(_voters[msg.sender].votingPower>=amount&&block.number>=_voters[msg.sender].lock);_voters[msg.sender].votingPower -= amount;IERC20(_token).transfer(msg.sender,amount);
	}

	function resolveVoting(uint id) external {
		uint forVotes = proposals[id].forVotes;
		require(forVotes>=500e24 && block.number>=proposals[id].endBlock && proposals[id].executed == false);//500 mil, not sure about this number
		proposals[id].executed = true;
		uint totalVotes = forVotes + proposals[id].againstVotes;
		uint percent = 100*forVotes/totalVotes;
		if(percent > 60) {_execute(id);}
	}

	function checkPrivelege() external { // i still think it's suboptimal
		require(_voters[msg.sender].lastPrivelegeCheck+100000 < block.number);
		_voters[msg.sender].lastPrivelegeCheck = uint128(block.number);
		uint totalVotingPower = _voters[msg.sender].votingPower;
		(uint amount,uint lock) = IFoundingEvent(_founding).getFounderTknAmntLckPt(msg.sender);
		if (lock == 0 || lock - 1036800 < block.number) {amount = 0;}
		totalVotingPower += amount;
		(amount,lock) = ITreasury(_treasury).getTknAmntLckPt(msg.sender);
		if (lock == 0 || lock - 1036800 < block.number) {amount = 0;}
		_voters[msg.sender].totalVotingPower = uint128(totalVotingPower + amount);
	}

	function changeAddress(address oldAccount,address newAccount) external {//can change address only if didn't vote for a month. that's cheaper than creating iteration through all proposals
		_voters[newAccount].lastVoted = block.number;
		uint128 votingPower = _voters[oldAccount].votingPower;
		uint128 lock = _voters[oldAccount].lock;
		delete _voters[oldAccount];
		if (votingPower != 0) {_voters[newAccount].votingPower = votingPower;_voters[newAccount].lock = lock;}
	}

	function getLastVoted(address account) external view returns(uint lstVtd) {return _lastVoted[account];}
	function _execute(uint id) internal{address dstntn = proposals[id].destination;bytes memory dt = proposals[id].data;dstntn.call(dt);emit ExecuteProposal(id,dstntn,dt);}
	function _isContract(address account) internal view returns(bool) {uint256 size;assembly {size := extcodesize(account)}return size > 0;}
}
