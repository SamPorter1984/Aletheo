// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface I {
    function transfer(address to, uint value) external returns (bool);

    function transferFrom(address from, address to, uint amount) external returns (bool);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function approve(address spender, uint256 value) external returns (bool);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract CampaignMarket {
    mapping(uint64 => Campaign) public campaigns;
    mapping(uint64 => PreciseCampaign) public preciseCampaigns;

    event CampaignCreated(Campaign campaign, uint campaignId);
    event CampaignEdited(Campaign campaign, uint campaignId);
    event CampaignFunded(Campaign campaign, uint campaignId, address indexed funder);
    event PreciseCampaignCreated(PreciseCampaign campaign, uint campaignId);
    event PreciseCampaignEdited(PreciseCampaign campaign, uint campaignId);
    event PreciseCampaignFunded(PreciseCampaign campaign, uint campaignId, address indexed funder);

    address public BUSD;
    address public factory;
    address public stakingContract;
    address private _governance;
    address private _aggregator;
    address private _router;
    uint64 public lastCampaignId;
    uint64 public stakersShare;

    struct PosterReward {
        uint128 amount;
        uint128 unapprovedAmount;
    }

    mapping(address => mapping(address => PosterReward)) public posterRewards;

    struct Campaign {
        // slot 1
        address paymentToken;
        uint48 minPaymentTokenHeldPX2; // gas savings: PX2 means value**2
        uint48 minPaymentTokenStakedPX2;
        // slot 2
        address creator;
        uint48 minLetCommitmentStakePX2;
        uint16 expirationDatePX2;
        // gas savings, looks ugly, but works for the user
        uint16 nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable; // gas savings
        // slot 3
        uint72 fundX10e17; // gas savings: X10e17 means value * 10e17
        //uint modsPay;
        CampaignOracleDetails details;
    }

    struct CampaignOracleDetails {
        uint48 payPerPostPX2;
        uint16 startDatePX2;
        uint16 startMinuteOfDay; //UTC
        uint16 endMinuteOfDay; //UTC
        uint8 keyStringPerWordsPX2;
        uint8 minPostLengthPX2;
        uint8 minShillPowerPX2;
        uint8 postRateInSecondsPX2;
        uint16 twitter_discord_telegram_reddit_4chan_2chhk;
        // top 32 from https://en.wikipedia.org/wiki/Languages_used_on_the_Internet
        uint32 en_ru_es_de_fr_ja_tr_fa_zh_it_vi_pt_nl_pl_ar_ko_id_uk_cs_th_he_sv_el_ro_da_hu_fi_sr_sk_bg_nb_hr;
        address customMetricAddress;
        bytes4 customMetricFunctionSignature; //oracles should only allow view or pure function calls, and obviously abi must be public
        uint8 customMetricReturnArgumentIndex;
        uint88 customMetricWeight;
        uint24 maxPostersPX2;
        // other slots
        // gas savings: in these uints strings are encoded. these strings are intended for oracles/front-end
        // and not are not supposed to be readable on chain,
        // however it's a possibility that an encode-decode library will be available in solidity.
        // 1 uint holds up to 37 symbols of shortened ascii, in addition uint is cheaper and more consistent than bytes and especially string
        // native solidity string has shown itself very inconsistent and extremely highly dependent on how big are recorded values.
        uint rulesLink;
        uint[] targetUrls;
        // bytes is still better if the string is long enough
        bytes keystrings;
        bytes mandatoryKeystring;
        bytes optionalMessage;
    }

    //supposed to be for testing
    struct PreciseCampaign {
        address paymentToken;
        uint minPaymentTokenHeld;
        uint minPaymentTokenStaked;
        address creator;
        uint minLetCommitmentStake;
        uint expirationDate;
        uint nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable; // gas savings
        uint fund;
        PreciseCampaignOracleDetails details;
    }

    struct PreciseCampaignOracleDetails {
        uint payPerPost;
        uint startDate;
        uint startMinuteOfDay; //UTC
        uint endMinuteOfDay; //UTC
        uint keyStringPerWords;
        uint minPostLength;
        uint minShillPower;
        uint postRateInSeconds;
        uint twitter_discord_telegram_reddit_4chan_2chhk;
        uint en_ru_es_de_fr_ja_tr_fa_zh_it_vi_pt_nl_pl_ar_ko_id_uk_cs_th_he_sv_el_ro_da_hu_fi_sr_sk_bg_nb_hr;
        address customMetricAddress;
        bytes customMetricFunctionSignature;
        uint customMetricReturnArgumentIndex;
        uint customMetricWeight;
        uint maxPosters;
        uint rulesLink;
        uint[] targetUrls;
        bytes keystrings;
        bytes mandatoryKeystring;
        bytes optionalMessage;
    }

    struct PosterRewardsForToken {
        address poster;
        uint96 amount;
    }

    struct TokenRewards {
        PosterRewardsForToken[] rewards;
    }

    function init() public {}

    function claimTokenRewards(address[] memory tokens) public {
        for (uint i; i < tokens.length; i++) {
            uint toClaim = posterRewards[tokens[i]][msg.sender].amount - posterRewards[tokens[i]][msg.sender].unapprovedAmount;
            posterRewards[tokens[i]][msg.sender].amount -= uint128(toClaim);
            I(tokens[i]).transfer(msg.sender, toClaim);
        }
    }

    function addRewardsForTokens(address[] memory tokens, TokenRewards[] memory tokenRewards) external {
        require(msg.sender == _aggregator);
        require(tokens.length == tokenRewards.length, 'array mismatch');
        for (uint i = 0; i < tokens.length; i++) {
            for (uint n = 0; n < tokenRewards[i].rewards.length; n++) {
                posterRewards[tokens[i]][tokenRewards[i].rewards[n].poster].unapprovedAmount += uint128(tokenRewards[i].rewards[n].amount);
            }
        }
    }

    function editUnapprovedRewardsForTokens(address[] memory tokens, TokenRewards[] memory tokenRewards) external {
        require(msg.sender == _governance);
        require(tokens.length == tokenRewards.length, 'array mismatch');
        for (uint i = 0; i < tokens.length; i++) {
            for (uint n = 0; n < tokenRewards[i].rewards.length; n++) {
                posterRewards[tokens[i]][tokenRewards[i].rewards[n].poster].unapprovedAmount = uint128(tokenRewards[i].rewards[n].amount);
            }
        }
    }

    function approveRewardsForTokens(address[] memory tokens, TokenRewards[] memory tokenRewards) external {
        require(msg.sender == _governance);
        require(tokens.length == tokenRewards.length, 'array mismatch');
        for (uint i = 0; i < tokens.length; i++) {
            for (uint n = 0; n < tokenRewards[i].rewards.length; n++) {
                uint128 amount = posterRewards[tokens[i]][tokenRewards[i].rewards[n].poster].unapprovedAmount;
                posterRewards[tokens[i]][tokenRewards[i].rewards[n].poster].amount = amount;
                posterRewards[tokens[i]][tokenRewards[i].rewards[n].poster].unapprovedAmount = 0;
            }
        }
    }

    function createCampaign(Campaign memory campaign) public {
        uint64 campaignId = ++lastCampaignId;
        uint amountInUsd = _calculatePrice(campaign.fundX10e17 * 10e17, campaign.paymentToken);
        require(amountInUsd > 1000e18);
        uint72 stakersPay = (campaign.fundX10e17 / 1000) * stakersShare;
        campaign.fundX10e17 -= stakersPay;
        campaigns[campaignId] = campaign;
        I(campaign.paymentToken).transferFrom(msg.sender, stakingContract, stakersPay * 10e17);
        I(campaign.paymentToken).transferFrom(msg.sender, address(this), campaign.fundX10e17 * 10e17);
        emit CampaignCreated(campaign, campaignId);
    }

    function editCampaign(uint64 id, Campaign memory campaign) public {
        bool[] memory bools = getBooleansFromUint(
            campaigns[id]
                .nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable,
            2 ** 16 - 1
        );
        require(msg.sender > campaigns[id].creator && !bools[0]);
        uint amountInUsd = _calculatePrice(campaigns[id].fundX10e17 * 10e17, campaigns[id].paymentToken);
        require(amountInUsd > 1000e18); // shouldn't be able to surprise posters when funds almost ran out
        require(campaign.fundX10e17 >= campaigns[id].fundX10e17); // can't surprise posters with suddenly reduced funding
        require(campaign.paymentToken == campaigns[id].paymentToken);
        uint72 stakersPay = (campaign.fundX10e17 / 1000) * stakersShare;
        campaign.fundX10e17 -= stakersPay;
        uint fundingDiff = (campaign.fundX10e17 - campaigns[id].fundX10e17) * 10e17;
        campaigns[id] = campaign;
        I(campaign.paymentToken).transferFrom(msg.sender, stakingContract, stakersPay * 10e17);
        I(campaign.paymentToken).transferFrom(msg.sender, address(this), fundingDiff);
        emit CampaignEdited(campaign, id);
    }

    function swapCampaignFundToFromStableCoin(uint64 id) public {
        bool[] memory bools = getBooleansFromUint(
            campaigns[id]
                .nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable,
            2 ** 16 - 1
        );
        require(msg.sender > campaigns[id].creator && !bools[0]);
        address[] memory ar = new address[](2);
        if (bools[8]) {
            ar[0] = BUSD;
            ar[1] = campaigns[id].paymentToken;
            bools[8] = false;
            campaigns[id]
                .nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable = uint16(
                storeBooleansInUint(bools)
            );
        } else {
            ar[0] = campaigns[id].paymentToken;
            ar[1] = BUSD;
            bools[8] = true;
            campaigns[id]
                .nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable = uint16(
                storeBooleansInUint(bools)
            );
        }
        I(ar[1]).approve(_router, 2 ** 256 - 1);
        // should check if direct pair exists first
        uint[] memory amounts = I(_router).swapExactTokensForTokens(campaigns[id].fundX10e17 * 10e17, 0, ar, address(this), 2 ** 256 - 1);
        campaigns[id].fundX10e17 = uint72(amounts[amounts.length - 1] / 10e17);
    }

    function fundCampaign(uint64 id, uint72 amountX10e17) public {
        // others can fund any, should fund non editable and non expirable
        campaigns[id].fundX10e17 += amountX10e17;
        I(campaigns[id].paymentToken).transferFrom(msg.sender, address(this), amountX10e17 * 10e17);
        emit CampaignFunded(campaigns[id], id, msg.sender);
    }

    function withdrawLeftoverFromExpiredCampaign(uint64 id) public {
        require(block.timestamp >= campaigns[id].expirationDatePX2 ** 2 && msg.sender > campaigns[id].creator);
        I(campaigns[id].paymentToken).transfer(msg.sender, campaigns[id].fundX10e17 * 10e17);
    }

    function _calculatePrice(uint amount, address campaignToken) internal view returns (uint) {
        address pool; //alert need pool address from factory
        (address token0, ) = campaignToken < BUSD ? (campaignToken, BUSD) : (BUSD, campaignToken);
        (uint reserve0, uint reserve1, ) = I(pool).getReserves();
        (uint reserveWBNB, uint reserveBUSD) = campaignToken == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return (amount * reserveBUSD) / reserveWBNB;
    }

    // for lib. up to 256 booleans only
    function storeBooleansInUint(bool[] memory bools) public returns (uint uintstore) {
        if (bools[0]) {
            uintstore += 1;
        }
        for (uint i = 1; i < bools.length; i++) {
            if (bools[i]) {
                uintstore += 2 ** i;
            }
        }
    }

    function getBooleansFromUint(uint uintstore, uint maxValue) public returns (bool[] memory bools) {
        if (uintstore % 2 == 1) {
            bools[0] = true;
        }
        uint half = maxValue / 2;
        uint i = maxValue;
        for (i; i > 0; i--) {
            if (uintstore > half + 1) {
                bools[i] = true;
            }
            uintstore -= half - 1;
            half /= 2;
        }
    }

    function createPreciseCampaign(PreciseCampaign memory campaign) public {
        uint64 campaignId = ++lastCampaignId;
        uint amountInUsd = _calculatePrice(campaign.fund, campaign.paymentToken);
        require(amountInUsd > 1000e18);
        uint stakersPay = (campaign.fund / 1000) * stakersShare;
        campaign.fund -= stakersPay;
        {
            preciseCampaigns[campaignId] = campaign;
            I(campaign.paymentToken).transferFrom(msg.sender, stakingContract, stakersPay);
            I(campaign.paymentToken).transferFrom(msg.sender, address(this), campaign.fund);
            emit PreciseCampaignCreated(campaign, campaignId);
        }
    }

    function editPreciseCampaign(uint64 id, PreciseCampaign memory campaign) public {
        bool[] memory bools = getBooleansFromUint(
            preciseCampaigns[id]
                .nonEditable_NoFiring_onlyManualApproval_shillPowerCounts_letStakeCounts_letDelegatesCount_rewardTokenLockCounts_paymentOnExpire_swappedToStable,
            2 ** 16 - 1
        );
        require(msg.sender > preciseCampaigns[id].creator && !bools[0]);
        uint amountInUsd = _calculatePrice(preciseCampaigns[id].fund, preciseCampaigns[id].paymentToken);
        require(amountInUsd > 1000e18); // shouldn't be able to surprise posters when funds almost ran out
        require(campaign.fund >= preciseCampaigns[id].fund); // not surprising posters with reduced funding
        uint stakersPay = (campaign.fund / 1000) * stakersShare;
        campaign.fund -= stakersPay;
        uint fundingDiff = (campaign.fund - preciseCampaigns[id].fund);
        preciseCampaigns[id] = campaign;
        I(campaign.paymentToken).transferFrom(msg.sender, stakingContract, stakersPay);
        I(campaign.paymentToken).transferFrom(msg.sender, address(this), fundingDiff);
        emit PreciseCampaignEdited(campaign, id);
    }

    function fundPreciseCampaign(uint64 id, uint amount) public {
        // others can fund any, should fund non editable and non expirable
        preciseCampaigns[id].fund += amount;
        I(preciseCampaigns[id].paymentToken).transferFrom(msg.sender, address(this), amount);
        emit PreciseCampaignFunded(preciseCampaigns[id], id, msg.sender);
    }

    function withdrawLeftoverFromExpiredPreciseCampaign(uint64 id) public {
        require(block.timestamp >= preciseCampaigns[id].expirationDate && msg.sender > preciseCampaigns[id].creator);
        I(preciseCampaigns[id].paymentToken).transfer(msg.sender, preciseCampaigns[id].fund);
    }

    function setStakersShare(uint64 _stakersShare) public {
        require(msg.sender == _governance && _stakersShare <= 50);
        stakersShare = _stakersShare;
    }

    function setGovernance(address governance) public {
        require(msg.sender == _governance);
        _governance = governance;
    }

    function setFactory(address _factory) public {
        require(msg.sender == _governance);
        factory = _factory;
    }

    function setStakingContract(address _stakingContract) public {
        require(msg.sender == _governance);
        stakingContract = _stakingContract;
    }
}
