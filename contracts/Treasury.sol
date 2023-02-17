// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

import 'hardhat/console.sol'; //alert

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

contract Treasury {
    mapping(address => Beneficiary) public bens;
    mapping(address => Poster) public posters;
    mapping(address => AirdropRecepient) public airdrops;
    mapping(address => Founder) public founders;

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

    struct AddressBook {
        address governance;
        address aggregator;
        address letToken;
        address foundingEvent;
        address router;
        address factory;
        address stableCoin;
        address otcMarket;
        address WETH;
    }

    AddressBook public ab;
    uint abLastUpdate;
    AddressBook public abPending;

    uint public totalPosterRewards;
    uint public totalFounderRewards;
    uint public totalAirdropEmissions;
    uint public totBenEmission;
    uint public baseRate;
    uint public posterRate;
    bool public initialized;

    function init(AddressBook calldata _ab) public {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199); //alert
        require(!initialized);
        initialized = true;
        posterRate = 2000;
        baseRate = 1e31;
        abLastUpdate = block.number;
        ab = _ab;
        I(ab.letToken).approve(ab.router, 2 ** 256 - 1);
    }

    modifier notContract() {
        address a = msg.sender;
        uint s;
        assembly {
            s := extcodesize(a)
        }
        require(s == 0);
        _;
    }

    function setPendingAddressBook(AddressBook calldata pab_) external {
        require(msg.sender == ab.governance);
        abPending = pab_;
    }

    function setAddressBook() external {
        require(msg.sender == ab.governance && abLastUpdate > block.number + 1209600); // 2 weeks for this version
        abLastUpdate = block.number;
        ab = abPending;
    }

    function setPosterRate(uint rate) external {
        require(msg.sender == ab.governance && rate <= 4000 && rate >= 100);
        posterRate = rate;
    }

    function setBaseRate(uint rate) external {
        require(msg.sender == ab.governance && rate < baseRate && rate > 1e20);
        baseRate = rate;
    }

    // ADD
    function addBeneficiary(address a, uint amount, uint emission) public {
        require(msg.sender == ab.governance);
        totBenEmission += emission;
        require(totBenEmission <= 1e22);
        bens[a].lastClaim = uint32(block.number);
        bens[a].amount = uint80(amount);
        bens[a].emission = uint80(emission);
    }

    function addAirdropBulk(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == ab.governance && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 10000e18);
            airdrops[r[i]].amount += uint80(amounts[i]);
            airdrops[r[i]].lastClaim = uint32(block.number);
        }
    }

    // this is probably suboptimal
    function addPosters(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == ab.aggregator && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 2000e18);
            posters[r[i]].unapprovedAmount += uint80(amounts[i]);
        }
    }

    function editUnapprovedPosters(address[] calldata r, uint[] calldata amounts) external {
        require(msg.sender == ab.governance && r.length == amounts.length);
        for (uint i; i < r.length; i++) {
            require(amounts[i] < 2000e18);
            posters[r[i]].unapprovedAmount = uint80(amounts[i]);
        }
    }

    function approvePosters(address[] calldata r) external {
        require(msg.sender == ab.governance, 'only governance');
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

    function claimBenRewards() external notContract returns (uint) {
        uint amount = bens[msg.sender].amount;
        uint lastClaim = bens[msg.sender].lastClaim;
        require(block.number > lastClaim, 'too early');
        require(amount > 0, 'not beneficiary');
        uint rate = getRate();
        rate = (rate * bens[msg.sender].emission) / totBenEmission;
        uint toClaim = (block.number - lastClaim) * rate;
        uint treasuryBalance = I(ab.letToken).balanceOf(address(this));
        uint limit = treasuryBalance > amount ? amount : treasuryBalance;
        toClaim = toClaim > limit ? limit : toClaim;
        bens[msg.sender].lastClaim = uint32(block.number);
        bens[msg.sender].amount -= uint80(toClaim);
        //console.log('toClaim:', toClaim);
        I(ab.letToken).transfer(msg.sender, toClaim);
        return toClaim;
    }

    function claimAirdrop() external notContract {
        _claimAirdrop(msg.sender);
    }

    function claimAirdropFor(address[] calldata a) public notContract {
        for (uint i; i < a.length; i++) {
            _claimAirdrop(a[i]);
        }
    }

    function _claimAirdrop(address a) private {
        require(airdrops[a].amount > 0 && I(ab.foundingEvent).genesisBlock() != 0 && block.number > airdrops[a].lastClaim);
        (uint toClaim, bool included) = airdropAvailable(a);
        if (!included) {
            airdrops[a].emissionIncluded = true;
            totalAirdropEmissions += 1;
        }
        //console.log('block.number:', block.number);

        airdrops[a].lastClaim = uint32(block.number);
        airdrops[a].amount -= uint80(toClaim);
        if (airdrops[a].amount == 0) {
            totalAirdropEmissions -= 1;
            delete airdrops[a];
        }
        //console.log('toClaim:', toClaim);
        I(ab.letToken).transfer(a, toClaim);
    }

    function airdropAvailable(address a) public view returns (uint, bool) {
        uint airdrop = airdrops[a].amount;
        uint available;
        bool included = airdrops[a].emissionIncluded;
        uint freeAmount = airdrop - airdrops[a].reserved;
        uint treasuryBalance = I(ab.letToken).balanceOf(address(this));
        uint limit = freeAmount > treasuryBalance ? treasuryBalance : freeAmount;
        if (airdrop > 0) {
            if (!included) {
                available = 1e18 < airdrop ? 1e18 : airdrop;
            } else {
                uint rate = getRate() / totalAirdropEmissions;
                rate = rate > 2e13 ? 2e13 : rate;
                //console.log('rate:', rate);
                available = (block.number - airdrops[a].lastClaim) * rate;
            }
        }
        available = available > limit ? limit : available;
        return (available, included);
    }

    function claimPosterRewards() external notContract {
        uint toClaim = _claimPosterRewards(msg.sender);
        I(ab.letToken).transfer(msg.sender, toClaim);
        //_resolveTransfer(msg.sender, toClaim);
    }

    function claimPosterRewardsFor(address[] calldata a) public notContract {
        uint toClaim;
        for (uint i; i < a.length; i++) {
            toClaim = _claimPosterRewards(a[i]);
            I(ab.letToken).transfer(a[i], toClaim);
            //_resolveTransfer(a[i], toClaim);
        }
    }

    function _claimPosterRewards(address a) private returns (uint toClaim) {
        require(posters[a].amount > 0 && block.number > posters[a].lastClaim);
        toClaim = posterRewardsAvailable(a);
        posters[a].lastClaim = uint32(block.number);
        posters[a].amount -= uint80(toClaim);
        uint treasuryBalance = I(ab.letToken).balanceOf(address(this));
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

    function posterRewardsAvailable(address a) public view returns (uint) {
        uint posterAmount = posters[a].amount;
        if (posterAmount > 0) {
            uint reserved = posters[a].reserved;
            uint rate = (((getRate() * posterAmount) / totalPosterRewards) * posterRate) / 1000;
            uint amount = (block.number - posters[a].lastClaim) * rate;
            uint treasuryBalance = I(ab.letToken).balanceOf(address(this));
            uint limit = posterAmount - reserved > treasuryBalance ? treasuryBalance : posterAmount - reserved;
            //console.log('reserved:', reserved);
            //console.log('treasuryBalance:', treasuryBalance);
            amount = amount > limit ? limit : amount;
            return amount;
        }
        return 0;
    }

    function claimFounderRewards() external notContract {
        _claimFounderRewards(msg.sender);
    }

    function claimFounderRewardsFor(address[] calldata a) public notContract {
        for (uint i; i < a.length; i++) {
            _claimFounderRewards(a[i]);
        }
    }

    function _claimFounderRewards(address a) private {
        uint genesis = I(ab.foundingEvent).genesisBlock();
        if (!founders[a].registered && genesis != 0) {
            uint deposit = I(ab.foundingEvent).deposits(a);
            require(deposit > 0);
            founders[a].amount = uint80(deposit);
            founders[a].lastClaim = uint32(genesis); //redundant
            founders[a].registered = true;
            if (totalFounderRewards == 0) {
                totalFounderRewards = I(ab.foundingEvent).sold();
            }
        }
        uint tfr = totalFounderRewards;
        require(founders[a].amount > 0);
        require(block.number > founders[a].lastClaim);
        uint toClaim = founderRewardsAvailable(a);
        founders[a].lastClaim = uint32(block.number);
        founders[a].amount -= uint80(toClaim);
        totalFounderRewards = tfr >= toClaim ? tfr - toClaim : 0;
        I(ab.letToken).transfer(a, toClaim);
    }

    function founderRewardsAvailable(address a) public view returns (uint) {
        uint founderAmount = founders[a].amount;
        if (founderAmount > 0) {
            uint lastClaim = founders[a].lastClaim;
            lastClaim = lastClaim > 0 ? lastClaim : I(ab.foundingEvent).genesisBlock();
            uint reserved = founders[a].reserved;
            uint rate = (getRate() * 5 * founderAmount) / totalFounderRewards;
            uint amount = (block.number - founders[a].lastClaim) * rate;
            uint treasuryBalance = I(ab.letToken).balanceOf(address(this));
            uint limit = treasuryBalance > founderAmount - reserved ? founderAmount - reserved : treasuryBalance;
            amount = amount > limit ? limit : amount;
            return amount;
        }
        return 0;
    }

    // still vulnerable for sendGasInstead()
    // flash loanable, hot fix would be: disable claiming anything by addresses with bytecode size above 0
    function getRate() public view returns (uint rate) {
        address stableCoin = ab.stableCoin;
        //console.log('\x1b[33mSTABLECOIN:', stableCoin);
        uint time = block.timestamp - 1609459200;
        //console.log('baseRate:', baseRate);
        //console.log('time:', time);
        uint price = _calculateLetAmountInToken(stableCoin, 1e18);
        //console.log('sqrt(price):', sqrt(price));
        //console.log('sqrt(price):', sqrt(price));
        rate = price > 1e18 ? baseRate / sqrt(price) / time : baseRate / sqrt(1e18) / time;
        //console.log('rate:', rate);
    }

    // uniswapv2 library:
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _calculateLetAmountInToken(address token, uint amount) internal view returns (uint) {
        //console.log('amount:', amount);
        address factory = ab.factory;
        //console.log('\x1b[33mFACTORY:', factory);
        address letToken = ab.letToken;
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
}
