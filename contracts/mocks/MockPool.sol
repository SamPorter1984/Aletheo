contract MockPool {
    uint reserve1 = 3;
    uint reserve2 = 1;

    function getReserves() public view returns (uint, uint, uint) {
        return (reserve1, reserve2, 0);
    }

    function setReserves(uint r1, uint r2) public {
        reserve1 = r1;
        reserve2 = r2;
    }
}
