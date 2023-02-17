// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface I {
    function transferFrom(address from, address to, uint amount) external returns (bool);

    function sync() external;

    function addPool(address a) external;

    function balanceOf(address a) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function createPair(address t, address t1) external returns (address pair);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract LiquidityManager {
    mapping(address => uint) public amounts;

    struct AddressBook {
        address router;
        address factory;
        address mainToken;
        address defTokenFrom;
        address defPoolFrom;
        address defTokenTo;
        address defPoolTo;
        address liqMan;
        address dao;
    }

    AddressBook public ab;
    uint abLastUpdate;
    AddressBook public abPending;

    function init(AddressBook calldata _ab) public {
        //alert
        ab = _ab;
        address LP = I(_ab.factory).getPair(_ab.mainToken, _ab.defTokenFrom);
        if (LP == address(0)) {
            LP = I(_ab.factory).createPair(_ab.mainToken, _ab.defTokenFrom);
        }
        address defPoolFrom = LP; //WETH pool
        I(_ab.mainToken).addPool(LP);
        LP = I(_ab.factory).getPair(_ab.mainToken, _ab.defTokenTo);
        if (LP == address(0)) {
            LP = I(_ab.factory).createPair(_ab.mainToken, _ab.defTokenTo);
        }
        address defPoolTo = LP; //DAI pool
        I(_ab.mainToken).addPool(LP);
        I(_ab.mainToken).approve(_ab.router, 2 ** 256 - 1);
        I(_ab.defTokenFrom).approve(_ab.router, 2 ** 256 - 1);
        I(_ab.defTokenTo).approve(_ab.router, 2 ** 256 - 1);
        I(defPoolFrom).approve(_ab.router, 2 ** 256 - 1);
        I(defPoolTo).approve(_ab.router, 2 ** 256 - 1);
    }

    function setPendingAddressBook(AddressBook calldata pab_) external {
        require(msg.sender == ab.liqMan);
        abPending = pab_;
    }

    function setAddressBook() external {
        require(msg.sender == ab.liqMan && abLastUpdate > block.number + 1209600); // 2 weeks for this version
        abLastUpdate = block.number;
        ab = abPending;
    }

    modifier onlyLiqMan() {
        require(msg.sender == ab.liqMan);
        _;
    }
    modifier onlyDao() {
        require(msg.sender == ab.dao);
        _;
    }

    function approve(address token) public onlyLiqMan {
        I(token).approve(ab.router, 2 ** 256 - 1);
    }

    function swapLiquidity(address tokenFrom, address tokenTo, uint percent) public onlyDao {
        address factory = ab.factory;
        address mainToken = ab.mainToken;
        address pFrom = I(factory).getPair(mainToken, tokenFrom);
        address pTo = I(factory).getPair(mainToken, tokenTo);
        uint liquidity = (I(pFrom).balanceOf(address(this)) * percent) / 100;
        if (I(mainToken).balanceOf(pTo) == 0) {
            I(mainToken).addPool(pTo);
        }
        _swapLiquidity(tokenFrom, tokenTo, liquidity);
    }

    function swapLiquidityDef(uint percent) public onlyLiqMan {
        address mainToken = ab.mainToken;
        address defPoolFrom = ab.defPoolFrom;
        address defPoolTo = ab.defPoolTo;
        uint amountFrom = I(mainToken).balanceOf(defPoolFrom);
        uint amountTo = I(mainToken).balanceOf(defPoolTo);
        uint liquidity;
        address tokenFrom = ab.defTokenFrom;
        address tokenTo = ab.defTokenTo;
        if (amountTo > amountFrom) {
            liquidity = I(defPoolTo).balanceOf(address(this));
            tokenFrom = ab.defTokenTo;
            tokenTo = ab.defTokenFrom;
        } else {
            liquidity = I(defPoolFrom).balanceOf(address(this));
        }
        liquidity = (liquidity * percent) / 100;
        _swapLiquidity(tokenFrom, tokenTo, liquidity);
    }

    function _swapLiquidity(address tokenFrom, address tokenTo, uint liquidity) private {
        address router = ab.router;
        address factory = ab.factory;
        address mainToken = ab.mainToken;
        address[] memory ar = new address[](2);
        ar[0] = tokenFrom;
        ar[1] = tokenTo;
        I(router).removeLiquidity(mainToken, tokenFrom, liquidity, 0, 0, address(this), 2 ** 256 - 1);
        I(router).swapExactTokensForTokens(I(tokenFrom).balanceOf(address(this)), 0, ar, address(this), 2 ** 256 - 1);
        I(router).addLiquidity(
            mainToken,
            tokenTo,
            I(mainToken).balanceOf(address(this)),
            I(tokenTo).balanceOf(address(this)),
            0,
            0,
            address(this),
            2 ** 256 - 1
        );
        address p = I(factory).getPair(mainToken, tokenTo);
        if (I(tokenTo).balanceOf(address(this)) > 0) {
            I(tokenTo).transfer(p, I(tokenTo).balanceOf(address(this)));
            I(p).sync();
        }
        if (I(mainToken).balanceOf(address(this)) > 0) {
            I(mainToken).transfer(p, I(mainToken).balanceOf(address(this)));
            I(p).sync();
        }
    }

    function changeDefTokenTo(address token) public onlyDao {
        address factory = ab.factory;
        address router = ab.router;
        address mainToken = ab.mainToken;
        ab.defTokenTo = token;
        address pool = I(factory).getPair(mainToken, token);
        if (pool == address(0)) {
            pool = I(factory).createPair(mainToken, token);
        }
        ab.defPoolTo = pool;
        I(token).approve(router, 2 ** 256 - 1);
        I(pool).approve(router, 2 ** 256 - 1);
        I(mainToken).addPool(pool);
    }

    function addLiquidity() external payable {
        address mainToken = ab.mainToken;
        I(ab.router).addLiquidityETH{value: address(this).balance}(
            mainToken,
            I(mainToken).balanceOf(address(this)),
            0,
            0,
            address(this),
            2 ** 256 - 1
        );
    }

    function stakeLiquidity(uint amount) external {
        address mainToken = ab.mainToken;
        address defPoolFrom = ab.defPoolFrom;
        amounts[msg.sender] += amount;
        I(defPoolFrom).transferFrom(msg.sender, address(this), amount);
        uint amountFrom = I(mainToken).balanceOf(defPoolFrom);
        uint amountTo = I(mainToken).balanceOf(ab.defPoolTo);
        if (amountTo > amountFrom) {
            _swapLiquidity(ab.defTokenFrom, ab.defTokenTo, amount);
        }
    }

    function unstakeLiquidity(uint amount) external {
        require(amounts[msg.sender] >= amount);
        address defPoolFrom = ab.defPoolFrom;
        amounts[msg.sender] -= amount;
        if (I(defPoolFrom).balanceOf(address(this)) >= amount) {
            I(defPoolFrom).transfer(msg.sender, amount);
        } else {
            address defTokenTo = ab.defTokenTo;
            address defTokenFrom = ab.defTokenFrom;
            uint liquidity = I(ab.defPoolTo).balanceOf(address(this));
            _swapLiquidity(defTokenTo, defTokenFrom, liquidity);
            I(defPoolFrom).transfer(msg.sender, amount);
            liquidity = I(defPoolFrom).balanceOf(address(this));
            _swapLiquidity(defTokenFrom, defTokenTo, liquidity);
        }
    }

    fallback() external payable {}

    receive() external payable {} //if uniswap sends back dust
}
