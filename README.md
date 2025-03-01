##

propery 'lpFee' exists in 'Pool.State.Slot0'

##

Update fee either via 'updateDynamicLPFee' for infrequent updates,
or 'beforeSwap' for dynamic updates each swap

## Mechanism Design

Q. How to track gas price or some other metric to update the fee?

there is no way to fetch the average gas price onchain, so we have to build a basic average gas-price tracker

we can only track the gas prie of transaction that are coming to our hook
we will use this to update out internal moving average gas price value

Q. How much to increase or decrease the fee subject to how much the gas price is higher or lower than the average?

if current_gas_price > average_gas_price {
charge swap fees = base fees / 2;
} else if current_gas_price < 90% of average_gas_price {
charge swap fees = base fees \* 2;
} else {
charge swap fees = base fees;
}

## Flow

'beforeInitialize':
-> make sure that the pool is initialized with support for dynamic fees

'beforeSwap':
-> track the gas price of the transaction coming through our hook and change the swap fees accordingly

'afterSwap':
-> update the average gas price based on the gas price of the transaction
