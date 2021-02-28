pragma solidity >=0.7.0;

// OpenZeppelin Upgradeability contracts modified by Sam Porter
// You can find original set of contracts here: 

// Had to pack OpenZeppelin upgradeability contracts in one single contract for readability. It's basically the same OpenZeppelin functions but in one contract with some
// differences:
// 1.constructor does not require arguments.
// 2._deadline variable is a block after which it becomes impossible to upgrade the contract. Defined in constructor and here it's ~2 years.
// 3._upgradeBlock defines how often the contract can be upgraded. Defined in _setImplementation() function and the internval here is set to 100k blocks.

contract CustomAdminProxy {
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint private _upgradeBlock;
    uint private _deadline;

    constructor() {
        require(ADMIN_SLOT == bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1), "eth ded or code broke?");
        require(IMPLEMENTATION_SLOT == bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1), "eth ded or code broke?");
        _setAdmin(msg.sender);
        _upgradeBlock = 0;
        _deadline = block.number + 4204800; // ~2 years as default
    }

    modifier ifAdmin() {
        if (msg.sender == _admin()) {
            _;
        } else {
            _fallback();
        }
    }

    function getSettings() external ifAdmin returns(address adm, address impl, uint pgrdBlck, uint ddln) {
        return (_admin(), _implementation(), _upgradeBlock, _deadline);
    }

    function _implementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function changeAdmin(address newAdmin) external ifAdmin {
        require(newAdmin != address(0), "Cannot change the admin of a proxy to the zero address");
        emit AdminChanged(_admin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function upgradeTo(address newImplementation) external ifAdmin {
        require(block.number >= _upgradeBlock, "wait");
        require(_deadline > block.number, "too late, the protocol is set in stone");
        _upgradeTo(newImplementation);
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) payable external ifAdmin {
        _upgradeTo(newImplementation);
        (bool success,) = newImplementation.delegatecall(data);
        require(success);
    }

    function _setImplementation(address newImplementation) internal {
        require(_isContract(newImplementation), "Cannot set a proxy implementation to a non-contract address");
        _upgradeBlock = block.number + 100000;
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    function _isContract(address account) internal view returns (bool b) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function _admin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
        adm := sload(slot)
        }
    }

    function _setAdmin(address newAdmin) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
        sstore(slot, newAdmin)
        }
    }

    fallback () external payable {
        _fallback();
    }

    receive () external payable {
        _fallback();
    }

    function _fallback() internal {
        require(msg.sender != _admin(), "Cannot call fallback function from the proxy admin");
        _delegate(_implementation());
    }

    function _delegate(address implementation_) internal {
        assembly {
        calldatacopy(0, 0, calldatasize())
        let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
        }
    }
}
