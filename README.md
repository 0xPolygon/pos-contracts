# Matic contracts

![Build Status](https://github.com/maticnetwork/contracts/workflows/CI/badge.svg)

Ethereum smart contracts that power the [Matic Network](https://polygon.technology/polygon-pos).

## Development
### Install dependencies with

```
npm install
```

### Setup git hooks

```
pre-commit install
```

### Prepare templates

```
npm run template:process -- --bor-chain-id 15001
```

bor-chain-id should be:  
**local: 15001**  
Mainnet = 137  
TestnetV4 (Mumbai) = 80001

### Generate interfaces

```
npm run generate:interfaces
```

### Build

```
forge build
```

## Testing

### Run forge upgrade forktest

```
forge test
```

### Run unit tests


#### Main chain and side chain

- Main chain

All tests are run against a fork of mainnet using Hardhat's forking functionality. No need to run any local chain!

- Start Matic side chain. Requires docker.

```
npm run bor:simulate
```

- Stop with

```
npm run bor:stop
```

- If you want a clean chain, this also deletes your /data folder containing the chain state.

```
npm run bor:clean
```

#### Run tests

Run Hardhat test

```
npm run test:hardhat
```

### Coverage

Run coverage with

```
npm run coverage
```
