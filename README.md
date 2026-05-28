# Polygon PoS contracts

Ethereum smart contracts that power [Polygon PoS](https://polygon.technology/polygon-pos).

## Development

### Install foundry

Follow the [foundry installation guide](https://book.getfoundry.sh/getting-started/installation).

### Install dependencies

```
npm install
```

Contributors should additionally set up pre-commit hooks — see [CONTRIBUTING.md](CONTRIBUTING.md#setup).

### Prepare templates

```
npm run template:process -- --bor-chain-id 15001
```

bor-chain-id should be:  
**local: 15001**  
Mainnet = 137  
Amoy = 80002

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

- Start the bor side chain. Requires docker.

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

## Contact

For more discussions, please head to the [R&D Discord](https://discord.gg/0xPolygonRnD)
