pragma solidity >=0.7.0 <0.9.0;

// OpenZeppelin Upgradeability contracts modified by Sam Porter. Proxy for Nameless Protocol contracts
// You can find original set of contracts here: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/proxy

// Had to pack OpenZeppelin upgradeability contracts in one single contract for readability. It's basically the same OpenZeppelin functions 
// but in one contract with some differences:
// 1. DEADLINE is a block after which it becomes impossible to upgrade the contract. Defined in constructor and here it's ~2 years.
// Maybe not even required for most contracts, but I kept it as an option.
// 2. UPGRADE_BLOCK defines how often the contract can be upgraded. Defined in _setNextLogic() function and the interval here is set
// to 172800 blocks ~1 month.
// 3. Admin rights are burnable. Rather not do that without deadline
// 4. prolongLock() allows to add to UPGRADE_BLOCK. Basically allows to prolong lock. Could prolong to maximum solidity number so the deadline might not be needed 
// 5. logic contract is not being set suddenly. it's being stored in NEXT_LOGIC_SLOT for a month and only after that it can be set as LOGIC_SLOT.
// Users have time to decide on if the deployer or the governance is malicious and exit safely.

// It fixes upgradeability bug I believe. Consensys won't be so smug about it anymore.

contract NamelessProxy {
	event Upgraded(address indexed toLogic);
	event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
	event NextLogicDefined(address indexed nextLogic);
	event UpgradePostponed(uint toBlock);
	event Canceled(address indexed toLogic);

	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
	bytes32 internal constant LOGIC_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
	bytes32 internal constant NEXT_LOGIC_SLOT = 0x56c185b2cb0723d5ac9bee49054a51e03ffce668e6ca209d91e6a1878e3ca4aa;
	bytes32 internal constant NEXT_LOGIC_BLOCK_SLOT = 0x717ada2fcd4aad6ac93cdada14e28f6d4a8483da76e136464708d860266d8f95;
	bytes32 internal constant UPGRADE_BLOCK_SLOT = 0x85e20208757fc820a8c68416a36f94ca955b4e86fafc028f8f82fb4c1f53c4ec;
	bytes32 internal constant DEADLINE_SLOT = 0x82249145f5968d8bd05e6767411f4176a5fa34858f6fb467470c471c9a8f1d57;

	constructor(address logic) {
		require(ADMIN_SLOT == bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1) && LOGIC_SLOT == bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1) && // this require is simply against human error, can be removed if you know what you are doing
		NEXT_LOGIC_SLOT == bytes32(uint256(keccak256('nameless.proxy.nextLogic')) - 1) && NEXT_LOGIC_BLOCK_SLOT == bytes32(uint256(keccak256('nameless.proxy.nextLogicBlock')) - 1) &&
		UPGRADE_BLOCK_SLOT == bytes32(uint256(keccak256('nameless.proxy.upgradeBlock')) - 1) && DEADLINE_SLOT == bytes32(uint256(keccak256('nameless.proxy.deadline')) - 1), "code broke");
		_setAdmin(msg.sender);
		uint deadline = block.number + 4204800; // ~2 years as default
		assembly {sstore(DEADLINE_SLOT,deadline) sstore(LOGIC_SLOT,logic)}
	}
	modifier ifAdmin() {if (msg.sender == _admin()) {_;} else {_fallback();}}

	function getSettings() external ifAdmin returns(address logic, uint pgrdBlck, uint ddln) {return (_logic(), _upgradeBlock(), _deadline());}
	function _logic() internal view returns (address logic) {assembly { logic := sload(LOGIC_SLOT) }}
	function _upgradeBlock() internal view returns (uint bl) {assembly { bl := sload(UPGRADE_BLOCK_SLOT) }}
	function _nextLogicBlock() internal view returns (uint bl) {assembly { bl := sload(NEXT_LOGIC_BLOCK_SLOT) }}
	function _deadline() internal view returns (uint bl) {assembly { bl := sload(DEADLINE_SLOT) }}
	function changeAdmin(address newAdm) external ifAdmin {emit AdminChanged(_admin(), newAdm);_setAdmin(newAdm);}
	function proposeTo(address newLogic) external ifAdmin {_setNextLogic(newLogic);}
	function proposeToAndCall(address newLogic, bytes calldata data) payable external ifAdmin {_setNextLogic(newLogic);(bool success,) = newLogic.delegatecall(data);require(success);}
	function prolongLock(uint block_) external ifAdmin {uint ub; assembly {ub := sload(UPGRADE_BLOCK_SLOT) ub := add(ub,block_) sstore(UPGRADE_BLOCK_SLOT,ub)}emit UpgradePostponed(ub);}

	function _setNextLogic(address nextLogic) internal {
		require(block.number >= _upgradeBlock() && block.number < _deadline(), "wait or too late");
		require(_isContract(nextLogic), "Can't set to 0 bytecode");
		uint upgradeBlock = block.number + 172800;
		uint nextLogicBlock = block.number + 172800;
		assembly { sstore(NEXT_LOGIC_SLOT, nextLogic) sstore(NEXT_LOGIC_BLOCK_SLOT, nextLogicBlock) sstore(UPGRADE_BLOCK_SLOT, upgradeBlock) }
		emit NextLogicDefined(nextLogic);
	}

	function upgrade() external ifAdmin {require(block.number>=_nextLogicBlock(),"wait");address logic;assembly {logic := sload(NEXT_LOGIC_SLOT) sstore(LOGIC_SLOT,logic)}emit Upgraded(logic);}

	function cancelUpgrade() external ifAdmin {address logic;assembly {logic := sload(LOGIC_SLOT)sstore(NEXT_LOGIC_SLOT, logic)}emit Canceled(logic);}

	function _isContract(address account) internal view returns (bool b) {uint256 size;assembly { size := extcodesize(account) }return size > 0;}
	function _admin() internal view returns (address adm) {assembly { adm := sload(ADMIN_SLOT) }}
	function _setAdmin(address newAdm) internal {assembly {sstore(ADMIN_SLOT, newAdm)}}

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
