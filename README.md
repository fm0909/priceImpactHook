# PriceImpactHook

A Uniswap v4 hook that dynamically adjusts trading fees based on the price impact of swaps.

## Overview

PriceImpactHook is a custom Uniswap v4 hook designed to create more efficient markets by charging higher fees for trades that have larger price impacts. This helps to:

1. Protect liquidity providers from large price swings
2. Discourage large trades that significantly move the market
3. Create a more equitable fee structure where traders pay fees proportional to their market impact

The hook implements a dynamic fee calculation system that starts with a base fee and scales it up based on the estimated price impact of each swap.

## Features

- **Dynamic Fee Calculation**: Fees scale with the price impact of trades
- **Configurable Parameters**: Adjustable base fee, minimum fee, maximum fee, and impact multiplier
- **Owner Controls**: Only the owner can update fee parameters

## How It Works

1. When a swap is initiated, the hook calculates the estimated price impact of the trade
2. Based on the impact, it calculates an appropriate fee using the formula:
   ```
   fee = baseFee + (priceImpactBips * impactMultiplier)
   ```
3. The fee is bounded by the configured minimum and maximum values
4. The hook returns the calculated fee to the pool manager, which applies it to the swap

## Fee Parameters

- `baseFee`: The starting fee for all swaps (default: 500 = 0.05%)
- `minFee`: The minimum fee that can be charged (default: 100 = 0.01%)
- `maxFee`: The maximum fee that can be charged (default: 25000 = 2.5%)
- `impactMultiplier`: Scales how aggressively fees increase with price impact (default: 50)

## Usage

When creating a Uniswap v4 pool, specify this hook as the `hooks` parameter in the `PoolKey` and make sure to set the dynamic fee flag in the `fee` parameter.

```solidity
// Example pool creation
PoolKey memory key = PoolKey({
    currency0: currency0,
    currency1: currency1,
    fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, // Must use dynamic fee flag
    tickSpacing: 60,
    hooks: IHooks(address(priceImpactHook))
});

poolManager.initialize(key, startingPrice, "");
```

## Requirements

- Uniswap v4-core
- Uniswap v4-periphery
- Solidity 0.8.x

## Setup

1. Deploy the PriceImpactHook with the Uniswap v4 PoolManager address
2. Create pools that use the hook with the dynamic fee flag set
3. Configure fee parameters as needed for your specific use case

## Admin Functions

- `updateFeeParameters(uint24 _baseFee, uint24 _minFee, uint24 _maxFee, uint24 _impactMultiplier)`: Update the fee calculation parameters
- `transferOwnership(address newOwner)`: Transfer control of the hook to a new owner

## License

MIT
