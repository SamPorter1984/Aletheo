contract MockFactory {
    address public pair;

    function setPair(address _pair) public {
        pair = _pair;
    }

    function getPair(address t1, address t2) public view returns (address) {
        return pair;
    }
}
