// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import "./Context.sol";
import "./IERC20.sol";
// A modification of OpenZeppelin ERC20 by Sam Porter
// Original can be found here: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol

// Very slow erc20 implementation. Limits release of the funds with emission rate in _beforeTokenTransfer().
// Even if there will be a vulnerability in upgradeable contracts defined in _beforeTokenTransfer(), it won't be devastating.
// Developers can't simply rug.
// Allowances are possible only for approved by the governance contracts.
// _mint() and _burn() functions are removed.
// Token name and symbol can be changed.

contract VSRERC20 is Context, IERC20 {
    event BulkTransferFrom(address indexed from, address[] indexed recipients, uint[] value);

	mapping (address => uint) private _balances;
	mapping (address => mapping (address => uint)) private _allowances;
	mapping (address => bool) private _allowedContracts;

	string private _name;
	string private _symbol;
	uint private _withdrawn;
	uint private _governanceSet;
	bool private _lock;
	address private _governance;

//// variables for testing purposes. live it should all be hardcoded addresses
	address private _treasury;
	uint private _genesisBlock;

	constructor (string memory name_, string memory symbol_) {
		_name = name_;
		_symbol = symbol_;
		_genesisBlock = block.number + 345600; // remove
		_governance = msg.sender; // for now
		_balances[msg.sender] = 1e30;
	}

	modifier onlyGovernance() {require(msg.sender == _governance, "only governance");_;}

	function stats() public view returns(uint emis, uint withdrawn, uint govSet) {return(42e19,_withdrawn,_governanceSet);}
	function name() public view returns (string memory) {return _name;}
	function symbol() public view returns (string memory) {return _symbol;}
	function totalSupply() public view override returns (uint) {uint supply = (block.number - _genesisBlock)*42e19;if (supply > 1e30) {supply = 1e30;}return supply;}
	function decimals() public pure returns (uint) {return 18;}
	function allowance(address owner, address spender) public view override returns (uint) {return _allowances[owner][spender];}
	function balanceOf(address account) public view override returns (uint) {return _balances[account];}

	function transfer(address recipient, uint amount) public override returns (bool) {_transfer(_msgSender(), recipient, amount);return true;}
	function approve(address spender, uint amount) public override returns (bool) {_approve(_msgSender(), spender, amount);return true;}

	function transferFrom(address sender, address recipient, uint amount) public override returns (bool) {
		_transfer(sender, recipient, amount);
		uint currentAllowance = _allowances[sender][_msgSender()];
		require(currentAllowance >= amount, "exceeds allowance");
		_approve(sender, _msgSender(), currentAllowance - amount);
		return true;
	}

	function increaseAllowance(address spender, uint addedValue) public returns (bool) {_approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);return true;}

	function decreaseAllowance(address spender, uint subtractedValue) public returns (bool) {
		uint currentAllowance = _allowances[_msgSender()][spender];
		require(currentAllowance >= subtractedValue, "below zero");
		_approve(_msgSender(), spender, currentAllowance - subtractedValue);
		return true;
	}

	function _transfer(address sender, address recipient, uint amount) internal {
		require(sender != address(0) && recipient != address(0), "zero address");
		_beforeTokenTransfer(sender, amount);
		uint senderBalance = _balances[sender];
		require(senderBalance >= amount, "exceeds balance");
		_balances[sender] = senderBalance - amount;
		_balances[recipient] += amount;
		emit Transfer(sender, recipient, amount);
	}

	function bulkTransfer(address[] memory recipients, uint[] memory amounts) public { // will be used by the contract, or anybody who wants to use it
		require(recipients.length == amounts.length && amounts.length < 500,"array length does not match or too long");
		require(sender != address(0), "zero address");
		uint senderBalance = _balances[msg.sender];
		uint total;
		for(uint i = 0;i<amounts.length;i++) {if (recipients[i] != address(0) && amounts[i] > 0) {total += amounts[i];}else{revert();}}
		require(senderBalance >= total, "don't");
		if (msg.sender == _treasury) {_beforeTokenTransfer(msg.sender, total);}
		_balances[msg.sender] = senderBalance - total;
		for(uint i = 0;i<amounts.length;i++) {_balances[recipients[i]] += amounts[i];}
		emit BulkTransfer(msg.sender, recipients, amounts);
	}

	function _approve(address owner, address spender, uint amount) internal {
		require(owner != address(0) && spender != address(0), "zero address");
		require(_allowedContracts[spender] == true, "forbidden spender"); // hardcoded uniswap contract also
		_allowances[owner][spender] = amount;
		emit Approval(owner, spender, amount);
	}

	function _beforeTokenTransfer(address from, uint amount) internal { // hardcoded address
		if (from == _treasury) { // so the treasury will contain all the funds, it will be one contract instead of several
			require(block.number > _genesisBlock, "safe math");
			require(_lock == false, "reentrancy guard");
			_lock = true;
			require(amount <= balanceOf(_treasury),"too much");
			uint allowed = (block.number - _genesisBlock)*42e19 - _withdrawn;
			require(amount <= allowed, "not yet");
			_withdrawn += amount;
			_lock = false;
		}
	}

	function setNameSymbol(string memory name_, string memory symbol_) public onlyGovernance {_name = name_;_symbol = symbol_;}
	function setGovernance(address address_) public onlyGovernance {require(_governanceSet < 3, "already set");_governanceSet += 1;_governance = address_;}
	function allowanceToContract(address contract_) public onlyGovernance {_allowedContracts[contract_] = true;}// not to forget to add uniswap contract. an address with no bytecode can be added, but it's ok
}
