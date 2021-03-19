pragma solidity >=0.7.0 <=0.9.0;

// Author: SamPorter1984
// I am building it for any token, but I guess people will mostly use highest liquidity tokens even for small transfers.
// I didn't test it yet, it's just a draft
// This bridge is mainly needed to relay logic through callAcross(), all other functionality can be taken by chainBridge, if they will move their asses. 
// Then again, a trust minimized bridge, not chainbridge is actually required.

// oracles will probably create standard erc-20 with a prefix "c" lowercase, as a reference to classic i guess.
// minimum store writes, so it does not track token balances for both bridges, so it will work only for tokens which were created on ETH,
// i am skeptical that anybody who wants to create anything interesting will start on ETC instead of ETH, so it's probably a win-win decision.
// An equivalent of this bridge also could used for matic, even if matic and trust minimized do not fit in one sentence its still important.

import "./IERC20.sol";

contract ETHtoETCbridge {
	event Cross(address indexed ccnt,address indexed tkn,uint mnt);
	event CrossTo(address indexed ccnt,address indexed tkn,uint mnt,address indexed t);
	event CallAcross(address indexed ccnt,address indexed t,bytes dt);
	event BridgeRequested(address indexed tkn);

	mapping(address => address) public bridges;
	mapping(address => uint) private _ethDeposits;
	mapping(address => mapping(address => uint)) private _deposits;
	uint public ethBalance;
	uint public etcBalance;
	uint public callAcrossCost;
	uint public baseCost;
	uint public percentage;
	bool private _l;
	address payable private _aggregator;
	address private _governance;
	constructor() {
		percentage = 10000;
		baseCost = 1e16;
		callAcrossCost = 1e15;
		_governance = msg.sender; // and then probably a governance of some sort if not Nameless Protocol governance
	}

	modifier onlyAggregator(){require(msg.sender==_aggregator);_;}
	modifier onlyGovernance(){require(msg.sender ==_governance);_;}

	function cross(address tkn, uint mnt, address t)payable public{
		uint cost = baseCost*percentage/10000;
		require(msg.value>cost);
		if(tkn==address(0)){uint msgvalue = msg.value-cost;_cross(msg.sender,address(0),msgvalue,t);}
		else {require(bridges[tkn] != address(0) && IERC20(tkn).balanceOf(msg.sender) >= mnt && mnt>0);IERC20(tkn).transferFrom(msg.sender,address(this),mnt);_cross(msg.sender,tkn,mnt,t);}
	}

	function _cross(address sndr,address tkn, uint mnt, address t) internal {if (t == address(0)) {mnt-=baseCost;emit Cross(sndr,tkn,mnt);} else {emit CrossTo(sndr,tkn,mnt,t);}}

	function callAcross(address t, bytes memory dt) payable public {
		uint cost = dt.length * callAcrossCost + baseCost*percentage/10000;
		require(msg.value >= cost);
		if (msg.value>cost) {uint rmndr = msg.value - cost; _ethDeposits[msg.sender] += rmndr; ethBalance+=rmndr;}
		emit CallAcross(msg.sender,t,dt);
	}

	function requestBridge(address tkn) public {emit BridgeRequested(tkn);}

	function crossBack(address frm, address tkn, uint mnt, address t, bytes memory dt) public onlyAggregator {
		require(IERC20(tkn).balanceOf(address(this)) >= mnt);
		if(t==address(0)) {IERC20(tkn).transfer(frm,mnt);}
		else {if(dt.length==0){IERC20(tkn).transfer(t,mnt);} else {IERC20(tkn).transfer(t,mnt);t.delegatecall(dt);}}
	}

	function registerBridges(address[] memory tknTH,address[] memory tknTC)public onlyAggregator{
		require(tknTH.length==tknTC.length&&tknTH.length<500);for(uint i=0;i<tknTH.length;i++){bridges[tknTH[i]]=tknTC[i];}
	}

	function updateETCBalance(uint mnt) public onlyAggregator {etcBalance = mnt;}
	function updateCost(uint bs, uint cll, uint prcntg) public onlyGovernance {baseCost=bs;callAcrossCost=cll;percentage=prcntg;}
	function setAggregator(address payable ggrgtr) public onlyGovernance {_aggregator = ggrgtr;}
	function setGovernance(address gvrnnc) public onlyGovernance {_governance = gvrnnc;}
	function getBridge(address tkn) public view returns(address tknTC){return bridges[tkn];}
	function getRewards() public onlyAggregator {uint rewards = address(this).balance - ethBalance;_aggregator.transfer(rewards);}

/*	function fund(address tkn,uint mnt) payable public {// funders will gain interest from cross volume in that token. this is useless for everything except native eth etc and their wrappings
		if (tkn==address(0)) {require(msg.value > 0);_ethDeposits[msg.sender] += msg.value; ethBalance+=msg.value;}
		else {require(IERC20(tkn).balanceOf(msg.sender) >= mnt);IERC20(tkn).transferFrom(msg.sender,address(this),mnt);_deposits[msg.sender][tkn] += mnt;}
	}

	function withdraw(address tkn,uint mnt) public {require(_deposits[msg.sender][tkn]>=mnt&&_l==false);_l=true;_deposits[msg.sender][tkn]-=mnt;IERC20(tkn).transfer(msg.sender,mnt);_l=false;} // and can withdraw
*/	
}
