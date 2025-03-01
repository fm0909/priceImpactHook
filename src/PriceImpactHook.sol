//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract PriceImpactHook is BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    // Owner address
    address public owner;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = msg.sender;
    }

    // Fee parameters
    uint24 public baseFee = 500; // Default 0.05% fee
    uint24 public minFee = 100; // Minimum 0.01% fee
    uint24 public maxFee = 25000; // Maximum 2.5% fee
    uint24 public impactMultiplier = 50; // How much to scale fee based on impact

    // Error messages
    error MustUseDynamicFee();
    error Unauthorized();

    // let everyone know what hook we are implementing
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true, // set dynamic fee flag
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // adjust fees
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // hook functions:
    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160 /*initial sqrtPrice)*/
    ) internal override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();

        return this.beforeInitialize.selector;
    }

    function _beforeSwap(
        address, // sender (unused)
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata // hookData (unused)
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Calculate price impact of this swap
        uint24 priceImpactBips = calculatePriceImpact(key, params);

        // Calculate appropriate fee based on impact
        uint24 dynamicFee = calculateDynamicFee(priceImpactBips);

        // Return the fee with override flag
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            dynamicFee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function calculatePriceImpact(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal view returns (uint24) {
        PoolId poolId = key.toId();

        // Get current pool liquidity
        uint128 liquidity = poolManager.getLiquidity(poolId);

        // Get swap amount
        uint256 swapAmount;
        if (params.amountSpecified < 0) {
            // Exact input swap
            swapAmount = uint256(-params.amountSpecified);
        } else {
            // Exact output swap
            swapAmount = uint256(params.amountSpecified);
        }

        // Simplified price impact calculation: swap size relative to pool liquidity
        // This is a simplified approximation - a more accurate implementation would use
        // the actual Uniswap v3 formula with concentrated liquidity adjustments
        uint24 priceImpactBips;
        if (liquidity > 0) {
            // Calculate impact as a percentage of liquidity (in basis points)
            priceImpactBips = uint24((swapAmount * 10000) / liquidity);

            // Cap at 10000 (100%)
            if (priceImpactBips > 10000) {
                priceImpactBips = 10000;
            }
        } else {
            // If no liquidity, treat as maximum impact
            priceImpactBips = 10000;
        }

        return priceImpactBips;
    }

    /**
     * @notice Calculate dynamic fee based on price impact
     * @param priceImpactBips The price impact in basis points (1/10000)
     * @return The calculated fee
     */
    function calculateDynamicFee(
        uint24 priceImpactBips
    ) internal view returns (uint24) {
        // Start with base fee
        uint24 fee = baseFee;

        // Add impact component (higher impact = higher fee)
        fee += priceImpactBips * impactMultiplier;

        // Apply bounds
        if (fee < minFee) {
            fee = minFee;
        } else if (fee > maxFee) {
            fee = maxFee;
        }

        return fee;
    }

    /**
     * @notice Update fee parameters - only callable by owner
     * @param _baseFee New base fee
     * @param _minFee New minimum fee
     * @param _maxFee New maximum fee
     * @param _impactMultiplier New impact multiplier
     */
    function updateFeeParameters(
        uint24 _baseFee,
        uint24 _minFee,
        uint24 _maxFee,
        uint24 _impactMultiplier
    ) external {
        if (msg.sender != owner) revert Unauthorized();

        baseFee = _baseFee;
        minFee = _minFee;
        maxFee = _maxFee;
        impactMultiplier = _impactMultiplier;
    }

    /**
     * @notice Transfer ownership of the contract
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        if (newOwner == address(0)) revert Unauthorized();
        owner = newOwner;
    }
}
