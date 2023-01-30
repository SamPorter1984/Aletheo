contract MockRouter {
    address public WETH = address(this);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public returns (uint256[] memory amounts) {
        (bool success, ) = payable(to).call{value: 11111111111111111111}('');
    }

    receive() external payable {}

    fallback() external payable {}
}
