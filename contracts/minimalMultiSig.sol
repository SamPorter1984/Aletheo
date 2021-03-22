pragma solidity >=0.7.0  <=0.9.0;

/// @title Multisignature wallet - Allows multiple parties to agree on Trxns before execution.
/// @author Stefan George - <stefan.george@consensys.net>
// modified by Sam Porter. Had to pack it up to more readable format, removed a few functions and variables.
contract MinimalMultiSig {
	event Submitted(uint indexed trxnId);
	event Executed(uint indexed trxnId);
	event ExecutionFailure(uint indexed trxnId);
	event Deposit(address indexed sender, uint value);

	struct Trxn {address dest;uint value;bytes data;bool executed;uint confirms;}
	mapping (uint => Trxn) public trxns;
	mapping (uint => mapping (address => bool)) private _confirmations;
	mapping (address => bool) public owners;
	uint private _ownersCount;
	uint public trxnCount;

	modifier onlyWallet(){require(msg.sender == address(this));_;}
	modifier onlyOwner(){require(owners[msg.sender] == true);_;}

	constructor (address[] memory owners_) {owners[msg.sender]=true;uint count = 1;for(uint i=0;i<owners_.length;i++){owners[owners_[i]] = true; count++;}_ownersCount = count;}

	receive() external payable {if (msg.value > 0) emit Deposit(msg.sender, msg.value);}
	function addOwner(address owner) public	onlyWallet {owners[owner] = true;_ownersCount += 1;}
	function removeOwner(address owner) public onlyWallet {owners[owner] = false;_ownersCount-=1;}
	function confirmTrxn(uint trxnId) public onlyOwner{require(!_confirmations[trxnId][msg.sender]);_confirmations[trxnId][msg.sender] = true;trxns[trxnId].confirms += 1;executeTrxn(trxnId);}

	function submitTrxn(address dest, uint value, bytes memory data) public returns (uint trxnId) {
		trxnId = trxnCount;
		trxns[trxnId].dest = dest;
		trxns[trxnId].value = value;
		trxns[trxnId].data = data;
		trxnCount += 1;emit Submitted(trxnId);confirmTrxn(trxnId);
	}

	function executeTrxn(uint trxnId) public onlyOwner {
		require(!trxns[trxnId].executed);
		if (trxns[trxnId].confirms == _ownersCount/2+1) {
			Trxn storage txn = trxns[trxnId];
			txn.executed = true;
			if (_external_call(txn.dest, txn.value, txn.data.length, txn.data)){emit Executed(trxnId);}
			else {emit ExecutionFailure(trxnId);txn.executed = false;}
		}
	}

	function _external_call(address dest, uint value, uint dataLength, bytes memory data) internal returns (bool) {
		bool result;
		assembly {let x := mload(0x40) let d := add(data, 32) result := call(sub(gas(), 34710),dest,value,d,dataLength,x,0)}
		return result;
	}
}
