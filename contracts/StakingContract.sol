// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface I {
    function balanceOf(address a) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint amount) external returns (bool);

    function getRewards(address a, uint rewToClaim) external;

    function lockPendingRewards(address a) external returns (uint32 freePending, uint32 blocks);
}

// this contract' beauty is being restored
contract StakingContract {
    mapping(address => Staker) public stakers;
    mapping(uint => TokenReward) public tokenRewards;
    mapping(address => mapping(address => Delegate)) public delegates;

    struct TokenReward {
        address token;
        uint32 registerBlock;
        uint initialAmount;
        uint reservedStorage1;
        uint reservedStorage2;
    }

    struct Delegate {
        uint24 amountE16;
        bool votingPower;
        uint reservedStorage1;
        uint reservedStorage2;
    }

    struct Staker {
        mapping(uint => uint) claimedTokenRewards;
        mapping(uint => uint) unclaimedTokenRewards; //if user unstakes and has something unclaimed this will record it
        uint32 amountE15;
        uint32 lastClaim;
        uint32 lockUpTo;
        uint32 reservedE15;
        uint32 unclaimedShareE15;
        uint24 delegatingToOthersE16;
        uint24 delegatedByOthersE16;
        uint24 votingToOthersE16;
        uint24 votingByOthersE16;
        uint firstTokenRewardId;
        uint reservedStorage1;
        uint reservedStorage2;
    }

    event NewStake(address indexed staker, uint stakeAmount, uint unlockBlock);
    event Unstake(address indexed staker, uint unstakeAmount);
    event NewDelegate(address indexed from, address indexed to, Delegate delegate);

    struct AddressBook {
        address letToken;
        address treasury;
        address otcMarket;
        address campaignMarket;
    }

    AddressBook public _ab;
    bool public initialized;
    uint128 public totalLetLocked;
    uint128 public lastTokenRewardId;

    uint private reservedStorage1;
    uint private reservedStorage2;
    uint private reservedStorage3;
    uint private reservedStorage4;

    function init(AddressBook memory ab) public {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199);
        require(!initialized);
        initialized = true;
        _ab = ab;
    }

    function safeLock(uint32 amountE15, uint32 blocks) public {
        I(_ab.letToken).transferFrom(msg.sender, address(this), uint(amountE15) * 1e15);
        uint32 safeBlocks = _checkSafeBlocks();
        blocks = blocks > safeBlocks ? safeBlocks : blocks;
        _lock(msg.sender, amountE15, blocks);
    }

    function lock(uint32 amountE15, uint32 blocks) public {
        I(_ab.letToken).transferFrom(msg.sender, address(this), amountE15 * 1e15);
        _lock(msg.sender, amountE15, blocks);
    }

    function lockPendingPosterRewards() public {
        (uint32 amountE15, uint32 blocks) = I(_ab.treasury).lockPendingRewards(msg.sender);
        _lock(msg.sender, amountE15, blocks);
    }

    function _lock(address a, uint32 amountE15, uint32 blocks) private {
        _getLockRewards(a);
        require(blocks > stakers[a].lockUpTo);
        stakers[a].lockUpTo = blocks;
        require(amountE15 > 0 && I(_ab.letToken).balanceOf(a) >= amountE15 * 1e15);
        uint32 prevAmountE15 = stakers[a].amountE15;
        if (prevAmountE15 == 0) {
            stakers[a].firstTokenRewardId = lastTokenRewardId + 1;
        }
        stakers[a].amountE15 = prevAmountE15 + amountE15;
        totalLetLocked += amountE15 * 1e15;
        emit NewStake(a, amountE15 * 1e15, blocks);
    }

    function lockPendingPosterRewardsWithSignature() public {
        (uint32 amountE15, uint32 blocks) = I(_ab.treasury).lockPendingRewards(msg.sender);
        _lock(msg.sender, amountE15, blocks);
    }

    function safeUnstake(uint32 amountE15) public {
        _getAllTokenRewards(msg.sender);
        _unstake(msg.sender, amountE15);
    }

    function unstake(uint32 amountE15) public {
        _recordUnclaimedTokenRewards(msg.sender);
        _unstake(msg.sender, amountE15);
    }

    function forceUnstake(uint32 amountE15) public {
        _unstake(msg.sender, amountE15);
    }

    function _recordUnclaimedTokenRewards(address a) internal {
        uint firstTokenRewardId = stakers[a].firstTokenRewardId;
        uint lockUpTo = stakers[a].lockUpTo;
        require(lockUpTo > block.number);
        uint unclaimedWord;
        uint claimedWord;
        uint wordIndex;
        uint bitIndex;
        for (uint i = firstTokenRewardId; i < lastTokenRewardId; i++) {
            if (i / 256 != wordIndex) {
                stakers[a].unclaimedTokenRewards[wordIndex] = unclaimedWord;
                wordIndex = i / 256;
                unclaimedWord = stakers[a].unclaimedTokenRewards[wordIndex];
                claimedWord = stakers[a].unclaimedTokenRewards[wordIndex];
            }
            bitIndex = i % 256;
            if (claimedWord & (1 << bitIndex) == 0) {
                unclaimedWord = unclaimedWord | (1 << bitIndex);
            }
        }
        stakers[a].unclaimedTokenRewards[wordIndex] = unclaimedWord;
        stakers[a].unclaimedShareE15 = uint32(uint((stakers[a].amountE15 * 1e15)) / totalLetLocked / 1e15);
    }

    function _unstake(address a, uint32 amountE15) internal {
        require(
            (stakers[msg.sender].amountE15 - stakers[msg.sender].reservedE15) * 10 - stakers[msg.sender].delegatingToOthersE16 >= amountE15 * 10 &&
                totalLetLocked >= amountE15 * 1e15 &&
                block.number > stakers[msg.sender].lockUpTo
        );
        _getLockRewards(msg.sender);
        stakers[a].amountE15 -= amountE15;
        I(_ab.letToken).transfer(a, (amountE15 * 1e15 * 99) / 100);
        uint leftOver = 1e15 * (amountE15 - (amountE15 * 99) / 100);
        I(_ab.letToken).transfer(_ab.treasury, leftOver); //1% burn to treasury as protection against malicious poster spam
        totalLetLocked -= amountE15 * 1e15;
        emit Unstake(a, amountE15 * 1e15);
    }

    function _checkSafeBlocks() internal view returns (uint32) {
        bytes32 PROPOSE_BLOCK_SLOT = 0x4b50776e56454fad8a52805daac1d9fd77ef59e4f1a053c342aaae5568af1388;
        uint proposeBlock;
        assembly {
            proposeBlock := sload(PROPOSE_BLOCK_SLOT)
        }
        if (block.number > proposeBlock) {
            uint nextLogicBlock;
            bytes32 NEXT_LOGIC_BLOCK_SLOT = 0xe3228ec3416340815a9ca41bfee1103c47feb764b4f0f4412f5d92df539fe0ee;
            assembly {
                nextLogicBlock := sload(NEXT_LOGIC_BLOCK_SLOT)
            }
            require(block.number < nextLogicBlock, 'unsafe period');
            return uint32(nextLogicBlock) - 86400;
        }
        uint zeroTrustPeriod;
        bytes32 ZERO_TRUST_PERIOD_SLOT = 0x7913203adedf5aca5386654362047f05edbd30729ae4b0351441c46289146720;
        assembly {
            zeroTrustPeriod := sload(ZERO_TRUST_PERIOD_SLOT)
        }
        return uint32(proposeBlock + zeroTrustPeriod) - 86400;
    }

    function getLockRewards() public returns (uint) {
        require(stakers[msg.sender].amountE15 > 0);
        return _getLockRewards(msg.sender);
    }

    function getLockRewardsFor(address[] memory a) public {
        for (uint i; i < a.length; i++) {
            require(stakers[a[i]].amountE15 > 0);
            _getLockRewards(a[i]);
        }
    }

    function _getLockRewards(address a) private returns (uint) {
        uint toClaim = 0;
        if (stakers[a].amountE15 > 0) {
            toClaim = lockRewardsAvailable(a);
            I(_ab.treasury).getRewards(a, toClaim);
            //stakers[msg.sender].lockUpTo=uint32(block.number+720000);//alert: it was a hot fix
        }
        stakers[msg.sender].lastClaim = uint32(block.number);
        return toClaim;
    }

    function lockRewardsAvailable(address a) public view returns (uint) {
        if (stakers[a].amountE15 > 0) {
            uint rate = 47e13;
            uint rateCap = (totalLetLocked * 100) / 100000e18;
            rateCap > 100 ? 100 : rateCap;
            rate *= rateCap / 100;
            uint lockUpTo = stakers[a].lockUpTo;
            uint limit = lockUpTo > block.number ? block.number : lockUpTo;
            uint amount = ((limit - stakers[a].lastClaim) * stakers[a].amountE15 * 1e15 * rate) / totalLetLocked;
            return amount;
        } else {
            return 0;
        }
    }

    function getTokenRewards(uint[] memory ids) public {
        _getTokenRewards(msg.sender, ids);
    }

    // gas saver
    function getSpecificTokenRewards(address token, uint[] memory ids) public {
        _getSpecificTokenRewards(msg.sender, token, ids);
    }

    function getAllTokenRewards() public {
        _getAllTokenRewards(msg.sender);
    }

    function _getAllTokenRewards(address a) internal {
        uint firstTokenRewardId = stakers[a].firstTokenRewardId;
        uint len = firstTokenRewardId - lastTokenRewardId;
        uint[] memory ids = new uint[](len);
        for (uint i = 0; i < len; i++) {
            ids[i] = i + firstTokenRewardId;
        }
        _getTokenRewards(a, ids);
    }

    function _getTokenRewards(address a, uint[] memory ids) internal {
        uint lockUpTo = stakers[a].lockUpTo;
        require(lockUpTo > block.number);
        uint wordIndex;
        uint word;
        uint bitIndex;
        uint amount;
        for (uint i; i < ids.length; i++) {
            if (ids[i] / 256 != wordIndex) {
                stakers[a].claimedTokenRewards[wordIndex] = word;
                wordIndex = ids[i] / 256;
                word = stakers[a].claimedTokenRewards[wordIndex];
            }
            bitIndex = ids[i] % 256;
            if (word & (1 << bitIndex) == 0) {
                amount = (stakers[a].amountE15 * 1e15 * tokenRewards[ids[i]].initialAmount) / totalLetLocked;
                I(tokenRewards[ids[i]].token).transfer(a, amount);
                word = word | (1 << bitIndex);
            }
        }
    }

    function _getSpecificTokenRewards(address a, address token, uint[] memory ids) internal {
        uint lockUpTo = stakers[a].lockUpTo;
        require(lockUpTo > block.number);
        uint wordIndex;
        uint word;
        uint bitIndex;
        uint amount;
        for (uint i; i < ids.length; i++) {
            if (ids[i] / 256 != wordIndex) {
                stakers[a].claimedTokenRewards[wordIndex] = word;
                wordIndex = ids[i] / 256;
                word = stakers[a].claimedTokenRewards[wordIndex];
            }
            bitIndex = ids[i] % 256;
            if (word & (1 << bitIndex) == 0) {
                require(token == tokenRewards[ids[i]].token);
                amount += (stakers[a].amountE15 * 1e15 * tokenRewards[ids[i]].initialAmount) / totalLetLocked;
                word = word | (1 << bitIndex);
            }
        }
        I(token).transfer(a, amount);
    }

    function registerToken(TokenReward memory token) public {
        I(token.token).transferFrom(msg.sender, address(this), token.initialAmount);
        tokenRewards[++lastTokenRewardId] = token;
    }

    function delegate(address[] memory accs, Delegate[] calldata del) public {
        int24 totalDiffE16;
        int24 totalVotingDiffE16;
        for (uint i; i < accs.length; i++) {
            int24 diffE16 = int24(del[i].amountE16 - delegates[msg.sender][accs[i]].amountE16);
            totalDiffE16 += diffE16;
            delegates[msg.sender][accs[i]] = del[i];
            uint24 delegatedByOthersE16 = stakers[accs[i]].delegatedByOthersE16;
            stakers[accs[i]].delegatedByOthersE16 = uint24(int24(delegatedByOthersE16) + diffE16); //these int operations always result in positive
            if (del[i].votingPower) {
                uint24 votingByOthersE16 = stakers[accs[i]].votingByOthersE16;
                stakers[accs[i]].votingByOthersE16 = uint24(int24(votingByOthersE16) + diffE16);
                totalVotingDiffE16 += diffE16;
            }
            emit NewDelegate(msg.sender, accs[i], del[i]);
        }
        uint24 delegatingToOthersE16 = stakers[msg.sender].delegatingToOthersE16;
        require(uint40(stakers[msg.sender].amountE15 * 10) - uint24(int24(delegatingToOthersE16) + totalDiffE16) >= 0);
        stakers[msg.sender].delegatingToOthersE16 = uint24(int24(delegatingToOthersE16) + totalDiffE16);
        uint24 votingToOthersE16 = stakers[msg.sender].votingToOthersE16;
        stakers[msg.sender].votingToOthersE16 = uint24(int24(votingToOthersE16) + totalVotingDiffE16);
    }

    function reassignOTCShare(address from, address to, uint32 amountE15) public {
        require(msg.sender == _ab.otcMarket);
        _getLockRewards(from);
        stakers[to].amountE15 += amountE15;
        stakers[to].lastClaim = uint32(block.number);
        stakers[to].lockUpTo = stakers[from].lockUpTo;
        stakers[from].amountE15 -= amountE15;
        stakers[from].reservedE15 -= amountE15;
        if (stakers[from].amountE15 == 0) {
            stakers[from].lockUpTo = uint32(block.number);
        }
        emit Unstake(from, amountE15 * 1e15);
        emit NewStake(to, amountE15 * 1e15, stakers[to].lockUpTo);
    }

    function reserveForOTC(address a, uint32 amountE15) public {
        require(msg.sender == _ab.otcMarket && stakers[a].amountE15 * 10 - stakers[a].delegatingToOthersE16 >= amountE15);
        stakers[a].reservedE15 = amountE15;
    }
}
