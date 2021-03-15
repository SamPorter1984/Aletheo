pragma solidity >=0.7.0;

// OpenZeppelin Upgradeability contracts modified by Sam Porter
// You can find original set of contracts here: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/proxy

// Had to pack OpenZeppelin upgradeability contracts in one single contract for readability. It's basically the same OpenZeppelin functions 
// but in one contract with some differences:
// 1. constructor does not require arguments.
// 2. _deadline variable is a block after which it becomes impossible to upgrade the contract. Defined in constructor and here it's ~2 years.
// 3. _upgradeBlock defines how often the contract can be upgraded. Defined in _setlogic() function and the internval here is set
// to 172800 blocks ~1 month.
// 4. Admin can be changed only three times.
// 5. prolongLock() allows to add to _upgradeBlock. Basically allows to prolong lock.

contract CustomProxy {
	event Upgraded(address indexed logic);
	event AdminChanged(address previousAdmin, address newAdmin);
	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
	bytes32 internal constant LOGIC_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
	uint private _upgradeBlock;
	uint private _deadline;
	uint private _governanceSet;
	
	constructor() {
		require(ADMIN_SLOT == bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1) && LOGIC_SLOT == bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1), "code broke");
		_setAdmin(msg.sender);
		_upgradeBlock = 0;
		_deadline = block.number + 4204800; // ~2 years as default
	}

	modifier ifAdmin() {if (msg.sender == _admin()) {_;} else {_fallback();}}

	function getSettings() external ifAdmin returns(address adm, address logic, uint pgrdBlck, uint ddln) {return (_admin(), _logic(), _upgradeBlock, _deadline);}
	function _logic() internal view returns (address logic) {assembly { logic := sload(LOGIC_SLOT) }}
	function changeAdmin(address newAdm) external ifAdmin {require(newAdm != address(0), "Can't change admin to 0");emit AdminChanged(_admin(), newAdm);_setAdmin(newAdm);}
	function upgradeTo(address newLogic) external ifAdmin {_setlogic(newLogic);}
	function upgradeToAndCall(address newLogic, bytes calldata data) payable external ifAdmin {_setlogic(newLogic);(bool success,) = newLogic.delegatecall(data);require(success);}
	function prolongLock(uint block) external ifAdmin {_upgradeBlock+=block;}

	function _setlogic(address newLogic) internal {
		require(block.number >= _upgradeBlock && block.number < _deadline, "wait or too late");
		require(_isContract(newLogic), "Can't set to 0 bytecode address");
		_upgradeBlock = block.number + 172800;
		assembly { sstore(LOGIC_SLOT, newLogic) }
		emit Upgraded(newLogic);
	}

	function _isContract(address account) internal view returns (bool b) {uint256 size;assembly { size := extcodesize(account) }return size > 0;}
	function _admin() internal view returns (address adm) {assembly { adm := sload(ADMIN_SLOT) }}
	function _setAdmin(address newAdm) internal {require(_governanceSet < 3, "governance already set");_governanceSet += 1;assembly { sstore(ADMIN_SLOT, newAdm) }}
	fallback () external payable {_fallback();}
	receive () external payable {_fallback();}
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
}
