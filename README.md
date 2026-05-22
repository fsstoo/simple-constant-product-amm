# SimpleAMM

A minimal constant product Automated Market Maker (AMM) built with Solidity and Foundry, inspired by Uniswap V2.

This project implements:

- Liquidity provisioning
- LP token minting/burning
- Constant product swaps
- 0.3% swap fee
- Slippage protection
- Invariant testing
- Fuzz testing
- Reentrancy protection

---


# Overview

`SimpleAMM` is a two-token liquidity pool where users can:

- Add liquidity
- Remove liquidity
- Swap between token pairs
- Earn LP shares representing pool ownership

The protocol follows the classic constant product invariant:

```math
x * y = k
```

Where:

- `x` = reserve of tokenA
- `y` = reserve of tokenB
- `k` = constant product invariant

---


# Features

## Core AMM Logic

- Constant product pricing model
- Deterministic swap output calculation
- Reserve tracking
- LP share accounting

## Liquidity Management

- Add liquidity proportionally
- Remove liquidity proportionally
- Minimum liquidity permanently locked
- Initial liquidity imbalance protection

## Security

- Reentrancy protection
- Custom errors
- Slippage checks
- Invariant enforcement
- Fee-on-transfer token rejection

## Testing

- Unit tests
- Fuzz tests
- Stateful invariant tests

---


# Tech Stack

- Solidity `0.8.20`
- Foundry
- OpenZeppelin Contracts

---


# Project Structure

```txt

script/   
src/       
test/

```

---


# AMM Formula

Swap output calculation:

```solidity
amountInWithFee = amountIn * 997;

amountOut =
    (reserveOut * amountInWithFee) /
    (reserveIn * 1000 + amountInWithFee);
```

Swap fee:

```txt
0.3%
```

---


# LP Token Logic

Liquidity providers receive LP tokens representing ownership of the pool.

Initial liquidity:

```solidity
shares = sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
```

Subsequent liquidity:

```solidity
shares = min(
    amountA * totalSupply / reserveA,
    amountB * totalSupply / reserveB
);
```

---


# Security Assumptions

## NOT Supported

The protocol intentionally does NOT support:

- Fee-on-transfer tokens
- Rebasing tokens
- Tokens with callbacks/hooks

## Owner Permissions

Owner can:

- `skim()` excess tokens
- `sync()` reserves to actual balances

Owner CANNOT:

- Mint arbitrary LP tokens
- Steal user liquidity
- Change swap fees

---


# Testing

## Run Unit Tests

```bash
forge test
```

## Run Invariant Tests

```bash
forge test --match-path test/invariant/*
```

## Run Coverage

```bash
forge coverage
```

---


# Invariants Tested

The invariant suite validates:

- Constant product invariant never decreases after swaps
- Reserves always match balances
- LP supply accounting stays correct
- Total supply never falls below minimum liquidity
- Reserves are never partially zero
- Zero address never holds LP tokens

---


# Example Workflow

## Add Liquidity

```solidity
amm.addLiquidity(
    amountADesired,
    amountBDesired,
    amountAMin,
    amountBMin
);
```

## Swap

```solidity
amm.swap(
    tokenIn,
    amountIn,
    amountOutMin
);
```

## Remove Liquidity

```solidity
amm.removeLiquidity(
    shares,
    amountAMin,
    amountBMin
);
```

---


# Gas & Optimization Notes

Optimizations used:

- Cached storage reads
- Custom errors
- Internal helper functions
- Minimal storage writes

---


# Future Improvements

Potential future upgrades:

- Factory contract
- Router contract
- Multi-pair architecture
- Flash swaps
- TWAP oracles
- Protocol fee switch
- Concentrated liquidity research

---


# Learning Goals

This project was built to practice:

- DeFi protocol architecture
- AMM mathematics
- Solidity security patterns
- Foundry testing
- Invariant testing
- Fuzz testing
- LP accounting systems

---


# Disclaimer

This project is for educational purposes and has not been audited.

Do NOT use in production with real funds.

---


# Author

Built by FSTO using Solidity + Foundry.