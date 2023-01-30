// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

// A modification of OpenZeppelin ERC20
// Original can be found here: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol

contract MockEERC20 {
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    string public name;
    string public symbol;
    uint private _totalSupply;
    bool public ini;
    address public liquidityManager;
    address public governance;
    address public treasury;
    address public foundingEvent;
    uint public sellTax;

    mapping(address => mapping(address => bool)) private _allowances;
    mapping(address => uint) private _balances;
    mapping(address => bool) public pools;

    function init(address _liquidityManager, address _treasury, address _foundingEvent, address _governance) public {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199);
        require(ini == false, 'already initialized');
        ini = true;
        name = 'Aletheo';
        symbol = 'LET';
        liquidityManager = _liquidityManager;
        treasury = _treasury;
        foundingEvent = _foundingEvent;
        governance = _governance;
        _mint(_governance, 15000e18);
        //_mint(treasury, 50000e18);
        _mint(foundingEvent, 100000e18);
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply - _balances[0x000000000000000000000000000000000000dEaD] - _balances[0x0000000000000000000000000000000000000000];
    }

    function decimals() public pure returns (uint) {
        return 18;
    }

    function balanceOf(address a) public view returns (uint) {
        return _balances[a];
    }

    function disallow(address spender) public returns (bool) {
        delete _allowances[msg.sender][spender];
        emit Approval(msg.sender, spender, 0);
        return true;
    }

    function approve(address spender, uint amount) public returns (bool) {
        if (spender == 0x10ED43C718714eb63d5aA57B78B54704E256024E) {
            // hardcoded pancake router
            emit Approval(msg.sender, spender, 2 ** 256 - 1);
            return true;
        } else {
            _allowances[msg.sender][spender] = true;
            emit Approval(msg.sender, spender, 2 ** 256 - 1);
            return true;
        }
    }

    function allowance(address owner, address spender) public view returns (uint) {
        // hardcoded pancake router
        if (spender == 0x10ED43C718714eb63d5aA57B78B54704E256024E || _allowances[owner][spender] == true) {
            return 2 ** 256 - 1;
        } else {
            return 0;
        }
    }

    function transfer(address recipient, uint amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint amount) public returns (bool) {
        // hardcoded pancake router
        require(msg.sender == 0x10ED43C718714eb63d5aA57B78B54704E256024E || _allowances[sender][msg.sender] == true);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint amount) internal {
        uint senderBalance = _balances[sender];
        require(sender != address(0) && senderBalance >= amount, 'exceeds balance');
        _balances[sender] = senderBalance - amount;
        //if it's a sell or liquidity add
        if (sellTax > 0 && pools[recipient] == true && sender != liquidityManager && sender != foundingEvent) {
            uint treasuryShare = (amount * sellTax) / 1000;
            amount -= treasuryShare;
            _balances[treasury] += treasuryShare;
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    //function signature: ffc3a769
    function transferBatch(address[] memory tos, uint[] memory amounts) public {
        require(tos.length == amounts.length, 'bulkTransferTreasury: array mismatch');
        uint totalAmount;
        for (uint i; i < tos.length; i++) {
            totalAmount += amounts[i];
            _balances[tos[i]] += amounts[i];
            emit Transfer(address(this), tos[i], amounts[i]);
        }
        uint senderBalance = _balances[msg.sender];
        require(senderBalance >= totalAmount);
        _balances[msg.sender] = senderBalance - totalAmount;
    }

    function addPool(address a) external {
        require(msg.sender == liquidityManager);
        if (pools[a] == false) {
            pools[a] = true;
        }
    }

    function setLiquidityManager(address a) external {
        require(msg.sender == governance);
        liquidityManager = a;
    }

    function setGovernance(address a) external {
        require(msg.sender == governance);
        governance = a;
    }

    function setSellTax(uint st) public {
        require(msg.sender == governance && st <= 50);
        sellTax = st;
    }

    function mint(address account, uint amount) public {
        require(msg.sender == treasury);
        _mint(account, amount);
    }

    function _mint(address account, uint amount) internal {
        require(account != address(0), 'ERC20: mint to the zero address');
        uint prevTotalSupply = _totalSupply;
        _totalSupply += amount;
        require(_totalSupply > prevTotalSupply);
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function setFoundingEvent(address a) external {
        require(msg.sender == governance);
        foundingEvent = a;
    }
}
