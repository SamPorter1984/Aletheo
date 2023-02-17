// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

// author: SamPorter1984
interface I {
    function enableTrading() external;

    function sync() external;

    function getPair(address t, address t1) external view returns (address pair);

    function createPair(address t, address t1) external returns (address pair);

    function transfer(address to, uint value) external returns (bool);

    function transferFrom(address from, address to, uint amount) external returns (bool);

    function balanceOf(address) external view returns (uint);

    function approve(address spender, uint256 value) external returns (bool);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

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

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function deposit() external payable;
}

contract FoundingEvent {
    mapping(address => uint) public deposits;
    bool public emergency;
    bool public swapToETH;
    uint public genesisBlock;
    uint public hardcap;
    uint public sold;
    uint public presaleEndBlock;
    uint public maxSold;

    struct AddressBook {
        address payable deployer;
        address liquidityManager;
        address letToken;
        address WETH;
        address DAI;
        address router;
        address factory;
    }

    AddressBook public ab;
    uint abLastUpdate;
    AddressBook public abPending;
    bool public initialized;

    function init(AddressBook memory _ab) external {
        require(msg.sender == 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199); //alert
        require(!initialized);
        initialized = true;
        ab = _ab;
        abLastUpdate = block.number;
        maxSold = 50000e18;
        I(ab.WETH).approve(ab.router, 2 ** 256 - 1);
        I(ab.letToken).approve(ab.router, 2 ** 256 - 1);
        I(ab.DAI).approve(ab.router, 2 ** 256 - 1);
    }

    function setupEvent(uint248 b) external {
        require(msg.sender == ab.deployer, 'not deployer');
        require(b > block.number, 'choose higher block');
        if (presaleEndBlock != 0) {
            require(b < presaleEndBlock);
        }
        presaleEndBlock = b;
    }

    function depositDAI(uint amount) external {
        require(presaleEndBlock > 0 && !emergency);
        I(ab.DAI).transferFrom(msg.sender, address(this), amount);
        I(ab.DAI).transfer(ab.deployer, amount / 10);
        if (swapToETH) {
            _swap(ab.DAI, ab.WETH, (amount / 10) * 9);
        }
        deposits[msg.sender] += amount / 2;
        I(ab.letToken).transfer(msg.sender, amount / 2);
        sold += amount;
        if (sold >= maxSold || block.number >= presaleEndBlock) {
            _createLiquidity();
        }
    }

    function depositETH() external payable {
        require(presaleEndBlock > 0 && !emergency, 'too late');
        uint letAmount = _calculateLetAmountInToken(ab.WETH, msg.value);
        (bool success, ) = payable(ab.deployer).call{value: msg.value / 10}('');
        require(success, 'try again');
        if (!swapToETH) {
            I(ab.WETH).deposit{value: address(this).balance}();
            _swap(ab.WETH, ab.DAI, (msg.value * 9) / 10);
        } else {
            I(ab.WETH).deposit{value: address(this).balance}();
        }
        deposits[msg.sender] += letAmount / 2;
        I(ab.letToken).transfer(msg.sender, letAmount / 2);
        sold += letAmount;
        if (sold >= maxSold || block.number >= presaleEndBlock) {
            _createLiquidity();
        }
    }

    //required for fee on transfer tokens
    function _calculateLetAmountInToken(address token, uint amount) internal view returns (uint) {
        // alert
        if (token == ab.DAI) return amount;
        address pool = I(ab.factory).getPair(token, ab.DAI);
        (address token0, ) = token < ab.DAI ? (token, ab.DAI) : (ab.DAI, token);
        (uint reserve0, uint reserve1, ) = I(pool).getReserves();
        (uint reserveToken, uint reserveDAI) = token == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return (amount * reserveToken) / reserveDAI;
    }

    //fails if no direct route available and probably can get scammed with fee on transfer tokens
    function _swap(address token0, address token1, uint amount) private returns (uint[] memory tradeResult) {
        if (I(token0).balanceOf(address(this)) > 0) {
            address[] memory ar = new address[](2);
            ar[0] = token0;
            ar[1] = token1;
            tradeResult = I(ab.router).swapExactTokensForTokens(amount, 0, ar, address(this), 2 ** 256 - 1);
        }
    }

    function setSwapToETH(bool swapToETH_) public {
        require(msg.sender == ab.deployer, 'only deployer');
        swapToETH = swapToETH_;
        swapToETH_ == true ? _swap(ab.DAI, ab.WETH, I(ab.DAI).balanceOf(address(this))) : _swap(ab.WETH, ab.DAI, I(ab.WETH).balanceOf(address(this)));
    }

    function _createLiquidity() internal {
        address liquidityManager = ab.liquidityManager;
        address token = ab.letToken;
        address letETHLP = I(ab.factory).getPair(token, ab.WETH);
        if (letETHLP == address(0)) {
            letETHLP = I(ab.factory).createPair(token, ab.WETH);
        }
        if (!swapToETH) {
            _swap(ab.DAI, ab.WETH, I(ab.DAI).balanceOf(address(this)));
        }
        I(ab.router).addLiquidity(
            token,
            ab.WETH,
            I(token).balanceOf(address(this)),
            I(ab.WETH).balanceOf(address(this)),
            0,
            0,
            liquidityManager,
            2 ** 256 - 1
        );
        genesisBlock = block.number;

        // if somebody already created the pool
        uint WETHBalance = I(ab.WETH).balanceOf(address(this));
        if (WETHBalance > 0) {
            I(ab.WETH).transfer(letETHLP, WETHBalance);
        }
        uint letBalance = I(token).balanceOf(address(this));
        if (letBalance > 0) {
            I(token).transfer(letETHLP, letBalance);
        }
        I(letETHLP).sync();
    }

    function triggerLaunch() public {
        if (block.number < presaleEndBlock) {
            require(msg.sender == ab.deployer);
        }
        _createLiquidity();
    }

    function toggleEmergency() public {
        require(msg.sender == ab.deployer);
        emergency = !emergency;
    }

    // founding event can swap funds back and forth between ETH and DAI,
    // its almost a guarantee that the last caller of withdraw
    // won't get at least some wei back no matter the setup
    function withdraw() public {
        require(emergency == true && deposits[msg.sender] > 0);
        uint withdrawAmount = (deposits[msg.sender] * 19) / 20;
        if (I(ab.WETH).balanceOf(address(this)) > 0) {
            _swap(ab.WETH, ab.DAI, I(ab.WETH).balanceOf(address(this)));
        }
        if (I(ab.DAI).balanceOf(address(this)) < withdrawAmount) {
            withdrawAmount = I(ab.DAI).balanceOf(address(this));
        }
        I(ab.DAI).transfer(msg.sender, withdrawAmount);
        delete deposits[msg.sender];
    }

    function setPendingAddressBook(AddressBook calldata pab_) external {
        require(msg.sender == ab.deployer);
        abPending = pab_;
    }

    function setAddressBook() external {
        require(msg.sender == ab.deployer && abLastUpdate > block.number + 1209600); // 2 weeks for this version
        abLastUpdate = block.number;
        ab = abPending;
    }
}
