contract MockFoundingEvent {
    mapping(address => uint) public deposits;
    uint public genesisBlock;
    uint public sold = 5000000000000000;

    function setDeposit(address a, uint d) public {
        deposits[a] = d;
    }

    function setGenesisBlock(uint gb) public {
        genesisBlock = gb;
    }
}
