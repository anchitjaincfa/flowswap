// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
// A minimal, mintable ERC-20 we use as fake "test tokens" in this demo.
// (The real DEX contracts only care about the standard ERC-20 interface,
//  so a tiny token like this behaves exactly like a real one for our purposes.)
// ---------------------------------------------------------------------------
contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt;
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        _transfer(msg.sender, to, amt);
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        uint256 al = allowance[from][msg.sender];
        require(al >= amt, "allowance");
        if (al != type(uint256).max) allowance[from][msg.sender] = al - amt;
        _transfer(from, to, amt);
        return true;
    }

    function _transfer(address from, address to, uint256 amt) internal {
        require(balanceOf[from] >= amt, "balance");
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
    }
}

// ---------------------------------------------------------------------------
// Minimal interfaces to the forked (0.7.6) contracts. We only declare the few
// functions we actually call; the struct layouts must match periphery exactly.
// ---------------------------------------------------------------------------
interface INPM {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract HelloFlowSwap is Test {
    uint24 constant FEE = 3000; // the 0.30% fee tier (tick spacing 60)
    int24 constant TICK_LOWER = -887220; // full-range lower tick (multiple of 60)
    int24 constant TICK_UPPER = 887220; // full-range upper tick
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // starting price = 1.0

    function test_create_pool_add_liquidity_and_swap() public {
        // -- 1. Deploy the DEX engine (your forked 0.7.6 contracts, by name) --
        address weth = address(new TestERC20("Wrapped Ether", "WETH")); // placeholder; unused in a token<>token swap
        address factory = deployCode("UniswapV3Factory.sol:UniswapV3Factory");
        address router = deployCode("SwapRouter.sol:SwapRouter", abi.encode(factory, weth));
        address npm =
            deployCode("NonfungiblePositionManager.sol:NonfungiblePositionManager", abi.encode(factory, weth, address(0)));

        console.log("Factory       :", factory);
        console.log("SwapRouter    :", router);
        console.log("PositionMgr   :", npm);

        // -- 2. Two test tokens; mint ourselves 1,000,000 of each --
        TestERC20 a = new TestERC20("Test Token A", "TKA");
        TestERC20 b = new TestERC20("Test Token B", "TKB");
        // Uniswap pools require token0 < token1 by address.
        (TestERC20 token0, TestERC20 token1) = address(a) < address(b) ? (a, b) : (b, a);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);

        // -- 3. Create + initialize the pool at price 1:1 --
        address pool =
            INPM(npm).createAndInitializePoolIfNecessary(address(token0), address(token1), FEE, SQRT_PRICE_1_1);
        console.log("Pool created  :", pool);

        // -- 4. Add liquidity: 100,000 of each token, across the full range --
        token0.approve(npm, type(uint256).max);
        token1.approve(npm, type(uint256).max);
        (,, uint256 used0, uint256 used1) = INPM(npm).mint(
            INPM.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: 100_000 ether,
                amount1Desired: 100_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1000
            })
        );
        console.log("Liquidity in - token0 used:", used0 / 1e18);
        console.log("Liquidity in - token1 used:", used1 / 1e18);

        // -- 5. Swap 1,000 token0 -> token1 --
        uint256 amountIn = 1_000 ether;
        token0.approve(router, amountIn);
        uint256 balBefore = token1.balanceOf(address(this));
        uint256 amountOut = ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: FEE,
                recipient: address(this),
                deadline: block.timestamp + 1000,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        uint256 balAfter = token1.balanceOf(address(this));

        console.log("Swapped IN  (token0):", amountIn / 1e18);
        console.log("Received OUT(token1):", amountOut / 1e18);

        // -- Sanity checks --
        assertGt(amountOut, 0, "swap returned nothing");
        assertEq(balAfter - balBefore, amountOut, "balance change mismatch");
        assertLt(amountOut, amountIn, "out should be < in (fee + price impact)");
        console.log("SUCCESS: pool created, liquidity added, swap executed.");
    }
}
