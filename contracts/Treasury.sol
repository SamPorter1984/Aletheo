pragma solidity >=0.7.0;

import "./IERC20.sol";
// needs support for stable coin based grants
contract Treasury {
	address private _token;
	address private _governance;
	address private _jobMarket;
	address private _staking;
	address private _oracleMain;
	uint56 private _emission; // has to be very slow, like really slow, so that elected devs and officials will have incentive to support the project long-term
	uint8 private _governanceSet;
	bool private _init;

	struct Beneficiary {uint88 amount; uint88 lastClaim; uint88 startBlock; bytes nameType;} // name is for transparency, type is like dev or mod, or bug bounty
	mapping (address => Beneficiary) public bens;

	function init() public {require(_init == false); _init=true; _governance = msg.sender; _emission = 1e15;}

	function addBeneficiary(address a, uint amount, uint lastClaim, uint startBlock, bytes memory nameType) external {
		require(amount<=30e21 && msg.sender == _governance);
		bens[a].amount = uint88(amount);
		bens[a].lastClaim = uint88(block.number);
		bens[a].startBlock = uint88(startBlock);
		bens[a].nameType = nameType;
	}

	function getBeneficiaryRewards() external {
		uint lastClaim = bens[msg.sender].lastClaim;
		uint amount = bens[msg.sender].amount;
		uint toClaim = (block.number - lastClaim)*_emission;
		require(amount > 0 && amount >= toClaim);
		bens[msg.sender].lastClaim = uint88(block.number);
		bens[acc].amount = uint88(amount - toClaim);
		IERC20(_token).transfer(msg.sender, toClaim);
	}

	function getRewards(address acc,uint amount) external returns(bool res){ // for posters, providers and oracles
		require(msg.sender == _jobMarket && msg.sender == _staking && msg.sender == _oracleMain);//hardcoded addresses
		IERC20(_token).transfer(acc, amount); return true;
	}
	// if a majority votes for a beneficiary, then it probably won't be easy to get majority vote to remove same beneficiary. unless there is something really strange going on
	function removeBeneficiary(address a) public {require(msg.sender == _governance); delete bens[a];}
	function setGovernance(address a) public {require(_governanceSet < 3);_governanceSet += 1;_governance = a;}
	function setContracts(address j, address st, address om) public {require(msg.sender == _governance); _jobMarket = j; _staking = st; _oracleMain = om;}
}
