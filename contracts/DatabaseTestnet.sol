pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;
// not critically important for this contract to be clean on testnet, and it's disposable by design anyway. but hopefully it's good already,
// so that it could create a good look i guess
// could make sense to make it upgradeable, so it won't be required to update contract address everywhere. this one is for only centralized oracle.
contract DatabaseTestnet {
	event Entry(address indexed a, bytes32 indexed hash, string entry);
	address private _governance;
	mapping (address => bool) private _oracles;
	mapping (address => bool) private _posters;
	mapping (address => uint) private _payouts;
	//testnet mappings
	mapping (address => uint) private _blockNumbers;

	constructor() {_governance = msg.sender;}

	modifier onlyOracle() {require(_oracles[msg.sender] == true);_;}
	modifier onlyGovernance() {require(msg.sender == _governance);_;}

	function recordEntry(bytes32 _hash, string memory _entry) public { // not to forget method id
		require(_blockNumbers[msg.sender] + 23 >= block.number);
		if (_approvalRequired == false) {_blockNumbers[msg.sender] = block.number; emit Entry(msg.sender, _hash, _entry);}
		else if (_posters[msg.sender] == true) {_blockNumbers[msg.sender] = block.number; emit Entry(msg.sender, _hash, _entry);}
	}

	function toggleOracle(address[] memory accounts) public onlyGovernance {
		for (uint i = 0; i < accounts.length; i++) {if (_oracles[accounts[i]] == false) {_oracles[accounts[i]] = true;} else {delete _oracles[accounts[i]];}}
	}

	//view functions
	function getAddress(address account) public view returns(bool poster, uint payout, uint founderContrib, address linked, bool taken, bool oracle, uint lastEntryBlock) {
		return (_posters[account],_payouts[account],_founders[account],_linkedAddresses[account],_takenAddresses[account],_oracles[account],_blockNumbers[account]);
	}

	function getSettings() public view returns(/*bool appr, */address gov/*, uint period, uint startB, uint endB*/) {
		return (/*_approvalRequired,*/_governance/*,_periodCounter,_periods[_periodCounter].startBlock,_periods[_periodCounter].endBlock*/);
	}
	function setGovernance(address account) public onlyGovernance {_governance = account;}

	function recordPayoutByOracle(address[] memory posters, uint[] memory payouts) public onlyOracle {for (uint i = 0; i < posters.length; i++) {_payouts[posters[i]] += payouts[i];}}
/*
	bool private _approvalRequired;
	uint private _periodCounter;
	struct Period {uint128 startBlock; uint128 endBlock;}

	mapping (uint => Period) private _periods;
	mapping (address => bool) private _takenAddresses;
	mapping (address => address) private _linkedAddresses;
	mapping (address => uint) private _founders;// ethContributed

	event posterAdded(address indexed account);
	event NewPeriod(uint id, uint startBlock, uint endBlock);
	event FounderAdded(address indexed founder);
	event AddressLinked(address indexed address1, address indexed address2);

	modifier onlyFounder() {require(_founders[msg.sender] > 0);_;}

	function recordEntryByOracle(address[] memory posters, bytes32[] memory hashes, string[] memory entries) public onlyOracle {
		for (uint i = 0; i < posters.length; i++) {
			if (_blockNumbers[posters[i]] + 23 >= block.number) {
				if (_approvalRequired == false) {_blockNumbers[posters[i]] = block.number; emit Entry(posters[i], hashes[i], entries[i]);}
				else if (_posters[posters[i]] == true) {_blockNumbers[posters[i]] = block.number; emit Entry(posters[i], hashes[i], entries[i]);}
			}
		}
	}

	function newPeriod(uint endB) public onlyGovernance { // this function is not required on testnet, it's a point of reference for decentralized oracle network
		uint counter = _periodCounter;
		uint previousEndB = _periods[counter].endBlock;
		require(block.number >= previousEndB);
		uint startB = previousEndB+1;
		if (previousEndB == 0) {
			startB = block.number;
		}
		require(endB > startB);
		_periodCounter++;
		counter++;
		_periods[counter].startBlock = uint128(startB);
		_periods[counter].endBlock = uint128(endB);
		emit NewPeriod(counter,startB,endB);
	}

	function togglePoster(address[] memory accounts) public onlyOracle {
		for (uint i = 0; i < accounts.length; i++) {if (_posters[accounts[i]] == false) {_posters[accounts[i]] = true; emit posterAdded(accounts[i]);} else {delete _posters[accounts[i]];}}
	}

	function linkAddressByOracle(address[] memory founders, address[] memory posters) external onlyOracle {
		for (uint i = 0; i < founders.length; i++) {_linkAddress(founders[i], posters[i]);}
	}

	// testnet functions
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

	function toggleApprovalRequired() public onlyGovernance {if (_approvalRequired == false) {_approvalRequired = true;} else {delete _approvalRequired;}}
	function linkAddress(address poster) external onlyFounder {_linkAddress(msg.sender, poster);}
	function _isFounder(address account) internal view returns(bool) {if (_founders[account] > 0) {return true;} else {return false;}}

	function _linkAddress(address founder, address poster) internal {
		if (_linkedAddresses[founder] != poster && _takenAddresses[poster] == false && _isFounder(poster) == false && _founders[founder] >= 1e16) {
			if (_linkedAddresses[founder] != address(0)) {
			address linkedAddress = _linkedAddresses[founder]; delete _linkedAddresses[founder]; delete _linkedAddresses[linkedAddress]; delete _takenAddresses[linkedAddress];
			}
			_linkedAddresses[founder] = poster;
			_linkedAddresses[poster] = founder;
			_takenAddresses[poster] = true;
			if (_posters[poster] != true) {_posters[poster] == true; emit posterAdded(poster);}
			emit AddressLinked(founder,poster);
		}
	}*/
}
