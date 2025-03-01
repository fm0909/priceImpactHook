// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PriceImpactHook} from "src/PriceImpactHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

contract TestPriceImpactHook is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PriceImpactHook hook;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress = address(
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG)
        );

        // Deploy our hook
        deployCodeTo("PriceImpactHook.sol", abi.encode(manager), hookAddress);
        hook = PriceImpactHook(hookAddress);

        // Initialize a pool
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // Add some liquidity (100 ether)
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_feeIncreasesWithPriceImpact() public {
        // Set up our swap test settings
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        // Test parameters - using 3 swap sizes
        int256[] memory swapAmounts = new int256[](3);
        swapAmounts[0] = -0.01 ether; // Small swap (0.01 ETH)
        swapAmounts[1] = -1 ether; // Medium swap (1 ETH)
        swapAmounts[2] = -10 ether; // Large swap (10 ETH)

        uint256[] memory outputs = new uint256[](3);

        // Perform swaps with different amounts and measure output
        for (uint256 i = 0; i < swapAmounts.length; i++) {
            // Set up swap parameters
            IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: swapAmounts[i],
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });

            // Record balance before swap
            uint256 balanceOfToken1Before = currency1.balanceOfSelf();

            // Execute the swap
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // Record balance after swap
            uint256 balanceOfToken1After = currency1.balanceOfSelf();

            // Calculate output amount
            outputs[i] = balanceOfToken1After - balanceOfToken1Before;

            // Log for visibility
            console.log("Swap amount:", uint256(-swapAmounts[i]));
            console.log("Output amount:", outputs[i]);
            console.log("-------------------");

            // Verify we received something
            assertGt(balanceOfToken1After, balanceOfToken1Before);
        }

        // Calculate effective rates (output per input)
        uint256[] memory rates = new uint256[](3);
        for (uint256 i = 0; i < swapAmounts.length; i++) {
            // Multiply by 1e18 for precision when dividing
            rates[i] = (outputs[i] * 1e18) / uint256(-swapAmounts[i]);
            console.log("Effective rate for swap", i, ":", rates[i]);
        }

        // Verify that larger swaps have worse rates (higher fees/price impact)
        // The rate should decrease as the swap size increases
        assertGt(
            rates[0],
            rates[1],
            "Small swap should have better rate than medium swap"
        );
        assertGt(
            rates[1],
            rates[2],
            "Medium swap should have better rate than large swap"
        );
    }
}
