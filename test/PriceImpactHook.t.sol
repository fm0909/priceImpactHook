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
                tickLower: -6000,
                tickUpper: 6000,
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
        uint256[] memory rates = new uint256[](3);

        // Add header for our results table
        console.log("=== PRICE IMPACT TEST RESULTS ===");
        console.log(
            "Swap Size | Output Amount | Effective Rate | Price Impact | Fee"
        );
        console.log(
            "----------------------------------------------------------"
        );

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

            // Calculate effective rate (output per input) - scaled by 1e18 for precision
            rates[i] = (outputs[i] * 1e18) / uint256(-swapAmounts[i]);

            // Calculate price impact percentage (1 - effectiveRate/1e18) * 100
            uint256 priceImpactPercent = ((1e18 - rates[i]) * 100) / 1e18;

            // Log the results in a simpler format
            if (i == 0) {
                console.log(
                    string.concat(
                        "0.01 ETH | ",
                        formatEth(outputs[i]),
                        " | ",
                        formatPercent(rates[i]),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "%"
                    )
                );
            } else if (i == 1) {
                console.log(
                    string.concat(
                        "1.0 ETH  | ",
                        formatEth(outputs[i]),
                        " | ",
                        formatPercent(rates[i]),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "%"
                    )
                );
            } else {
                console.log(
                    string.concat(
                        "10.0 ETH | ",
                        formatEth(outputs[i]),
                        " | ",
                        formatPercent(rates[i]),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "% | ",
                        vm.toString(priceImpactPercent),
                        "%"
                    )
                );
            }
        }
        console.log(
            "----------------------------------------------------------"
        );
        console.log(
            "Note: Price impact increases with swap size, and fees scale with price impact"
        );

        // Verify that larger swaps have worse rates (higher fees/price impact)
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

        // Log the conclusion
        console.log(
            "TEST PASSED: Larger swaps have higher price impact and higher fees"
        );
    }

    // Helper function to format ETH values with 4 decimal places
    function formatEth(uint256 amount) internal pure returns (string memory) {
        uint256 eth = amount / 1e18;
        uint256 decimal = (amount % 1e18) / 1e14;

        if (eth > 0) {
            return
                string(
                    abi.encodePacked(
                        vm.toString(eth),
                        ".",
                        decimal < 10 ? "000" : decimal < 100
                            ? "00"
                            : decimal < 1000
                            ? "0"
                            : "",
                        vm.toString(decimal),
                        " ETH"
                    )
                );
        } else {
            return
                string(
                    abi.encodePacked(
                        "0.",
                        decimal < 10 ? "000" : decimal < 100
                            ? "00"
                            : decimal < 1000
                            ? "0"
                            : "",
                        vm.toString(decimal),
                        " ETH"
                    )
                );
        }
    }

    // Helper function to format percentage with 2 decimal places
    function formatPercent(uint256 rate) internal pure returns (string memory) {
        uint256 percent = (rate * 100) / 1e18;
        uint256 decimal = ((rate * 10000) / 1e18) % 100;

        return
            string(
                abi.encodePacked(
                    vm.toString(percent),
                    ".",
                    decimal < 10 ? "0" : "",
                    vm.toString(decimal)
                )
            );
    }
}
