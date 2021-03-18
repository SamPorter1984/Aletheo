pragma solidity >=0.7.0 <0.9.0;

// EIP-1984: https://ethereum-magicians.org/t/eip-1984-trust-minimized-proxy/5742/2 this is big for DeFi, but certainly not as big for eips in general,
// either way I hope it becomes a standard which will allow to easily distinguish genuine anonymous devs from scammers.

// OpenZeppelin Upgradeability contracts modified by Sam Porter. Proxy for Nameless Protocol contracts
// You can find original set of contracts here: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/proxy

// Had to pack OpenZeppelin upgradeability contracts in one single contract for readability. It's basically the same OpenZeppelin functions 
// but in one contract with some differences:
// 1. DEADLINE is a block after which it becomes impossible to upgrade the contract. Defined in constructor and here it's ~2 years.
// Maybe not even required for most contracts, but I kept it in case if something happens to developers.
// 2. PROPOSE_BLOCK defines how often the contract can be upgraded. Defined in _setNextLogic() function and the interval here is set
// to 172800 blocks ~1 month.
// 3. Admin rights are burnable. Rather not do that without deadline
// 4. prolongLock() allows to add to UPGRADE_BLOCK. Basically allows to prolong lock. Could prolong to maximum solidity number so the deadline might not be needed 
// 5. logic contract is not being set suddenly. it's being stored in NEXT_LOGIC_SLOT for a month and only after that it can be set as LOGIC_SLOT.
// Users have time to decide on if the deployer or the governance is malicious and exit safely.

// It fixes "upgradeability bug" I believe. Also I sincerely believe that upgradeability is not about fixing bugs, but about upgradeability,
// so yeah, proposed logic has to clean.

contract TrustMinimizedProxy {
	event Upgraded(address indexed toLogic);
	event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
	event NextLogicDefined(address indexed nextLogic);
	event ProposalsRestrictedUntil(uint block);
	event Canceled(address indexed toLogic);

	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
	bytes32 internal constant LOGIC_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
	bytes32 internal constant NEXT_LOGIC_SLOT = 0xb182d207b11df9fb38eec1e3fe4966cf344774ba58fb0e9d88ea35ad46f3601e;
	bytes32 internal constant NEXT_LOGIC_BLOCK_SLOT = 0x96de003e85302815fe026bddb9630a50a1d4dc51c5c355def172204c3fd1c733;
	bytes32 internal constant PROPOSE_BLOCK_SLOT = 0xbc9d35b69e82e85049be70f91154051f5e20e574471195334bde02d1a9974c90;
	bytes32 internal constant DEADLINE_SLOT = 0xb124b82d2ac46ebdb08de751ebc55102cc7325d133e09c1f1c25014e20b979ad;

	constructor(address logic, bytes memory data) payable {
		require(ADMIN_SLOT == bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1) && LOGIC_SLOT == bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1) && // this require is simply against human error, can be removed if you know what you are doing
		NEXT_LOGIC_SLOT == bytes32(uint256(keccak256('eip1984.proxy.nextLogic')) - 1) && NEXT_LOGIC_BLOCK_SLOT == bytes32(uint256(keccak256('eip1984.proxy.nextLogicBlock')) - 1) &&
		PROPOSE_BLOCK_SLOT == bytes32(uint256(keccak256('eip1984.proxy.proposeBlock')) - 1) && DEADLINE_SLOT == bytes32(uint256(keccak256('eip1984.proxy.deadline')) - 1), "code broke");
		_setAdmin(msg.sender);
		if(data.length > 0) {
			(bool success,) = logic.delegatecall(data);
			require(success==true);
		}
		uint deadline = block.number + 4204800; // ~2 years as default
		assembly {sstore(DEADLINE_SLOT,deadline) sstore(LOGIC_SLOT,logic)}
	}
	modifier ifAdmin() {if (msg.sender == _admin()) {_;} else {_fallback();}}

	function getSettings() external ifAdmin returns(address logic, uint pgrdBlck, uint ddln) {return (_logic(), _proposeBlock(), _deadline());}
	function _logic() internal view returns (address logic) {assembly { logic := sload(LOGIC_SLOT) }}
	function _proposeBlock() internal view returns (uint bl) {assembly { bl := sload(PROPOSE_BLOCK_SLOT) }}
	function _nextLogicBlock() internal view returns (uint bl) {assembly { bl := sload(NEXT_LOGIC_BLOCK_SLOT) }}
	function _deadline() internal view returns (uint bl) {assembly { bl := sload(DEADLINE_SLOT) }}
	function changeAdmin(address newAdm) external ifAdmin {emit AdminChanged(_admin(), newAdm);_setAdmin(newAdm);}
	function proposeTo(address newLogic) external ifAdmin {_setNextLogic(newLogic);}
	function proposeToAndCall(address newLogic, bytes calldata data) payable external ifAdmin {_setNextLogic(newLogic);(bool success,) = newLogic.delegatecall(data);require(success);}
	function prolongLock(uint block_) external ifAdmin {uint pb; assembly {pb := sload(PROPOSE_BLOCK_SLOT) pb := add(pb,block_) sstore(PROPOSE_BLOCK_SLOT,pb)}emit ProposalsRestrictedUntil(pb);}

	function _setNextLogic(address nextLogic) internal {
		require(block.number >= _proposeBlock() && block.number < _deadline(), "wait or too late");
		require(_isContract(nextLogic), "Can't set to 0 bytecode");
		uint proposeBlock = block.number + 172800;
		uint nextLogicBlock = block.number + 172800;
		assembly { sstore(NEXT_LOGIC_SLOT, nextLogic) sstore(NEXT_LOGIC_BLOCK_SLOT, nextLogicBlock) sstore(PROPOSE_BLOCK_SLOT, proposeBlock) }
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
