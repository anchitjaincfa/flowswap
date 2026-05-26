// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import {UniswapV3Factory} from "../src/core/UniswapV3Factory.sol";
import {SwapRouter} from "../src/periphery/SwapRouter.sol";
import {NonfungiblePositionManager} from "../src/periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "../src/periphery/interfaces/INonfungiblePositionManager.sol";
import {WETH9} from "../src/mocks/WETH9.sol";
import {FaucetToken} from "../src/mocks/FaucetToken.sol";

// --- Minimal Foundry cheatcode interface (so this can stay on Solidity 0.7.6) ---
interface Vm {
    function envUint(string calldata key) external view returns (uint256);
    function addr(uint256 privateKey) external view returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

// --- Minimal console.log (forge intercepts calls to this address) ---
library console {
    address constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    function _send(bytes memory payload) private view {
        address c = CONSOLE;
        assembly {
            pop(staticcall(gas(), c, add(payload, 32), mload(payload), 0, 0))
        }
    }

    function log(string memory a) internal view {
        _send(abi.encodeWithSignature("log(string)", a));
    }

    function log(string memory a, address b) internal view {
        _send(abi.encodeWithSignature("log(string,address)", a, b));
    }
}

/// @notice Deploys the full FlowSwap DEX (factory, router, position manager, WETH),
///         two faucet test tokens, then creates a pool and seeds it with liquidity.
contract DeployFlowSwap {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint24 constant FEE = 3000; // 0.30% tier (tick spacing 60)
    int24 constant TICK_LOWER = -887220; // full range
    int24 constant TICK_UPPER = 887220;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // start price = 1.0

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1. The DEX engine
        UniswapV3Factory factory = new UniswapV3Factory();
        WETH9 weth = new WETH9();
        SwapRouter router = new SwapRouter(address(factory), address(weth));
        NonfungiblePositionManager npm =
            new NonfungiblePositionManager(address(factory), address(weth), address(0));

        // 2. Two faucet test tokens
        FaucetToken tokenA = new FaucetToken("FlowSwap Test A", "fTKA");
        FaucetToken tokenB = new FaucetToken("FlowSwap Test B", "fTKB");

        // 3. Seed the deployer with supply
        tokenA.mint(deployer, 1_000_000 ether);
        tokenB.mint(deployer, 1_000_000 ether);

        // 4. Create + initialize the pool at 1:1 (tokens must be sorted by address)
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        npm.createAndInitializePoolIfNecessary(t0, t1, FEE, SQRT_PRICE_1_1);

        // 5. Add 100,000 of each token as full-range liquidity
        tokenA.approve(address(npm), type(uint256).max);
        tokenB.approve(address(npm), type(uint256).max);
        npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: t0,
                token1: t1,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: 100_000 ether,
                amount1Desired: 100_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp + 3600
            })
        );

        vm.stopBroadcast();

        // 6. Print the deployed addresses
        console.log("---- FlowSwap deployed ----");
        console.log("Deployer:        ", deployer);
        console.log("Factory:         ", address(factory));
        console.log("WETH9:           ", address(weth));
        console.log("SwapRouter:      ", address(router));
        console.log("PositionManager: ", address(npm));
        console.log("Token A (fTKA):  ", address(tokenA));
        console.log("Token B (fTKB):  ", address(tokenB));
    }
}
