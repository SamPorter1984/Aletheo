//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface I{function transfer(address to, uint value) external returns(bool);function balanceOf(address) external view returns(uint); function genesisBlock() external view returns(uint);}

contract Treasury {
	address private _governance;
	bool private _init;

	struct Beneficiary {uint88 amount; uint32 lastClaim; uint16 emission;}
	mapping (address => Beneficiary) public beneficiaries;

	function init() public {
		require(_init == false && msg.sender == 0x2D9F853F1a71D0635E64FcC4779269A05BccE2E2);
		_init=true;
		_governance = msg.sender;
		setBeneficiary(0x2D9F853F1a71D0635E64FcC4779269A05BccE2E2,32857142857e12,0,2e3);
		setBeneficiary(0x174F4EbE08a7193833e985d4ef0Ad6ce50F7cBc4,28857142857e12,0,2e3);
		setBeneficiary(0xFA9675E41a9457E8278B2701C504cf4d132Fe2c2,25285714286e12,0,2e3);
	}

	function setBeneficiary(address a, uint amount, uint lastClaim, uint emission) public {
		require(msg.sender == _governance && amount<=4e22 && bens[a].amount == 0 && lastClaim < block.number+1e6 && emission >= 1e2 && emission <=2e3);
		if(lastClaim < block.number) {lastClaim = block.number;}
		uint lc = bens[a].lastClaim;
		if (lc == 0) {bens[a].lastClaim = uint32(lastClaim+129600);} // this 3 weeks delay disallows deployer to be malicious, can be removed after the governance will have control over treasury
		if (bens[a].amount == 0 && lc != 0) {bens[a].lastClaim = uint32(lastClaim);}
		bens[a].amount = uint88(amount);
		bens[a].emission = uint16(emission);
	}

	function getBeneficiaryRewards() external{
		uint genesisBlock = I(0x901628CF11454AFF335770e8a9407CccAb3675BE).genesisBlock();
		require(genesisBlock != 0);
		uint lastClaim = bens[msg.sender].lastClaim; 
		if (lastClaim < genesisBlock) {lastClaim = genesisBlock;} 
		uint rate = 5e11; uint quarter = block.number/1e7;
		if (quarter>1) { for (uint i=1;i<quarter;i++) {rate=rate*3/4;} }
		uint toClaim = (block.number - lastClaim)*bens[msg.sender].emission*rate;
		bens[msg.sender].lastClaim = uint32(block.number);
		bens[msg.sender].amount -= uint88(toClaim);
		I(0x1565616E3994353482Eb032f7583469F5e0bcBEC).transfer(msg.sender, toClaim);
	}

// these checks leave less room for deployer to be malicious
	function getRewards(address a,uint amount) external{ //for posters, providers and oracles
		uint genesisBlock = I(0x901628CF11454AFF335770e8a9407CccAb3675BE).genesisBlock();
		require(genesisBlock != 0&& msg.sender == 0x109533F9e10d4AEEf6d74F1e2D59a9ed11266f27 || msg.sender == 0xEcCD8639eA31FAfe9e9646Fbf31310Ec489ad1C8 || msg.sender == 0xde97e5a2fAe859ac24F70D1f251B82D6A9B77296);
		if (msg.sender == 0xEcCD8639eA31FAfe9e9646Fbf31310Ec489ad1C8) {// if job market(posters)
				uint withd =  999e24 - I(0x1565616E3994353482Eb032f7583469F5e0bcBEC).balanceOf(address(this));// balanceOf(treasury)
				uint allowed = (block.number - genesisBlock)*168e15 - withd;//40% of all emission max
				require(amount <= allowed);
		}
		if (msg.sender == 0xde97e5a2fAe859ac24F70D1f251B82D6A9B77296) {// if oracle registry
				uint withd =  999e24 - I(0x1565616E3994353482Eb032f7583469F5e0bcBEC).balanceOf(address(this));// balanceOf(treasury)
				uint allowed = (block.number - genesisBlock)*42e15 - withd;//10% of all emission max, maybe actually should be less, depends on stuff
				require(amount <= allowed);
		}
		I(0x1565616E3994353482Eb032f7583469F5e0bcBEC).transfer(a, amount);
	}
}
