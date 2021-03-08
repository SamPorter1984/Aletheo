pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;
// not critically important for this contract to be clean on the testnet, and it's disposable by design anyway. but hopefully it's good already,
// so that it could create a good look i guess
// could make sense to make it upgradeable for starters, so it won't be required to update contract address everywhere. then after a while deploy
// non-upgradeable finilized version
contract DatabaseTestnet {
	address private _governance;
	bool private _approvalRequired;
	uint private _periodCounter;
	uint private _linkLimit;
	struct Period {uint startBlock; uint endBlock;}

	mapping (uint => Period) private _periods;
	mapping (address => uint) private _blockNumbers;
	mapping (address => bool) private _oracles;
	mapping (address => uint) private _founders;// ethContributed // only for public testnet
	mapping (address => bool) private _takenAddresses;
	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _workers;

	event Entry(address indexed addressFrom, bytes32 indexed hash, string entry);
	event WorkerAdded(address indexed account);
	event AddressLinked(address indexed address1, address indexed address2);
	event NewPeriod(uint id, uint startBlock, uint endBlock);
	event FounderAdded(address indexed founder);
	
	constructor() {_governance = msg.sender;_linkLimit=1e17;}

	modifier onlyOracle() {require(_oracles[msg.sender] == true, "not an oracle");_;}
	modifier onlyGovernance() {require(msg.sender == _governance, "not a governance address");_;}
	modifier onlyFounder() {require(_founders[msg.sender] > 0, "Not a Founder");_;}

	function recordEntry(bytes32 _hash, string memory _entry) public { // method id
		require(_blockNumbers[msg.sender] + 25 >= block.number, "too early"); // mandatory for testnet
		if (_approvalRequired == false) {_blockNumbers[msg.sender] = block.number; emit Entry(msg.sender, _hash, _entry);}
		else if (_workers[msg.sender] == true) {_blockNumbers[msg.sender] = block.number; emit Entry(msg.sender, _hash, _entry);}
	}

	function recordEntryByOracle(address[] memory workers, bytes32[] memory hashes, string[] memory entries) public onlyOracle {
		for (uint i = 0; i < workers.length; i++) {
			require(_blockNumbers[workers[i]] + 25 >= block.number, "too early"); // mandatory for testnet
			if (_approvalRequired == false) {_blockNumbers[workers[i]] = block.number; emit Entry(workers[i], hashes[i], entries[i]);}
			else if (_workers[workers[i]] == true) {_blockNumbers[workers[i]] = block.number; emit Entry(workers[i], hashes[i], entries[i]);}
		}
	}

	function newPeriod(uint endB) public onlyGovernance {
		require(block.number >= _periods[_periodCounter].endBlock);
		uint startB = _periods[_periodCounter].endBlock+1;
		_periodCounter++;
		_periods[_periodCounter].startBlock = startB;
		_periods[_periodCounter].endBlock = endB;
		emit NewPeriod(_periodCounter,startB,endB);
	}

	function toggleFounder(address[] memory accounts, uint[] memory ethContributions) public onlyOracle {
		for (uint i = 0; i < accounts.length; i++) {
			if(_founders[accounts[i]] != ethContributions[i]) {_founders[accounts[i]] = ethContributions[i]; emit FounderAdded(accounts[i]);}
			else {
				if (_linkedAddresses[accounts[i]] != address(0)) {
					address linkedAddress = _linkedAddresses[accounts[i]];
					delete _linkedAddresses[linkedAddress];
					delete _linkedAddresses[accounts[i]];
					delete _takenAddresses[linkedAddress];
				}
				delete _founders[accounts[i]];
			}
		}
	}

	function toggleWorker(address[] memory accounts) public onlyOracle {
		for (uint i = 0; i < accounts.length; i++) {if (_workers[accounts[i]] == false) {_workers[accounts[i]] = true; emit WorkerAdded(accounts[i]);} else {delete _workers[accounts[i]];}}
	}

	function toggleOracle(address[] memory accounts) public onlyGovernance {
		for (uint i = 0; i < accounts.length; i++) {if (_oracles[accounts[i]] == false) {_oracles[accounts[i]] = true;} else {delete _oracles[accounts[i]];}}
	}

	function linkAddressByOracle(address[] memory founders, address[] memory workers) external onlyOracle {
		for (uint i = 0; i < founders.length; i++) {_linkAddress(founders[i], workers[i]);}
	}

	function setGovernance(address account) public onlyGovernance {_governance = account;}
	function toggleApprovalRequired() public onlyGovernance {if (_approvalRequired == false) {_approvalRequired = true;} else {delete _approvalRequired;}}
	function linkAddress(address worker) external onlyFounder {_linkAddress(msg.sender, worker);}
	function _isFounder(address account) internal view returns(bool) {if (_founders[account] > 0) {return true;} else {return false;}}
	function setLinkLimit(uint value) external onlyGovernance {require(value >= 0 && value < 1e18, "can't override hard limit");_linkLimit = value;}

	function _linkAddress(address founder, address worker) internal {
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

	function getAddress(address account) public view returns(bool worker, uint founderContrib, address linked, bool taken, bool oracle, uint lastEntryBlock) {
		return (_workers[account],_founders[account],_linkedAddresses[account],_takenAddresses[account],_oracles[account],_blockNumbers[account]);
	}

	function getSettings() public view returns(bool appr, address gov, uint period, uint startB, uint endB) {
		return (_approvalRequired,_governance,_periodCounter,_periods[_periodCounter].startBlock,_periods[_periodCounter].endBlock);
	}
}
