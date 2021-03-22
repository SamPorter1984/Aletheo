pragma solidity >=0.7.0 <=0.9.0;

// Author: SamPorter1984
// I didn't test it yet, it's just a draft
// Commit-reveal scheme disallows oracles to alter transactions, they can only attempt to censor transactions, but they won't do that with verifiable 
// random number roles. 
// Hash has to be generated by the user and has to correspond with keccak256(abi.encodePacked(userAddress,arg1,arg2,arg3,arg4,anyDisposableKey)). 
// Hash has to be posted by announceHash(), after oracles relay it to other chain, and after user confirms it's the hash he posted, he can then call
// cross() or callAcross() with the arguments and disposable key

// oracles will probably create standard erc-20 with a prefix "c" lowercase, as a reference to classic i guess.
// minimum store writes, so it does not track token balances for both bridges, so it will work only for tokens which were created on ETH,
// i am skeptical that anybody who wants to create anything interesting will start on ETC instead of ETH, so it's probably a win-win decision.
// However if such a situation, that genuinely good high liquidity project will be created on ETC, then we can make this bridge upgradeable
// An equivalent of this bridge also could be used for matic, even if matic and trust minimized do not fit in one sentence very well its still important.
// PS. I seriously believe that the code is the most auditable when it fits in one screen. I hate infinite scrolling :(

// It will be like stated in the paper, but better, since both ETH and ETC(with Mess) are very reliable sources, then accuracy of all Chainlink nodes will
// always approach 100%. Therefore the punishment for lies in this particular case can be very-very significant. So it's possible to adjust the system
// in such a way, when game theory will deem attempts of lies completely not worth it, regardless of transaction value.
// At the time of writing, ETH has 50x more hashrate than ETC. All it needs is to decide on what finality is safe. Could wait a day.
import "./IERC20.sol";

contract TrustMinimizedCrossChainBridge { 
	event Cross(address indexed ccnt,address indexed tkn,uint mnt,string key);
	event CrossTo(address indexed ccnt,address indexed tkn,uint mnt,address indexed t,string key);
	event CallAcross(address indexed ccnt,address indexed t,bytes dt,string key);
	event BridgeRequested(address indexed tkn);
	event HashAnnounced(address indexed ccnt,bytes32 indexed hash);
	mapping(address => bytes32) public hashes;
	mapping(address => address) public bridges;
	struct Holder {uint128 deposit; uint128 lock;}
	mapping(address => Holder) private _holders;
	uint public callAcrossCost;
	uint public baseCost;//numbers are for eth mainnet
	uint public ethBalance;
	address payable private _aggregator;
	address private _governance;
	constructor() {baseCost = 1e16;callAcrossCost = 1e15;_governance = msg.sender;} // and then probably a governance of some sort if not Nameless Protocol governance

	modifier onlyAggregator(){require(msg.sender==_aggregator);_;}
	modifier onlyGovernance(){require(msg.sender ==_governance);_;}

	function announceHash(bytes32 hash) payable public {
		uint cost = baseCost;
		uint deposit = msg.value +_holders[msg.sender].deposit;
		require(deposit>=cost);
		deposit -= cost;
		_holders[msg.sender].deposit = uint128(deposit);
		emit HashAnnounced(msg.sender,hash);
	}

	function cross(address tkn, uint mnt, address t, string memory key)payable public{
		uint cost = baseCost;
		uint deposit = msg.value +_holders[msg.sender].deposit;
		require(deposit>=cost);
		deposit -= cost;
		if(tkn==address(0)){require(deposit>=mnt);deposit-=mnt;_cross(msg.sender,address(0),mnt,t,key);}
		else {require(bridges[tkn] != address(0) && IERC20(tkn).balanceOf(msg.sender) >= mnt && mnt>0);IERC20(tkn).transferFrom(msg.sender,address(this),mnt);_cross(msg.sender,tkn,mnt,t,key);}
		_holders[msg.sender].deposit = uint128(deposit);
	}

	function callAcross(address t,bytes memory dt,string memory key) payable public {
		uint cost = dt.length * callAcrossCost + baseCost;
		uint deposit = msg.value +_holders[msg.sender].deposit;
		require(deposit>=cost);
		deposit -= cost;
		_holders[msg.sender].deposit = uint128(deposit);
		emit CallAcross(msg.sender,t,dt,key);
	}

	function crossBack(address frm, address tkn, uint mnt, address t, bytes memory dt,string memory k) public onlyAggregator {
		require(IERC20(tkn).balanceOf(address(this)) >= mnt);
		require(hashes[frm] == keccak256(abi.encodePacked(frm,tkn,mnt,t,dt,k)));
		if(t==address(0)) {IERC20(tkn).transfer(frm,mnt);}
		else {if(dt.length==0){IERC20(tkn).transfer(t,mnt);} else {IERC20(tkn).transfer(t,mnt);t.call(dt);}}
	}

	function registerBridges(address[] memory tknTH,address[] memory tknTC)public onlyAggregator{
		require(tknTH.length==tknTC.length&&tknTH.length<500);for(uint i=0;i<tknTH.length;i++){bridges[tknTH[i]]=tknTC[i];}
	}

	function withdraw(uint mnt) public{
		uint128 l = _holders[msg.sender].lock;
		require(_holders[msg.sender].deposit>=mnt&&block.number>l);
		_holders[msg.sender].lock = l+10;
		uint ethB=ethBalance;
		if(ethB>=mnt){ethBalance=ethB-mnt;}else{mnt=ethB;ethBalance=0;}
		_holders[msg.sender].deposit -= uint128(mnt);
		msg.sender.transfer(mnt);
	}

	function relayHash(address[] memory a,bytes32[] memory hash) public onlyAggregator {require(a.length==hash.length&&a.length<100); for (uint i=0;i<a.length;i++) {hashes[a[i]] = hash[i];}}
	function depositEth() public payable{_holders[msg.sender].deposit+=uint128(msg.value);ethBalance+=msg.value;}
	function _cross(address sndr,address tkn, uint mnt, address t,string memory k) internal {if (t == address(0)) {emit Cross(sndr,tkn,mnt,k);} else {emit CrossTo(sndr,tkn,mnt,t,k);}}
	function requestBridge(address tkn) public {emit BridgeRequested(tkn);}
	function updateCost(uint bs, uint cll) public onlyGovernance {baseCost=bs;callAcrossCost=cll;}
	function setAggregator(address payable ggrgtr) public onlyGovernance {_aggregator = ggrgtr;}
	function setGovernance(address gvrnnc) public onlyGovernance {_governance = gvrnnc;}
	function getBridge(address tkn) public view returns(address tknTC){return bridges[tkn];}
	function getRewards() public onlyAggregator {uint rewards = address(this).balance - ethBalance;_aggregator.transfer(rewards);}
}