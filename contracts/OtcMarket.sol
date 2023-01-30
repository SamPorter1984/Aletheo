pragma solidity ^0.8.6;

// author: SamPorter1984
// at first it was supposed to provide ability for holders of otherwise locked shares to be tradeable
// now it's a limit order exchange which supports every token
// with graphql it's possible to make it into a fully decentralized limit order exchange and make it cheap
enum LockedShare {
    STAKE,
    FOUNDER,
    POSTER,
    AIRDROP
}

interface I {
    function getPair(address t, address t1) external view returns (address pair);

    function createPair(address t, address t1) external returns (address pair);

    function transfer(address to, uint value) external returns (bool);

    function transferFrom(address from, address to, uint amount) external returns (bool);

    function balanceOf(address) external view returns (uint);

    function approve(address spender, uint256 value) external returns (bool);

    function reserveForOTC(address a, uint amount, LockedShare t) external;

    function withdrawFromOTC(address a, uint amount, LockedShare t) external;

    function otcReassignment(address from, address to, uint amount, LockedShare t) external;
}

contract OTCMarket {
    //selling
    mapping(address => mapping(uint96 => mapping(address => uint96))) asks;
    mapping(LockedShare => mapping(uint96 => mapping(address => uint96))) lockedShareAsks;
    //buying
    mapping(address => mapping(uint96 => mapping(address => uint96))) bids;
    mapping(LockedShare => mapping(uint96 => mapping(address => uint96))) lockedShareBids;

    event EditAsk(address indexed token, uint price, address indexed asker, uint amount);
    event EditBid(address indexed token, uint price, address indexed bidder, uint amount);
    event EditLockedShareAsk(LockedShare lockedShare, uint price, address indexed asker, uint amount);
    event EditLockedShareBid(LockedShare lockedShare, uint price, address indexed bidder, uint amount);
    //enum LockedShare {
    //    STAKE,
    //    FOUNDER,
    //    POSTER,
    //    AIRDROP
    //}

    address private _deployer;
    address private _letToken;
    address private _treasury;
    address private _staking;
    address public BUSD;
    bool public ini;

    function init() external {
        require(msg.sender == 0xc22eFB5258648D016EC7Db1cF75411f6B3421AEc);
        _deployer = 0xB23b6201D1799b0E8e209a402daaEFaC78c356Dc;
        _letToken = 0x98AAF20cdFaaEf9A4a9dE26a4be52dF4E699fc89;
        _treasury = 0x793bb3681F86791D65786EfB3CE7fcCf25370454;
        BUSD = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59;
    }

    function editLockedShareAsk(LockedShare lockedShare, uint96 price, uint96 amount) public {
        uint prevAmount = lockedShareAsks[lockedShare][price][msg.sender];
        _editLockedShareAsk(lockedShare, price, msg.sender, amount);
        address dest = _treasury;
        if (lockedShare == LockedShare.STAKE) {
            dest = _staking;
        }
        if (prevAmount > amount) {
            I(dest).withdrawFromOTC(msg.sender, prevAmount - amount, lockedShare);
        } else {
            I(dest).reserveForOTC(msg.sender, amount - prevAmount, lockedShare);
        }
    }

    function _editLockedShareAsk(LockedShare lockedShare, uint96 price, address asker, uint96 amount) private {
        lockedShareAsks[lockedShare][price][asker] = amount;
        emit EditLockedShareAsk(lockedShare, price, asker, amount);
    }

    function editLockedShareBid(LockedShare lockedShare, uint96 price, address asker, uint96 amount) public {
        uint prevAmount = lockedShareBids[lockedShare][price][msg.sender];
        _editLockedShareBid(lockedShare, price, msg.sender, amount);
        uint stableCoinInWei = 1e18;
        uint total = (prevAmount * price) / stableCoinInWei;
        uint newTotal = (amount * price) / stableCoinInWei;
        if (total > newTotal) {
            I(BUSD).transfer(msg.sender, total - newTotal);
        } else {
            I(BUSD).transferFrom(msg.sender, address(this), newTotal - total);
        }
    }

    function _editLockedShareBid(LockedShare lockedShare, uint96 price, address bidder, uint96 amount) private {
        lockedShareBids[lockedShare][price][bidder] = amount;
        emit EditLockedShareBid(lockedShare, price, bidder, amount);
    }

    function buyLockedShareWithBUSD(
        LockedShare[] memory lockedShares,
        uint96[] memory prices,
        address[] memory askers,
        uint96[] memory amounts
    ) public returns (uint cost) {
        for (uint n = 0; n < lockedShares.length; n++) {
            LockedShare lockedShare = lockedShares[n];
            uint96 price = prices[n];
            address asker = askers[n];
            uint96 amount = amounts[n];
            uint96 amountLeft = lockedShareAsks[lockedShare][price][asker] - amount;
            _editLockedShareAsk(lockedShare, price, asker, amountLeft);
            cost = (amount * price) / 1e18;
            I(BUSD).transferFrom(msg.sender, asker, cost);
            address dest = _treasury;
            if (lockedShare == LockedShare.STAKE) {
                dest = _staking;
            }
            I(dest).otcReassignment(asker, msg.sender, amount, lockedShare);
        }
    }

    function sellLockedShareToBUSD(
        LockedShare[] memory lockedShares,
        uint96[] memory prices,
        address[] memory bidders,
        uint96[] memory amounts
    ) public returns (uint cost) {
        for (uint n = 0; n < lockedShares.length; n++) {
            LockedShare lockedShare = lockedShares[n];
            uint96 price = prices[n];
            address bidder = bidders[n];
            uint96 amount = amounts[n];
            uint96 amountLeft = lockedShareBids[lockedShare][price][bidder] - amount;
            _editLockedShareBid(lockedShare, price, bidder, amountLeft);
            cost += amount * price;
            address dest = _treasury;
            if (lockedShare == LockedShare.STAKE) {
                dest = _staking;
            }
            I(dest).otcReassignment(msg.sender, bidder, amount, lockedShare);
        }
        I(BUSD).transfer(msg.sender, cost);
    }

    function editAsk(address token, uint96 price, uint96 amount) public {
        uint prevAmount = asks[token][price][msg.sender];
        _editAsk(token, price, msg.sender, amount);
        if (prevAmount > amount) {
            I(token).transfer(msg.sender, prevAmount - amount);
        } else {
            I(token).transferFrom(msg.sender, address(this), amount - prevAmount);
        }
    }

    function _editAsk(address token, uint96 price, address asker, uint96 amount) private {
        asks[token][price][asker] = amount;
        emit EditAsk(token, price, asker, amount);
    }

    function editBid(address token, uint96 price, uint96 amount) public {
        uint prevAmount = bids[token][price][msg.sender];
        _editBid(token, price, msg.sender, amount);
        uint stableCoinInWei = 1e18;
        uint total = (prevAmount * price) / stableCoinInWei;
        uint newTotal = (amount * price) / stableCoinInWei;
        if (total > newTotal) {
            I(BUSD).transfer(msg.sender, total - newTotal);
        } else {
            I(BUSD).transferFrom(msg.sender, address(this), newTotal - total);
        }
        emit EditBid(token, price, msg.sender, amount);
    }

    function _editBid(address token, uint96 price, address bidder, uint96 amount) private {
        bids[token][price][bidder] = amount;
        emit EditBid(token, price, bidder, amount);
    }

    function buyWithBUSD(
        address[] memory tokens,
        uint96[] memory prices,
        address[] memory askers,
        uint96[] memory amounts
    ) public returns (uint cost) {
        for (uint n = 0; n < tokens.length; n++) {
            address token = tokens[n];
            uint96 price = prices[n];
            address asker = askers[n];
            uint96 amount = amounts[n];
            uint96 amountLeft = asks[token][price][asker] - amount;
            _editAsk(token, price, asker, amountLeft);
            cost = (amount * price) / 1e18;
            I(BUSD).transferFrom(msg.sender, asker, cost);
            I(token).transfer(msg.sender, amount);
        }
    }

    function sellToBUSD(
        address[] memory tokens,
        uint96[] memory prices,
        address[] memory bidders,
        uint96[] memory amounts
    ) public returns (uint cost) {
        for (uint n = 0; n < tokens.length; n++) {
            address token = tokens[n];
            uint96 price = prices[n];
            address bidder = bidders[n];
            uint96 amount = amounts[n];
            uint96 amountLeft = asks[token][price][bidder] - amount;
            _editBid(token, price, bidder, amountLeft);
            cost += amount * price;
            I(token).transferFrom(msg.sender, bidder, amount);
        }
        I(BUSD).transfer(msg.sender, cost);
    }
}
