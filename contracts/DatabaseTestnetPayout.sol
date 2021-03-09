pragma solidity >=0.7.0;

contract PayoutDatabase {
	address private _governance;
	mapping (address => bool) private _oracles;
	mapping (address => uint) private _payouts;
	
	constructor() {_governance = msg.sender;}

	modifier onlyOracle() {require(_oracles[msg.sender] == true, "not an oracle");_;}
	modifier onlyGovernance() {require(msg.sender == _governance, "not a governance address");_;}

	function recordPayoutByOracle(address[] memory workers, uint[] memory payouts) public onlyOracle {for (uint i = 0; i < workers.length; i++) {_payouts[workers[i]] += payouts[i];}}
	function toggleOracle(address[] memory a) public onlyGovernance {for (uint i = 0; i < a.length; i++) {if (_oracles[a[i]] == false) {_oracles[a[i]] = true;} else {delete _oracles[a[i]];}}}
	function setGovernance(address account) public onlyGovernance {_governance = account;}

	function getAddress(address account) public view returns(uint payout, bool oracle) {return (_payouts[account],_oracles[account]);}
	function getSettings() public view returns(address gov) {return _governance;}
}
