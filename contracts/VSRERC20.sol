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
	mapping (address => uint256) private _balances;
	mapping (address => mapping (address => uint256)) private _allowances;
	mapping (address => bool) private _allowanceContracts;

	uint256 private _totalSupply = 1e30;
	string private _name;
	string private _symbol;
	uint private _emission;
	uint private _marketingEmission;
	uint private _withdrawnMfund;
	uint private _withdrawnFfund;
	uint private _withdrawnTfund;
	uint private _withdrawnMRfund;
	uint private _withdrawnCfund;
	uint private _withdrawnLpOfund;
	uint private _withdrawnDfund;
	uint private _governanceSet;
	bool private _withdrawingFromFunds;
	address private _governance;

//// variables for testing purposes. live it should all be hardcoded addresses
	address private _mFund;
	address private _tFund;
	address private _mrFund;
	address private _charFund;
	address private _lpOfund;
	address private _fFund;
	address private _devFund;
	uint private _genesisBlock;

	constructor (string memory name_, string memory symbol_) {
		_name = name_;
		_symbol = symbol_;
		_genesisBlock = block.number + 320000; // remove
		_governance = msg.sender; // for now
		_emission = 42; // approx 1 bil from a fund in 10 years
		_marketingEmission = 420;
		_balances[msg.sender] = 1e30;
	}

	modifier onlyGovernance() {require(msg.sender == _governance, "only governance");_;}

	function stats() public view returns(uint emi, uint mEmi, uint wMf, uint wFf, uint wTf, uint wMRf, uint wCf, uint wLpOf, uint wDf, uint govSet) {
		return (_emission,_marketingEmission,_withdrawnMfund,_withdrawnFfund,_withdrawnTfund,_withdrawnMRfund,_withdrawnCfund,_withdrawnLpOfund,_withdrawnDfund,_governanceSet);
	}

	function name() public view returns (string memory) {return _name;}
	function symbol() public view returns (string memory) {return _symbol;}
	function totalSupply() public view override returns (uint) {return _totalSupply;}
	function decimals() public pure returns (uint) {return 18;}
	function allowance(address owner, address spender) public view override returns (uint) {return _allowances[owner][spender];}
	function balanceOf(address account) public view override returns (uint) {return _balances[account];}

	function transfer(address recipient, uint amount) public override returns (bool) {_transfer(_msgSender(), recipient, amount);return true;}
	function approve(address spender, uint amount) public override returns (bool) {_approve(_msgSender(), spender, amount);return true;}

	function transferFrom(address sender, address recipient, uint amount) public override returns (bool) {
		_transfer(sender, recipient, amount);
		uint256 currentAllowance = _allowances[sender][_msgSender()];
		require(currentAllowance >= amount, "exceeds allowance");
		_approve(sender, _msgSender(), currentAllowance - amount);
		return true;
	}

	function increaseAllowance(address spender, uint addedValue) public returns (bool) {_approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);return true;}

	function decreaseAllowance(address spender, uint subtractedValue) public returns (bool) {
		uint256 currentAllowance = _allowances[_msgSender()][spender];
		require(currentAllowance >= subtractedValue, "below zero");
		_approve(_msgSender(), spender, currentAllowance - subtractedValue);
		return true;
	}

	function _transfer(address sender, address recipient, uint amount) internal {
		require(sender != address(0) && recipient != address(0), "zero address");
		_beforeTokenTransfer(sender, amount);
		uint256 senderBalance = _balances[sender];
		require(senderBalance >= amount, "exceeds balance");
		_balances[sender] = senderBalance - amount;
		_balances[recipient] += amount;
		emit Transfer(sender, recipient, amount);
	}

	function _approve(address owner, address spender, uint amount) internal {
		require(owner != address(0), "zero address");
		require(_allowanceContracts[spender] == true, "forbidden spender");
		_allowances[owner][spender] = amount;
		emit Approval(owner, spender, amount);
	}

	function _beforeTokenTransfer(address from, uint amount) internal { // if all addresses are hardcoded almost no cost is added
		if (from == _devFund || from == _fFund || from == _tFund || from == _mrFund || from == _charFund || from == _lpOfund|| from == _mFund) {
			require(block.number > _genesisBlock, "too early");
			require(_withdrawingFromFunds == false, "reentrancy guard");
			_withdrawingFromFunds = true;
			if (from == _mFund) {
				require(amount <= balanceOf(_mFund),"too much");
				uint allowed = (block.number - _genesisBlock)*_marketingEmission - _withdrawnMfund;
				require(amount <= allowed, "not yet");
				_withdrawnMfund += amount;
			} else if (from == _devFund) {
				require(amount <= balanceOf(_devFund),"too much");
				uint allowed = (block.number - _genesisBlock)*_emission - _withdrawnDfund;
				require(amount <= allowed, "not yet");
				_withdrawnDfund += amount;
			} else if (from == _fFund) {
				require(amount <= balanceOf(_fFund),"too much");
				uint allowed = (block.number - _genesisBlock)*_emission - _withdrawnFfund;
				require(amount <= allowed, "not yet");
				_withdrawnFfund += amount;
			} else if (from == _tFund) {
				require(amount <= balanceOf(_tFund),"too much");
				uint allowed = (block.number - _genesisBlock)*_emission - _withdrawnTfund;
				require(amount <= allowed, "not yet");
				_withdrawnTfund += amount;
			} else if (from == _mrFund) {
				require(block.number > _genesisBlock + 10512000, "too early");
				require(amount <= balanceOf(_mrFund),"too much");
				uint allowed = (block.number - _genesisBlock + 10512000)*_emission - _withdrawnMRfund;
				require(amount <= allowed, "not yet");
				_withdrawnMRfund += amount;
			} else if (from == _charFund) {
				require(block.number > _genesisBlock + 10512000, "too early");
				require(amount <= balanceOf(_charFund),"too much");
				uint allowed = (block.number - _genesisBlock + 10512000)*_emission - _withdrawnCfund;
				require(amount <= allowed, "not yet");
				_withdrawnCfund += amount;
			} else if (from == _lpOfund) {
				require(amount <= balanceOf(_lpOfund),"too much");
				uint allowed = (block.number - _genesisBlock)*_emission - _withdrawnLpOfund;
				require(amount <= allowed, "not yet");
				_withdrawnLpOfund += amount;
			}
			_withdrawingFromFunds = false;
		}
	}

	function setNameSymbol(string memory name_, string memory symbol_) public onlyGovernance {_name = name_;_symbol = symbol_;}
	function setGovernance(address address_) public onlyGovernance {require(_governanceSet < 4, "already set");_governanceSet += 1;_governance = address_;}
	function setEmission(uint emission) public onlyGovernance {require(emission <= 50 && emission >= 20, "hard limit");_emission = emission;}

	function setMarketingEmission(uint marketingEmission) public onlyGovernance {
		require(marketingEmission <= 500 && marketingEmission >= 200, "hard limit");
		_marketingEmission = marketingEmission;
	}

	function toggleAllowanceContract(address contract_) public onlyGovernance { // not to forget to add uniswap contract
		require(contract_ != address(0), "forbidden address"); // an address with no bytecode can be added, but it's ok
		if (_allowanceContracts[contract_] == true) {_allowanceContracts[contract_] = false;}
		else {_allowanceContracts[contract_] = true;}
	}
}
