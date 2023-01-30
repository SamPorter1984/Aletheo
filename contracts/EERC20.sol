// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

// A modification of OpenZeppelin ERC20
// Original can be found here: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
import 'hardhat/console.sol';

struct Request {
    bytes4 selector;
    address signer;
    bytes signature;
    uint chainId;
    address callee;
    bytes callData;
    uint index;
    uint tip;
    uint interval; // if 0, it's one time transaction, if above 0, it's a subscription
    string domainTypehash;
    bool needsHelper; // uniswap trades fail if token address is the sender
    uint salt;
    address returnToken;
    address tokenInUse;
    string functionName;
    uint minOut;
}

contract EERC20 {
    mapping(address => bool) public pools;
    mapping(uint => Path) public paths;
    mapping(address => User) public users;
    mapping(address => bool) public authorized;
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    struct User {
        mapping(uint => uint) forbiddenSaltsBitMap; // we dont use nonces, we need to also support subscriptions in gas efficient way
        mapping(uint => uint) indexLastClaims;
        mapping(uint => uint) forbidPathBitMap;
        mapping(address => bool) allowances;
        uint balance;
        bool forbidAll;
    }

    struct Path {
        address callee;
        bytes4 selector;
        bool onlyAuthorized;
    }

    struct AddressBook {
        address liquidityManager;
        address governance;
        address treasury;
        address foundingEvent;
        address factory;
        address helper;
        address WETH;
    }

    AddressBook public _ab;

    string public name;
    string public symbol;
    uint private _totalSupply;
    bool public ini;
    uint public sellTax;
    uint public latestAddedPath;

    function init(AddressBook calldata addressBook) public {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199);
        require(ini == false, 'already initialized');
        ini = true;
        name = 'Aletheo';
        symbol = 'LET';
        _ab = addressBook;
        _mint(addressBook.governance, 15000e18);
        _mint(addressBook.treasury, 50000e18);
        _mint(addressBook.foundingEvent, 100000e18);
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply - users[0x000000000000000000000000000000000000dEaD].balance - users[address(0)].balance;
    }

    function decimals() public pure returns (uint) {
        return 18;
    }

    function balanceOf(address a) public view returns (uint) {
        return users[a].balance;
    }

    function disallow(address spender) public returns (bool) {
        delete users[msg.sender].allowances[spender];
        emit Approval(msg.sender, spender, 0);
        return true;
    }

    function approve(address spender, uint amount) public returns (bool) {
        if (spender == 0x10ED43C718714eb63d5aA57B78B54704E256024E) {
            // hardcoded pancake router
            emit Approval(msg.sender, spender, 2 ** 256 - 1);
            return true;
        } else {
            users[msg.sender].allowances[spender] = true;
            emit Approval(msg.sender, spender, 2 ** 256 - 1);
            return true;
        }
    }

    function allowance(address owner, address spender) public view returns (uint) {
        // hardcoded pancake router
        if (spender == 0x10ED43C718714eb63d5aA57B78B54704E256024E || users[owner].allowances[spender] == true) {
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
        require(msg.sender == 0x10ED43C718714eb63d5aA57B78B54704E256024E || users[sender].allowances[msg.sender] == true);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint amount) internal {
        uint senderBalance = users[sender].balance;
        require(senderBalance >= amount, 'exceeds balance');
        users[sender].balance = senderBalance - amount;
        //if it's a sell or liquidity add
        if (sellTax > 0 && pools[recipient] == true && sender != _ab.liquidityManager && sender != _ab.foundingEvent) {
            uint treasuryShare = (amount * sellTax) / 1000;
            amount -= treasuryShare;
            users[_ab.treasury].balance += treasuryShare;
        }
        users[recipient].balance += amount;
        emit Transfer(sender, recipient, amount);
    }

    //function signature:
    function transferBatch(address[] memory tos, uint[] memory amounts) public {
        require(tos.length == amounts.length, 'bulkTransferTreasury: array mismatch');
        uint totalAmount;
        for (uint i; i < tos.length; i++) {
            totalAmount += amounts[i];
            users[tos[i]].balance += amounts[i];
            emit Transfer(address(this), tos[i], amounts[i]);
        }
        uint senderBalance = users[msg.sender].balance;
        require(senderBalance >= totalAmount);
        users[msg.sender].balance = senderBalance - totalAmount;
    }

    function addPool(address a) external {
        require(msg.sender == _ab.liquidityManager);
        if (pools[a] == false) {
            pools[a] = true;
        }
    }

    function setAddressBook(AddressBook memory ab) external {
        require(msg.sender == _ab.governance);
        _ab = ab;
    }

    function setSellTax(uint st) public {
        require(msg.sender == _ab.governance && st <= 50);
        sellTax = st;
    }

    function mint(address account, uint amount) public {
        require(msg.sender == _ab.treasury);
        _mint(account, amount);
    }

    function _mint(address account, uint amount) internal {
        uint prevTotalSupply = _totalSupply;
        _totalSupply += amount;
        require(_totalSupply > prevTotalSupply);
        users[account].balance += amount;
        emit Transfer(address(0), account, amount);
    }

    ///for keepers
    function callBySignature(Request calldata reqt) external payable {
        uint gasPrice;
        assembly {
            gasPrice := gasprice()
        }
        uint initGasLeft = gasleft();
        require(!users[reqt.signer].forbidAll, 'forbid all is active');
        _verifySig(reqt);

        // check if allowed to use this signature
        require(block.timestamp > users[reqt.signer].indexLastClaims[reqt.index] + reqt.interval, 'sig cant be valid yet');
        require(users[reqt.signer].forbiddenSaltsBitMap[reqt.salt / 256] & (1 << reqt.salt % 256) == 0, 'forbidden salt');

        // checks for allowed paths. looks kind of deletable, except it's an attempt to protect the most gullible.
        // otherwise, whats already there is sufficient
        require(users[reqt.signer].forbidPathBitMap[reqt.index / 256] & (1 << reqt.index % 256) == 0, 'forbidden path');
        if (paths[reqt.index].onlyAuthorized) require(authorized[msg.sender], 'not authorized');
        require(reqt.selector == paths[reqt.index].selector);
        require(reqt.callee == paths[reqt.index].callee);

        // record state change if any
        if (reqt.interval > 0) {
            users[reqt.signer].indexLastClaims[reqt.index] = block.timestamp;
        } else {
            _forbidSalt(reqt.signer, reqt.salt);
        }
        // call
        // if data is 0, subtract keeper reward from user balance here
        // otherwise data should return amount which is then being split between the user and the keeper
        bytes memory data;
        bool success;
        if (reqt.needsHelper) {
            (success, data) = I(_ab.helper).handle{value: msg.value}(reqt);
            require(success == true, 'helper cant handle');
        } else {
            (success, data) = reqt.callee.call{value: msg.value}(abi.encodeWithSelector(reqt.selector, reqt.callData));
            require(success == true, 'what went wrong');
        }

        // take fee and complete
        uint amount; // compute amount from data bytes
        assembly {
            amount := mload(add(data, 0x20))
        }
        uint approxGas = (initGasLeft - gasleft() /*+ 21000 */) * gasPrice;
        uint keeperReward = _calculateAmountInNativeToken(reqt.returnToken, approxGas + reqt.tip);
        require(amount - keeperReward >= reqt.minOut);
        if (reqt.returnToken == address(this)) {
            users[msg.sender].balance += keeperReward;
            users[reqt.signer].balance += amount - keeperReward;
        } else {
            if (reqt.returnToken == address(0)) {
                (success, data) = payable(msg.sender).call{value: keeperReward}('');
                require(success);
                (success, data) = payable(reqt.signer).call{value: amount - keeperReward}('');
                require(success);
            } else {
                I(reqt.returnToken).transfer(msg.sender, keeperReward);
                I(reqt.returnToken).transfer(reqt.signer, amount - keeperReward);
            }
        }
    }

    function _calculateAmountInNativeToken(address returnToken, uint amount) internal view returns (uint) {
        address factory = _ab.factory;
        address WETH = _ab.WETH;
        address pool = I(factory).getPair(returnToken, WETH);
        (address token0, ) = WETH < returnToken ? (WETH, returnToken) : (returnToken, WETH);
        (uint reserve0, uint reserve1, ) = I(pool).getReserves();
        (uint reserveToken, uint reserveWETH) = returnToken == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return (amount * reserveToken) / reserveWETH;
    }

    function _verifySig(Request memory reqt) public {
        bytes memory signature = reqt.signature;
        bytes32 DOMAIN_TYPEHASH = keccak256(bytes(reqt.domainTypehash));
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint chainId;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
            chainId := chainid()
        }
        bytes32 domainSeparator = keccak256(abi.encodePacked(DOMAIN_TYPEHASH, chainId, reqt.functionName, reqt.selector, address(this)));
        bytes32 hashStructEssentail = keccak256(abi.encodePacked(reqt.signer, reqt.callee, reqt.salt, reqt.index));
        bytes32 hashStructOptions = keccak256(
            abi.encodePacked(reqt.tip, reqt.interval, reqt.returnToken, reqt.tokenInUse, reqt.callData, reqt.minOut)
        );

        bytes32 message = keccak256(abi.encodePacked(domainSeparator, hashStructEssentail, hashStructOptions));
        bytes32 digest = keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', message));
        address signer = ecrecover(digest, v, r, s);
        require(signer == reqt.signer, 'sig does not match request');
    }

    function forbidPaths(uint[] calldata ids, uint[] calldata values) public {
        _forbidPaths(msg.sender, ids, values);
    }

    // ids should be submitted in order
    function _forbidPaths(address a, uint[] calldata ids, uint[] calldata values) internal {
        uint word;
        uint bitIndex;
        uint wordIndex;
        for (uint i; i < ids.length; i++) {
            if (ids[i] / 256 != wordIndex) {
                users[a].forbidPathBitMap[wordIndex] = word;
                wordIndex = ids[i] / 256;
                word = users[a].forbidPathBitMap[wordIndex];
            }
            bitIndex = ids[i] % 256;
            if (word & (1 << bitIndex) != values[i]) {
                word ^= (1 << bitIndex);
            }
        }
    }

    function forbidSalt(uint salt) public {
        _forbidSalt(msg.sender, salt);
    }

    function _forbidSalt(address a, uint salt) internal {
        users[a].forbiddenSaltsBitMap[salt / 256] |= (1 << salt % 256);
    }

    function _forbidSalts(address a, uint[] calldata salts) internal {
        uint word;
        uint bitIndex;
        uint wordIndex;
        for (uint i; i < salts.length; i++) {
            if (salts[i] / 256 != wordIndex) {
                users[a].forbiddenSaltsBitMap[wordIndex] = word;
                wordIndex = salts[i] / 256;
                word = users[a].forbiddenSaltsBitMap[wordIndex];
            }
            bitIndex = salts[i] % 256;
            if (word & (1 << bitIndex) == 0) {
                word |= (1 << bitIndex);
            }
        }
    }

    // it will be a pain for a user to cherrypick
    // what to toggle without frontend help
    // also keeps the bitmap settings
    function forbidAll() public {
        users[msg.sender].forbidAll = true;
    }

    function unforbidAll() public {
        users[msg.sender].forbidAll = false;
    }

    // emergency case for a gullible user, who does not even know how to transact
    // on their own yet, because used meta transactions for months
    // trustless contract does not have to handle this but its a nice have
    function forbidAllFor(address a) public {
        require(msg.sender == _ab.governance);
        users[a].forbidAll = true;
    }

    function addPaths(Path[] calldata paths_) public {
        for (uint i; i < paths_.length; i++) {
            paths[latestAddedPath + 1 + i] = paths_[i];
        }
        latestAddedPath += paths_.length;
    }

    // can invalidate a lot of previously generated signatures attached to some malicious path which is nice
    function setPaths(uint[] calldata ids, Path[] calldata paths_) public {
        for (uint i; i < ids.length; i++) {
            paths[ids[i]] = paths_[i];
        }
    }
}

interface I {
    function getPair(address t, address t1) external view returns (address pair);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function handle(Request calldata req) external payable returns (bool, bytes calldata);

    function transfer(address to, uint value) external returns (bool);
}
