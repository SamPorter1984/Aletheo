pragma solidity >=0.7.0 <=0.9.0;

// Author: SamPorter1984
// I am building it for any token, but I guess people will mostly use highest liquidity tokens even for small transfers.
// I didn't test it yet, it's just a draft
// This bridge is mainly needed to relay logic through callAcross(), all other functionality can be taken by chainBridge, if they will move their asses. 
// Then again, a trust minimized bridge, not chainbridge is actually required.

// oracles will probably create standard erc-20 with a prefix "c" lowercase, as a reference to classic i guess.
// minimum store writes, so it does not track token balances for both bridges, so it will work only for tokens which were created on ETH,
// i am skeptical that anybody who wants to create anything interesting will start on ETC instead of ETH, so it's probably a win-win decision.
// However if such a situation, that genuinely good high liquidity will be created on ETC, then we can make this bridge upgradeable
// An equivalent of this bridge also could used for matic, even if matic and trust minimized do not fit in one sentence its still important.
// PS. I seriously believe that the code is the most auditable when it fits in one screen. I hate infinite scrolling :(

// It will be like stated in schizopaper, but better, since both ETH and ETC are very reliable sources, then accuracy of all Chainlink nodes will always
// approach 100%. Therefore the punishment for lies in this particular case can be very-very significant. So it's possible to adjust the system
// in such a way, when game theory will deem attempts of lies completely not worth it, regardless of transaction value.
import "./IERC20.sol";

contract ETHtoETCbridge { 
	event Cross(address indexed ccnt,address indexed tkn,uint mnt);
	event CrossTo(address indexed ccnt,address indexed tkn,uint mnt,address indexed t);
	event CallAcross(address indexed ccnt,address indexed t,bytes dt);
	event BridgeRequested(address indexed tkn);

	mapping(address => address) public bridges;
	mapping(address => uint) private _ethDeposits;
	uint public callAcrossCost;
	uint public baseCost;
	bool private _l;
	uint public ethBalance;
	address payable private _aggregator;
	address private _governance;
	constructor() {baseCost = 1e16;callAcrossCost = 1e15;_governance = msg.sender;} // and then probably a governance of some sort if not Nameless Protocol governance

	modifier onlyAggregator(){require(msg.sender==_aggregator);_;}
	modifier onlyGovernance(){require(msg.sender ==_governance);_;}

	function cross(address tkn, uint mnt, address t)payable public{
		uint cost = baseCost;
		uint deposit = msg.value +_ethDeposits[msg.sender];
		require(deposit>=cost);
		deposit -= cost;
		if(tkn==address(0)){require(deposit>=mnt);deposit-=mnt;_cross(msg.sender,address(0),mnt,t);}
		else {require(bridges[tkn] != address(0) && IERC20(tkn).balanceOf(msg.sender) >= mnt && mnt>0);IERC20(tkn).transferFrom(msg.sender,address(this),mnt);_cross(msg.sender,tkn,mnt,t);}
		_ethDeposits[msg.sender] = deposit;
	}

	function callAcross(address t, bytes memory dt) payable public {
		uint cost = dt.length * callAcrossCost + baseCost;
		uint deposit = msg.value +_ethDeposits[msg.sender];
		require(deposit>=cost);
		_ethDeposits[msg.sender] = deposit;
		emit CallAcross(msg.sender,t,dt);
	}

	function crossBack(address frm, address tkn, uint mnt, address t, bytes memory dt) public onlyAggregator {
		require(IERC20(tkn).balanceOf(address(this)) >= mnt);
		if(t==address(0)) {IERC20(tkn).transfer(frm,mnt);}
		else {if(dt.length==0){IERC20(tkn).transfer(t,mnt);} else {IERC20(tkn).transfer(t,mnt);t.call(dt);}}
	}

	function registerBridges(address[] memory tknTH,address[] memory tknTC)public onlyAggregator{
		require(tknTH.length==tknTC.length&&tknTH.length<500);for(uint i=0;i<tknTH.length;i++){bridges[tknTH[i]]=tknTC[i];}
	}

	function withdraw(uint mnt) public{
		require(_ethDeposits[msg.sender]>=mnt&&_l==false);_l=true;uint ethB=ethBalance;if(ethB>=mnt){ethBalance=ethB-mnt;}else{mnt=ethB;ethBalance=0;}msg.sender.transfer(mnt);_l=false;
	}

	function depositEth() public payable{_ethDeposits[msg.sender]+=msg.value;ethBalance+=amount;}
	function _cross(address sndr,address tkn, uint mnt, address t) internal {if (t == address(0)) {emit Cross(sndr,tkn,mnt);} else {emit CrossTo(sndr,tkn,mnt,t);}}
	function requestBridge(address tkn) public {emit BridgeRequested(tkn);}
	function updateCost(uint bs, uint cll) public onlyGovernance {baseCost=bs;callAcrossCost=cll;}
	function setAggregator(address payable ggrgtr) public onlyGovernance {_aggregator = ggrgtr;}
	function setGovernance(address gvrnnc) public onlyGovernance {_governance = gvrnnc;}
	function getBridge(address tkn) public view returns(address tknTC){return bridges[tkn];}
	function getRewards() public onlyAggregator {uint rewards = address(this).balance - ethBalance;_aggregator.transfer(rewards);}
}
