pragma solidity >=0.7.0;

contract DatabaseTestnet {
	address private _governance;
	bool private _approvalRequired;
	uint private _periodCounter;

	struct Period {uint startBlock; uint endBlock;}

	mapping (uint => Period) private _periods;
	mapping (address => uint96) private _blockNumbers;
	mapping (address => bool) private _oracles;
	mapping (address => uint) private _founders;// ethContributed // only for public testnet
	mapping (address => bool) private _takenAddresses;
	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _workers;

	event Entry(address indexed addressFrom, bytes32 indexed hash, string entry);
	event WorkerAdded(address indexed account);
	event AddressLinked(address indexed address1, address indexed address2);
	event NewPeriod(uint id, uint startBlock, uint endBlock);

	constructor() {_governance = msg.sender;}

	modifier onlyOracle() {require(_oracles[msg.sender] == true, "not an oracle");_;}
	modifier onlyGovernance() {require(msg.sender == _governance, "not a governance address");_;}
	modifier onlyFounder() {require(_founders[msg.sender] > 0, "Not a Founder");_;}

	function recordEntry(bytes32 _hash, string memory _entry) public { // method id
		require(_blockNumbers[msg.sender] + 25 >= block.number, "too early"); // mandatory for testnet
		if (_approvalRequired == false) {_blockNumbers[msg.sender] = block.number;emit Entry(msg.sender, _hash, _entry);}
		else if (_workers[msg.sender] == true) {_blockNumbers[msg.sender] = block.number;emit Entry(msg.sender, _hash, _entry);}
	}

	function newPeriod(uint startB, uint endB) public onlyOracle {
		_periodCounter++;
		_periods[_periodCounter].startBlock = startB;
		_periods[_periodCounter].endBlock = endB;
		emit NewPeriod(_periodCounter,startB,endB);
	}

	function toggleFounder(address account) public onlyOracle {if (_founders[account] == false) {_founders[account] = true;emit FounderAdded(account);} else {delete _founders[account];}}
	function toggleWorker(address account) public onlyOracle {if (_workers[account] == false) {_workers[account] = true;emit WorkerAdded(account);} else {delete _workers[account];}}
	function toggleOracle(address account) public onlyGovernance {if (_oracles[account] == false) {_oracles[account] = true;} else {delete _oracles[account];}}
	function setGovernance(address account) public onlyGovernance {_governance = account;}
	function toggleApprovalRequired() public onlyGovernance {if (_approvalRequired == false) {_approvalRequired = true;} else {delete _approvalRequired;}}
	function linkAddressByOracle(address founder, address worker) external onlyOracle {_linkAddress(founder, worker);}
	function linkAddress(address worker) external onlyFounder {_linkAddress(msg.sender, worker);}
	function _isFounder(address account) internal view returns(bool) {if (_founders[account].ethContributed > 0) {return true;} else {return false;}}

	function _linkAddress(address founder, address worker) external { // can be used to limit the amount of testers to only approved addresses
		require(_linkedAddresses[founder] != worker && _takenAddresses[worker] == false, "already linked these or somebody already uses this");
		require(_isFounder(worker) == false && _founders[founder] >= _linkLimit, "can't link founders or not enough eth deposited");
		if (_linkedAddresses[founder] != address(0)) {
			address linkedAddress = _linkedAddresses[founder]; delete _linkedAddresses[founder]; delete _linkedAddresses[linkedAddress]; delete _takenAddresses[linkedAddress];
		}
		_linkedAddresses[founder] = worker;
		_linkedAddresses[worker] = founder;
		_takenAddresses[worker] = true;
		if (_workers[worker] != true) {_workers[worker] == true; emit WorkerAdded(worker);}
		emit AddressLinked(founder,worker);
	}
	function getAddress(address account) public view returns(bool worker, bool founder, address linked, bool taken, bool oracle, uint lastEntryBlock) {
		return (_workers[account],_founders[account],_linkedAddresses[account],_takenAddresses[account],_oracles[account],_blockNumbers[account]);
	}

	function getSettings() public view returns(bool appr, address gov, uint period, uint startB, uint endB) {
		return (_approvalRequired,_governance,_periodCounter,_periods[_periodCounter].startBlock,_periods[_periodCounter].endBlock);
	}
}
