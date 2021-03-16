pragma solidity >=0.7.0;

// OpenZeppelin Upgradeability contracts modified by Sam Porter
// You can find original set of contracts here: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/proxy

// Had to pack OpenZeppelin upgradeability contracts in one single contract for readability. It's basically the same OpenZeppelin functions 
// but in one contract with some differences:
// 1. constructor does not require arguments.
// 2. _deadline variable is a block after which it becomes impossible to upgrade the contract. Defined in constructor and here it's ~2 years.
// Maybe not even required, but I kept it as an option.
// 3. _upgradeBlock defines how often the contract can be upgraded. Defined in _setlogic() function and the internval here is set
// to 172800 blocks ~1 month.
// 4. Admin can be changed only three times.
// 5. prolongLock() allows to add to _upgradeBlock. Basically allows to prolong lock. Could prolong for trillions of blocks so the deadline might not be needed 
// 6. logic contract is not being set suddenly. it's being stored in NEXT_LOGIC_SLOT for a month and only after that it can be set as LOGIC_SLOT.
// Users have time to decide on if the deployer or the governance is malicious and exit safely.

// It fixes upgradeability bug I believe. Consensys won't be so smug about it anymore. They will still point out to something like what
// if these 3 addresses already being used? We can just restrict using these addresses in logic contract, so there are only weak arguments left i guess. 

contract NamelessProxy {
	event Upgraded(address indexed logic);
	event AdminChanged(address previousAdmin, address newAdmin);
	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
	bytes32 internal constant LOGIC_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
	bytes32 internal constant NEXT_LOGIC_SLOT = 0x56c185b2cb0723d5ac9bee49054a51e03ffce668e6ca209d91e6a1878e3ca4aa;
	uint private _upgradeBlock;
	uint private _deadline;
	uint private _governanceSet;
	
	constructor() {
		require(ADMIN_SLOT == bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1) && LOGIC_SLOT == bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1), "code broke");
		require(NEXT_LOGIC_SLOT == bytes32(uint256(keccak256('nameless.proxy.nextLogic')) - 1), "code broke");
		_setAdmin(msg.sender);
		_upgradeBlock = 0;
		_deadline = block.number + 4204800; // ~2 years as default
	}

	modifier ifAdmin() {if (msg.sender == _admin()) {_;} else {_fallback();}}

	function getSettings() external ifAdmin returns(address adm, address logic, uint pgrdBlck, uint ddln) {return (_admin(), _logic(), _upgradeBlock, _deadline);}
	function _logic() internal view returns (address logic) {assembly { logic := sload(LOGIC_SLOT) }}
	function changeAdmin(address newAdm) external ifAdmin {require(newAdm != address(0), "Can't change admin to 0");emit AdminChanged(_admin(), newAdm);_setAdmin(newAdm);}
	function proposeTo(address newLogic) external ifAdmin {_setNextLogic(newLogic);}
	function proposeToAndCall(address newLogic, bytes calldata data) payable external ifAdmin {_setNextLogic(newLogic);(bool success,) = newLogic.delegatecall(data);require(success);}
	function prolongLock(uint block) external ifAdmin {_upgradeBlock+=block;}

	function _setNextLogic(address nextLogic) internal {
		require(block.number >= _upgradeBlock && block.number < _deadline, "wait or too late");
		require(_isContract(nextLogic), "Can't set to 0 bytecode address");
		_upgradeBlock = block.number + 172800;
		_nextLogicBlock = block.number + 172800;
		assembly { sstore(NEXT_LOGIC_SLOT, nextLogic) }
		emit NextLogicDefined(nextLogic);
	}

	function upgrade() external ifAdmin {
		require(block.number >= _nextLogicBlock, "wait");
		address logic;
		assembly { logic := sload(NEXT_LOGIC_SLOT) }
		assembly { sstore(LOGIC_SLOT, logic) }
		emit Upgraded(logic);
	}

	function cancelUpgrade() external ifAdmin {
		address logic;
		assembly { logic := sload(LOGIC_SLOT) }
		assembly { sstore(NEXT_LOGIC_SLOT, logic) }
	}

	function _isContract(address account) internal view returns (bool b) {uint256 size;assembly { size := extcodesize(account) }return size > 0;}
	function _admin() internal view returns (address adm) {assembly { adm := sload(ADMIN_SLOT) }}
	function _setAdmin(address newAdm) internal {require(_governanceSet < 3, "governance already set");_governanceSet += 1;assembly { sstore(ADMIN_SLOT, newAdm) }}
	fallback () external payable {_safety();_fallback();}
	receive () external payable {_safety();_fallback();}
	function _fallback() internal {require(msg.sender != _admin(), "Can't call fallback from admin");_delegate(_logic());}

	function _delegate(address logic_) internal {
		assembly {
		calldatacopy(0, 0, calldatasize())
		let result := delegatecall(gas(), logic_, 0, calldatasize(), 0, 0)
		returndatacopy(0, 0, returndatasize())
		switch result
		case 0 { revert(0, returndatasize()) }
		default { return(0, returndatasize()) }
		}
	}
	function _safety() internal { // could require context
		require(msg.sender != 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 && msg.sender != 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc && msg.sender != 0x56c185b2cb0723d5ac9bee49054a51e03ffce668e6ca209d91e6a1878e3ca4aa, "can't");
	}
}
