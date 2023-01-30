// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

import 'hardhat/console.sol';

// Aletheo keeper is supposed to not as negatively impact tokenomics or project funding as other abstract keepers
// this is the most abstract version, probably too expensive, will be updated as soon as time comes to gas tests

// major security concern: users shouldn't sign anything through dapps they dont trust.
// attacker can forge a malicious signature by tricking users into signing a malicious request.
// this version attempts to handle it, but it's probably futile anyway, it can be cleaner and cheaper
// technically no third party can access user funds without user' help
// babysitting users wont help this contract to be useful
contract KeeperGateway {
    mapping(uint => Path) public paths;
    mapping(address => User) public users;
    mapping(address => bool) public authorized;

    address public governance;
    uint public latestAddedPath;

    struct User {
        mapping(uint => uint) forbiddenSaltsBitMap; // we dont use nonces, we need to also support subscriptions in gas efficient way
        mapping(uint => uint) indexLastClaims;
        mapping(uint => uint) forbidPathBitMap;
        bool forbidAll;
    }

    struct Path {
        address callee;
        bytes4 selector;
        bool onlyAuthorized;
    }

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
        uint salt;
        address returnToken;
        address tokenInUse;
    }

    constructor() {
        governance = msg.sender;
    }

    function callBySignature(Request calldata reqt) external {
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
        (bool success, bytes memory data) = reqt.callee.call(abi.encodeWithSelector(reqt.selector, reqt.callData));
        require(success == true, 'what went wrong');

        // take fee and complete
        uint toClaim;
        //posters[a].lastClaimWithSig = uint32(block.number);
        uint approxGas = (initGasLeft - gasleft() /*+ 21000 */) * gasPrice;
        uint keeperReward;
        require(toClaim >= keeperReward * 3);
        if (reqt.signer.balance <= 1e17) {} else {}
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
        bytes32 domainSeparator = keccak256(abi.encodePacked(DOMAIN_TYPEHASH, chainId, reqt.selector, address(this)));
        bytes32 hashStruct;
        {
            hashStruct = keccak256(abi.encodePacked(reqt.signer, reqt.callee, reqt.index, reqt.tip, reqt.interval, reqt.salt, reqt.callData));
        }
        bytes32 message = keccak256(abi.encodePacked(domainSeparator, hashStruct));
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

    // emergency case for a gullible user, trustless contract does not have to handle this but its a nice have
    function forbidAllFor(address a) public {
        require(msg.sender == governance);
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
