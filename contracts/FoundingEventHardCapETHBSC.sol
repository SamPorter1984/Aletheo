pragma solidity ^0.7.6;

interface I{
	function getPair(address t, address t1) external view returns(address pair);
	function createPair(address t, address t1) external returns(address pair);
	function genesis(uint Eth,address pair,uint genesis) external;
	function deposit() external payable;
	function transfer(address to, uint value) external returns(bool);
	function mint(address to) external returns(uint liquidity);
//	function triggerBSCLaunch() external;
}

contract FoundingEvent {
	mapping(address => uint) public deposits;
	address payable private _deployer;
	bool private _lgeOngoing;
	address private _staking;
	bool private _notInit;
	uint private _hardcap;
	uint public genesisBlock;
//	address private _bridge;
//	bool private _emergency;

	constructor() {_deployer = msg.sender;}
	function startLGE(uint hc) external {require(msg.sender == _deployer && hc < 5e21 && hc > 1e20);_lgeOngoing = true; _hardcap = hc;}
//	function _triggerBSCLaunch() internal { address b = _bridge; if(b != address(0)){I(_bridge).triggerBSCLaunch();} }
//	function triggerLaunch() public {require(_lgeOngoing == true && msg.sender == _bridge);_createLiquidity();}
//	function emergency() public {require(msg.sender == _deployer);_emergency = true;}
//	function withdraw() public {uint d = deposits[msg.sender];require(_emergency == true && d > 0); address payable s = msg.sender;(s).transfer(d);}
//	function defineBridge(address b) public {require(msg.sender == _deployer); _bridge = b;}
	function addressBalance() external pure returns(uint){return address(this).balance;}

	function depositEth() external payable {
		require(_lgeOngoing == true);
		uint amount = msg.value;
		uint deployerShare = amount/100; amount -= deployerShare; _deployer.transfer(deployerShare);
		deposits[msg.sender] += amount;
		if (address(this).balance > _hardcap) {/*_triggerBSCLaunch();*/_createLiquidity();}
	}

	function _createLiquidity() internal {
		genesisBlock = block.number;
		address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
		address token = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;//0xdff92dCc99150Df99D54BC3291bD7e5522bB1Edd;// hardcoded token address after erc20 will be deployed
		address staking = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;//;
		address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
		address tknETHLP = I(factory).getPair(token,WETH);
		if (tknETHLP == address(0)) {tknETHLP=I(factory).createPair(token, WETH);}
		uint ETHDeposited = address(this).balance;
		I(WETH).deposit{value: ETHDeposited}();
		I(token).transfer(tknETHLP, 1e24);
		I(WETH).transfer(tknETHLP, ETHDeposited);
		I(tknETHLP).mint(staking);
		I(staking).genesis(ETHDeposited, tknETHLP,block.number);
		delete _staking; delete _lgeOngoing; delete _deployer; delete _hardcap;// delete _bridge;
	}
}
