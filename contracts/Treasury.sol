// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface I {
    function transfer(address to, uint value) external returns (bool);

    function balanceOf(address) external view returns (uint);

    function genesisBlock() external view returns (uint);

    function deposits(address a) external view returns (uint);

    function sold() external view returns (uint);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getPair(address t, address t1) external view returns (address pair);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function WETH() external pure returns (address);

    function approve(address spender, uint256 value) external returns (bool);

    function transferBatch(address[] memory tos, uint[] memory amounts) external;
}

import 'hardhat/console.sol';

contract Treasury {
    mapping(address => Beneficiary) public bens;
    mapping(address => Poster) public posters;
    mapping(address => AirdropRecepient) public airdrops;
    mapping(address => Founder) public founders;

    struct AddressBook {
        address governance;
        address aggregator;
        address letToken;
        address foundingEvent;
        address staking;
        address router;
        address factory;
        address stableCoin;
        address otcMarket;
        address wbnb;
    }

    AddressBook public _ab;

    uint public totalPosterRewards;
    uint public totalFounderRewards;
    uint public totalAirdropEmissions;
    uint public totBenEmission;
    uint public baseRate;
    uint public posterRate;
    bool public initialized;

    struct Beneficiary {
        uint80 amount;
        uint80 emission;
        uint32 lastClaim;
    }

    struct Poster {
        uint80 amount;
        uint32 lastClaim;
        uint80 unapprovedAmount;
        uint32 lastClaimWithSig;
        uint80 reserved;
    }

    struct AirdropRecepient {
        uint80 amount;
        uint32 lastClaim;
        bool emissionIncluded;
        uint80 reserved;
    }

    struct Founder {
        uint80 amount;
        uint32 lastClaim;
        bool registered;
        uint80 reserved;
    }

    function init(AddressBook calldata ab) public {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199);
        require(!initialized);
        initialized = true;
        posterRate = 1000;
        baseRate = 95e34;
        _ab = ab;
        I(ab.letToken).approve(ab.router, 2 ** 256 - 1);
    }

    // a hit to trust minimization, if the governance is centralized on launch
    function setAddressBook(AddressBook calldata ab) external {
        require(msg.sender == _ab.governance);
        _ab = ab;
    }

    function setPosterRate(uint rate) external {
        require(msg.sender == _ab.governance && rate <= 2000 && rate >= 100);
        posterRate = rate;
    }

    function setBaseRate(uint rate) external {
        require(msg.sender == _ab.governance && rate < baseRate && rate > 1e13);
        baseRate = rate;
    }

    // ADD
    function addBeneficiary(address a, uint amount, uint emission) public {
        require(msg.sender == _ab.governance);
        totBenEmission += emission;
        require(totBenEmission <= 1e22);
        bens[a].lastClaim = uint32(block.number);
        bens[a].amount = uint80(amount);
        bens[a].emission = uint80(emission);
    }

    function addAirdropBulk(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == _ab.governance && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 20000e18);
            airdrops[r[i]].amount += uint80(amounts[i]);
            airdrops[r[i]].lastClaim = uint32(block.number);
        }
    }

    function addPosters(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == _ab.aggregator && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 2000e18);
            posters[r[i]].unapprovedAmount += uint80(amounts[i]);
        }
    }

    function editUnapprovedPosters(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == _ab.governance && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 2000e18);
            posters[r[i]].unapprovedAmount = uint80(amounts[i]);
        }
    }

    function approvePosters(address[] calldata r) external {
        require(msg.sender == _ab.governance, 'only governance');
        uint total;
        for (uint i; i < r.length; i++) {
            uint80 amount = posters[r[i]].unapprovedAmount;
            posters[r[i]].amount += amount;
            posters[r[i]].unapprovedAmount = 0;
            if (posters[r[i]].lastClaim == 0) {
                posters[r[i]].lastClaim = uint32(block.number);
            }
            total += amount;
        }
        totalPosterRewards += total;
    }

    // CLAIM
    function getStakingRewards(address a, uint amount) external {
        require(msg.sender == _ab.staking);
        I(_ab.letToken).transfer(a, amount); //token
    }

    function claimBenRewards() external returns (uint) {
        uint amount = bens[msg.sender].amount;
        uint lastClaim = bens[msg.sender].lastClaim;
        require(block.number > lastClaim, 'too early');
        require(amount > 0, 'not beneficiary');
        uint rate = getRate();
        rate = (rate * bens[msg.sender].emission) / totBenEmission;
        uint toClaim = (block.number - lastClaim) * rate;
        uint treasuryBalance = I(_ab.letToken).balanceOf(address(this));
        uint limit = treasuryBalance > amount ? amount : treasuryBalance;
        toClaim = toClaim > limit ? limit : toClaim;
        bens[msg.sender].lastClaim = uint32(block.number);
        bens[msg.sender].amount -= uint80(toClaim);
        //console.log('toClaim:', toClaim);
        I(_ab.letToken).transfer(msg.sender, toClaim);
        return toClaim;
    }

    function claimAirdrop() external {
        _claimAirdrop(msg.sender);
    }

    function claimAirdropFor(address[] calldata a) public {
        for (uint i; i < a.length; i++) {
            _claimAirdrop(a[i]);
        }
    }

    function _claimAirdrop(address a) private {
        require(airdrops[a].amount > 0 && I(_ab.foundingEvent).genesisBlock() != 0 && block.number > airdrops[a].lastClaim);
        (uint toClaim, bool included) = airdropAvailable(a);
        if (!included) {
            airdrops[a].emissionIncluded = true;
            totalAirdropEmissions += 1;
        }
        airdrops[a].lastClaim = uint32(block.number);
        airdrops[a].amount -= uint80(toClaim);
        if (airdrops[a].amount == 0) {
            totalAirdropEmissions -= 1;
            delete airdrops[a];
        }
        I(_ab.letToken).transfer(a, toClaim);
    }

    function airdropAvailable(address a) public view returns (uint, bool) {
        uint airdrop = airdrops[a].amount;
        uint available;
        bool included = airdrops[a].emissionIncluded;
        uint freeAmount = airdrop - airdrops[a].reserved;
        uint treasuryBalance = I(_ab.letToken).balanceOf(address(this));
        uint limit = freeAmount > treasuryBalance ? treasuryBalance : freeAmount;
        if (airdrop > 0) {
            if (!included) {
                available = 1e18 < airdrop ? 1e18 : airdrop;
            } else {
                uint rate = getRate() / totalAirdropEmissions;
                rate = rate > 20e13 ? 20e13 : rate;
                available = (block.number - airdrops[a].lastClaim) * rate;
            }
        }
        available = available > limit ? limit : available;
        return (available, included);
    }

    function claimPosterRewards() external {
        uint toClaim = _claimPosterRewards(msg.sender);
        _resolveTransfer(msg.sender, toClaim);
    }

    function claimPosterRewardsFor(address[] calldata a) public {
        uint toClaim;
        for (uint i; i < a.length; i++) {
            toClaim = _claimPosterRewards(a[i]);
            _resolveTransfer(a[i], toClaim);
        }
    }

    function _claimPosterRewards(address a) private returns (uint toClaim) {
        require(posters[a].amount > 0 && block.number > posters[a].lastClaim);
        toClaim = posterRewardsAvailable(a);
        posters[a].lastClaim = uint32(block.number);
        posters[a].amount -= uint80(toClaim);
        uint treasuryBalance = I(_ab.letToken).balanceOf(address(this));
        uint tpr = totalPosterRewards;
        totalPosterRewards = tpr > toClaim ? tpr - toClaim : 0;
        uint toClaimInitial = toClaim;
        uint airdrop = airdrops[a].amount;
        if (airdrop > 0) {
            uint bonus = airdrop >= toClaim ? toClaim : airdrop;
            if (toClaim + bonus <= treasuryBalance) {
                airdrops[a].amount -= uint80(bonus);
                toClaim += bonus;
            } else {
                airdrops[a].amount -= uint80(treasuryBalance);
                toClaim += treasuryBalance;
            }
            if (airdrops[a].amount == 0) {
                if (airdrops[a].emissionIncluded) {
                    totalAirdropEmissions -= 1;
                }
                delete airdrops[a];
            }
        }
        uint founder = founders[a].amount;
        if (founder > 0) {
            uint bonus = founder >= toClaimInitial ? toClaimInitial : founder;
            if (toClaim + bonus <= treasuryBalance) {
                founders[a].amount -= uint80(bonus);
                totalFounderRewards -= bonus;
                toClaim += bonus;
            } else {
                uint left = treasuryBalance - toClaim;
                founders[a].amount -= uint80(left);
                totalFounderRewards -= left;
                toClaim += left;
            }
        }
        if (posters[a].amount == 0) {
            posters[a].lastClaim = 0;
        }
    }

    function _resolveTransfer(address a, uint toClaim) internal {
        if (a.balance <= 1e17) {
            //console.log('\x1b[33m', 'sendGasInstead, toClaim:', toClaim);
            _sendGasInstead(a, toClaim);
        } else {
            //console.log('toClaim:', toClaim);
            I(_ab.letToken).transfer(a, toClaim);
        }
    }

    function _sendGasInstead(address to, uint amount) internal {
        address[] memory ar = new address[](2);
        ar[0] = _ab.letToken;
        //ar[1] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; //wbnb
        ar[1] = I(_ab.router).WETH();
        I(_ab.router).swapExactTokensForETH(amount, 0, ar, to, 2 ** 256 - 1);
    }

    function posterRewardsAvailable(address a) public view returns (uint) {
        uint posterAmount = posters[a].amount;
        if (posterAmount > 0) {
            uint reserved = posters[a].reserved;
            uint rate = (((getRate() * posterAmount) / totalPosterRewards) * posterRate) / 1000;
            uint amount = (block.number - posters[a].lastClaim) * rate;
            uint treasuryBalance = I(_ab.letToken).balanceOf(address(this));
            uint limit = posterAmount - reserved > treasuryBalance ? treasuryBalance : posterAmount - reserved;
            amount = amount > limit ? limit : amount;
            return amount;
        }
        return 0;
    }

    // only posters should be able to do this
    function lockPendingRewards(address a) public returns (uint32 freePendingE15, uint32 blocks) {
        require(msg.sender == _ab.staking);
        uint80 posterAmount = posters[a].amount;
        uint80 reserved = posters[a].reserved;
        uint80 treasuryBalance = uint80(I(_ab.letToken).balanceOf(address(this)));
        uint freePending = (posterAmount - reserved > treasuryBalance ? treasuryBalance : posterAmount - reserved);
        freePendingE15 = uint32(freePending / 1e15);
        uint rate = (((getRate() * posterAmount) / totalPosterRewards) * posterRate) / 1000;
        blocks = uint32(uint80(freePendingE15 * 1e15) / rate + block.number);
        posters[a].amount = posterAmount - uint80(freePendingE15) * 1e15;
        posters[a].lastClaim = uint32(block.number);
        totalPosterRewards -= freePending;
        I(_ab.letToken).transfer(_ab.staking, freePendingE15 * 1e15);
    }

    function claimFounderRewards() external {
        _claimFounderRewards(msg.sender);
    }

    function claimFounderRewardsFor(address[] calldata a) public {
        for (uint i; i < a.length; i++) {
            _claimFounderRewards(a[i]);
        }
    }

    function _claimFounderRewards(address a) private {
        uint genesis = I(_ab.foundingEvent).genesisBlock();
        if (!founders[a].registered && genesis != 0) {
            uint deposit = I(_ab.foundingEvent).deposits(a);
            require(deposit > 0);
            founders[a].amount = uint80(deposit);
            founders[a].lastClaim = uint32(genesis); //redundant
            founders[a].registered = true;
            if (totalFounderRewards == 0) {
                totalFounderRewards = I(_ab.foundingEvent).sold();
            }
        }
        uint tfr = totalFounderRewards;
        require(founders[a].amount > 0 && block.number > founders[a].lastClaim);
        uint toClaim = founderRewardsAvailable(a);
        founders[a].lastClaim = uint32(block.number);
        founders[a].amount -= uint80(toClaim);
        totalFounderRewards = tfr >= toClaim ? tfr - toClaim : 0;
        I(_ab.letToken).transfer(a, toClaim);
    }

    function founderRewardsAvailable(address a) public view returns (uint) {
        uint founderAmount = founders[a].amount;
        if (founderAmount > 0) {
            uint lastClaim = founders[a].lastClaim;
            lastClaim = lastClaim > 0 ? lastClaim : I(_ab.foundingEvent).genesisBlock();
            uint reserved = founders[a].reserved;
            uint rate = (getRate() * 5 * founderAmount) / totalFounderRewards;
            uint amount = (block.number - founders[a].lastClaim) * rate;
            uint treasuryBalance = I(_ab.letToken).balanceOf(address(this));
            uint limit = treasuryBalance > founderAmount - reserved ? founderAmount - reserved : treasuryBalance;
            amount = amount > limit ? limit : amount;
            return amount;
        }
        return 0;
    }

    // still vulnerable, sort of, dont forget
    function _calculateLetAmountInToken(address token, uint amount) internal view returns (uint) {
        //console.log('amount:', amount);
        address factory = _ab.factory;
        //console.log('\x1b[33mFACTORY:', factory);
        address letToken = _ab.letToken;
        //console.log('\x1b[33mLET:', letToken);
        address pool = I(factory).getPair(token, letToken);
        (address token0, ) = letToken < token ? (letToken, token) : (token, letToken);
        //console.log('\x1b[33mPOOL:', pool);
        (uint reserve0, uint reserve1, ) = I(pool).getReserves();
        //console.log('\x1b[33mreserve0:', reserve0);
        //console.log('\x1b[33mreserve1:', reserve1);
        (uint reserveToken, uint reserveLET) = token == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return (amount * reserveToken) / reserveLET;
    }

    function getRate() public view returns (uint rate) {
        address stableCoin = _ab.stableCoin;
        //console.log('\x1b[33mSTABLECOIN:', stableCoin);
        uint time = block.timestamp - 1609459200; //portable
        uint price = _calculateLetAmountInToken(stableCoin, 1e18);
        rate = price > 1e18 ? baseRate / price / time : rate = baseRate / 1e18 / time;
    }

    /// OTC MARKET add enum instead
    function reserveForOTC(address a, uint80 amount, uint t) public {
        require(msg.sender == _ab.otcMarket);
        if (t == 0) {
            uint freeAmount = founders[a].amount - founders[a].reserved;
            require(freeAmount >= amount);
            founders[a].reserved = amount;
        } else if (t == 1) {
            uint freeAmount = posters[a].amount - posters[a].reserved;
            require(freeAmount >= amount);
            posters[a].reserved = amount;
        } else {
            uint freeAmount = airdrops[a].amount - airdrops[a].reserved;
            require(freeAmount >= amount);
            airdrops[a].reserved = amount;
        }
    }

    function reassignOTCShare(address from, address to, uint80 amount, uint t) public {
        require(msg.sender == _ab.otcMarket);
        if (t == 0) {
            founders[from].reserved -= amount;
            founders[from].amount -= amount;
            founders[to].amount += amount;
            founders[to].lastClaim = uint32(block.number);
            if (!founders[to].registered) {
                founders[to].registered = true;
            }
        } else if (t == 1) {
            posters[from].reserved -= amount;
            posters[from].amount -= amount;
            posters[to].amount += amount;
            posters[to].lastClaim = uint32(block.number);
        } else {
            airdrops[from].reserved -= amount;
            airdrops[from].amount -= amount;
            airdrops[to].amount += amount;
            airdrops[to].lastClaim = uint32(block.number);
            airdrops[to].emissionIncluded = airdrops[from].emissionIncluded;
        }
    }
}
