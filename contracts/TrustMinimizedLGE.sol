pragma solidity >=0.7.0 <=0.8.0;

// Author: Sam Porter

// What CORE team did is something really interesting, with LGE it's now possible 
// to create fairer distribution and fund promising projects without VC vultures at all.
// Non-upgradeable, not owned, liquidity is being created automatically on first transaction after last block of LGE.
// Founders' liquidity is not locked, instead an incentive to keep it is introduced.
// The Event lasts for ~2 months to ensure fair distribution.
// 0,5% of contributed Eth goes to developer for earliest development expenses including audits and bug bounties.
// Blockchain needs no VCs, no authorities.

// Tokens will be staked by default after liquidity will be created, so there is no stake function, and unstaking means losing Founder rewards forever.

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ITreasury.sol";
import "./IWETH.sol";
import "./IERC20.sol";
import "./IGovernance.sol";
import "./IOptimismBridge.sol";
import "./IEtcBridge.sol";

contract FoundingEvent {
	// I believe this is required for the safety of investors and other developers joining the project
	string public AgreementTerms = "I understand that this contract is provided with no warranty of any kind. \n I agree to not hold the contract creator, RAID team members or anyone associated with this event liable for any damage monetary and otherwise I might onccur. \n I understand that any smart contract interaction carries an inherent risk.";
	uint private _totalETHDeposited;
	uint private _totalLGELPtokensMinted;
	address private _tokenETHLP; // create2 and hardcode too?
	uint private _totalTokenAmount;
	bool private _lgeOngoing;
	bool private _lock;
	address private _optimismBridge;
	address private _etcBridge;
///////variables for testing purposes
	address private constant _WETH = 0x2E9d30761DB97706C536A112B9466433032b28e3;// testing
	address private _uniswapFactory = 0x7FDc955b5E2547CC67759eDba3fd5d7027b9Bd66;
	uint private _rewardsGenesis; // = hardcoded block.number
	address private _token; // = hardcoded address
	address private _treasury; // hardcoded
	address private _governance; // hardcoded
	address payable private _deployer; // hardcoded

//////
	constructor() {
		_deployer = msg.sender;
		_token = 0xf8e81D47203A594245E36C48e151709F0C19fBe8; // testing
		_rewardsGenesis = block.number + 5;
		_totalTokenAmount = 1e27;
		_lgeOngoing = true;
	}

	struct Founder {uint ethContributed; uint claimed; uint tokenAmount; uint lockUpTo;address newAddress;}

	mapping(address => Founder) private _founders;
	mapping (address => address) private _linkedAddresses;
	mapping (address => bool) private _takenAddresses;

	event AddressLinked(address indexed address1, address indexed address2);

	modifier onlyFounder() {require(_founders[msg.sender].ethContributed > 0 && _lock != true, "Not a Founder or locked");_lock = true;_;_lock = false;}

	function depositEth(bool iAgreeToPublicStringAgreementTerms) external payable {
		require(_lgeOngoing == true && iAgreeToPublicStringAgreementTerms == true, "LGE has already ended or didn't start, or no agreement provided");
		require(_isContract(msg.sender) == false, "contracts can't be Founders");
		if (_takenAddresses[msg.sender] == true) {
			address linkedAddress = _linkedAddresses[msg.sender]; delete _linkedAddresses[linkedAddress]; delete _linkedAddresses[msg.sender]; delete _takenAddresses[msg.sender];
		}
		uint deployerShare = msg.value / 200;
		uint amount = msg.value - deployerShare;
		_deployer.transfer(deployerShare);
		_founders[msg.sender].ethContributed += amount;
		if (block.number >= _rewardsGenesis) {_createLiquidity();}
	}

	function unstakeLP() public onlyFounder {
		require(_founders[msg.sender].lockUpTo <= block.number && _founders[msg.sender].tokenAmount > 0, "tokens locked or claim rewards");
		_cleanUpLinked(msg.sender);
		_totalTokenAmount -= _founders[msg.sender].tokenAmount;
		IERC20(_tokenETHLP).transfer(address(msg.sender), _calcLpShare(msg.sender));
		delete _founders[msg.sender];
	}

	function claimLGERewards() public onlyFounder { // has to have first Method Id or close to
		uint rewardsGenesis = _rewardsGenesis;
		require(block.number > rewardsGenesis, "too soon");
		uint toClaim;
		uint tokenAmount = _founders[msg.sender].tokenAmount;
		uint claimed = _founders[msg.sender].claimed;
		uint halver = block.number/10000000;uint rewardsRate = 75;if (halver>1) {for (uint i=1;i<halver;i++) {rewardsRate=rewardsRate*5/6;}}
		if(tokenAmount == 0){_founders[msg.sender].tokenAmount=_founders[msg.sender].ethContributed*1e27/_totalETHDeposited;}
		toClaim = (block.number - rewardsGenesis)*rewardsRate*1e18*tokenAmount/_totalTokenAmount;
		if (toClaim > claimed) {toClaim -= claimed; _founders[msg.sender].claimed += toClaim; ITreasury(_treasury).claimFounderRewards(address(msg.sender), toClaim);}
	}

	function migrate(address contr) public onlyFounder {
		require(_founders[msg.sender].tokenAmount > 0, "claim rewards before this");
		require(contr == _treasury || contr == _optimismBridge || contr == _etcBridge,"invalid contract");
		_cleanUpLinked(msg.sender);
		uint lpShare = _calcLpShare(msg.sender);
		if (contr == _treasury) {
			IERC20(_tokenETHLP).transfer(_treasury, lpShare);
			ITreasury(_treasury).fromFoundersContract(msg.sender,lpShare,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);// should tokenAmount be cut in half here?	
		} else if (contr == _optimismBridge) {
			IERC20(_tokenETHLP).transfer(_optimismBridge, lpShare);
			IOptimismBridge(_optimismBridge).fromFoundersContract(msg.sender,lpShare,_founders[msg.sender].claimed,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);
		} else if (contr == _etcBridge) {
			IERC20(_tokenETHLP).transfer(_etcBridge, lpShare);
			IEtcBridge(_etcBridge).fromFoundersContract(msg.sender,lpShare,_founders[msg.sender].claimed,_founders[msg.sender].tokenAmount,_founders[msg.sender].lockUpTo);
		}
		_totalTokenAmount -= _founders[msg.sender].tokenAmount;
		delete _founders[msg.sender];
	}

	function newAddress(address account) public onlyFounder {require(_isContract(account) == false, "can't change to contract");//has to be expensive as alert of something fishy just in case
		for (uint i = 0;i<10;i++) {delete _founders[msg.sender].newAddress;_founders[msg.sender].newAddress = account;} // metamask has to somehow provide more info about a transaction
	}

	function changeAddress() public onlyFounder { // no founder, nobody should trust dapp interface. only blockchain. maybe a function like this should not be provided through dapp at all
		require(IGovernance(_governance).getVoting() == false, "voting is ongoing");
		address account = _founders[msg.sender].newAddress;
		require(account != address(0),"new address wasn't set");
		uint ethContributed = _founders[msg.sender].ethContributed;
		uint claimed = _founders[msg.sender].claimed;
		uint tokenAmount = _founders[msg.sender].tokenAmount;
		uint lockUpTo = _founders[msg.sender].lockUpTo;
		delete _founders[msg.sender];
		_founders[account].ethContributed = ethContributed;
		_founders[account].claimed = claimed;
		_founders[account].tokenAmount = tokenAmount;
		_founders[account].lockUpTo = lockUpTo;
	}

	function lock(bool ok) public onlyFounder{require(ok==true,_founders[msg.sender].tokenAmount>0, "first claim rewards");_founders[msg.sender].lockUpTo = block.number + 6307200;}
	function _isFounder(address account) internal view returns(bool) {if (_founders[account].ethContributed > 0) {return true;} else {return false;}}
	function _isContract(address account) internal view returns(bool) {uint256 size;assembly {size := extcodesize(account)}return size > 0;}
	function setBridges(address optimism, address etc) external {require(msg.sender==_deployer,"can't");_optimismBridge = optimism;_etcBridge = etc;}
	function setTotalTknMnt(uint amount) external onlyBridgeOracle {_totalTokenAmount = amount;}

	function linkAddress(address account) external onlyFounder { // can be used to limit the amount of testers to only approved addresses
		require(_linkedAddresses[msg.sender] != account && _takenAddresses[account] == false, "already linked these or somebody already uses this");
		require(_isFounder(account) == false && _founders[msg.sender].ethContributed >= 1e16, "can't link founders or not enough eth deposited");
		_cleanUpLinked(msg.sender);
		_linkedAddresses[msg.sender] = account;
		_linkedAddresses[account] = msg.sender;
		_takenAddresses[account] = true;
		emit AddressLinked(msg.sender,account);
	}

	function _cleanUpLinked(address msgsender) internal {
		if (_linkedAddresses[msgsender] != address(0)) {
			address linkedAddress = _linkedAddresses[msgsender]; delete _linkedAddresses[msgsender]; delete _linkedAddresses[linkedAddress]; delete _takenAddresses[linkedAddress];
		}
	}

	function _calcLpShare(address msgsender) internal {
		uint ethContributed = _founders[msgsender].ethContributed;
		uint lpShare = _totalLGELPtokensMinted*ethContributed/_totalETHDeposited;
		uint inStock = IERC20(_tokenETHLP).balanceOf(address(this));
		if (lpShare > inStock) {lpShare = inStock;}
		return lpShare;
	}

	function _createLiquidity() internal {
		delete _lgeOngoing;
		uint ETHDeposited = address(this).balance;
		IWETH(_WETH).deposit{value: ETHDeposited}();
		_tokenETHLP = IUniswapV2Factory(_uniswapFactory).createPair(_token, _WETH);
		IERC20(_WETH).transfer(_tokenETHLP, ETHDeposited);
		IERC20(_token).transfer(_tokenETHLP, 1e27);
		IUniswapV2Pair(_tokenETHLP).mint(address(this));
		_totalLGELPtokensMinted = IERC20(_tokenETHLP).balanceOf(address(this));
		_totalETHDeposited = ETHDeposited;
	}
// VIEW FUNCTIONS ==================================================
	function getFounder(address account) external view returns (address newAddress,uint ethContributed, uint claimed, address linked) {
		return (_founders[msg.sender].newAddress,_founders[account].ethContributed,_founders[account].claimed,_linkedAddresses[account]);
	}

	function getFounderTknAmntLckPt(address account) external view returns (uint tknAmount,uint lockUpTo) {return (_founders[account].tokenAmount,_founders[account].lockUpTo);}

	function getLgeInfo() external view returns (uint rewGenesis,uint rewRate,uint totEthDepos, uint totTknAmount, uint totLGELPMinted) {
		uint halver = block.number/10000000;uint rewardsRate = 75;if (halver>1) {for (uint i=1;i<halver;i++) {rewardsRate=rewardsRate*5/6;}}
		return (_rewardsGenesis,rewardsRate,_totalETHDeposited,_totalTokenAmount,_totalLGELPtokensMinted);
	}
}
