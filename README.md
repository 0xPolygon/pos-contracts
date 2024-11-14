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
## Deployment on Anvil

### Starting Local Anvil Server

```bash
anvil --port 9545 \
      --balance 1000000000000000 \
      --gas-limit 1000000000000000000 \
      --gas-price 1 \
      --code-size-limit 1000000000000000000 \
      --verbosity
```

The above command will start anvil on port 9545 on your machine with 10 accounts (10 is default, you can use the --accounts flag to specify the number), with specified gas-limit, gas price and code size limit. You can check all the other options on the [anvil-reference page](https://book.getfoundry.sh/reference/anvil/) or can use the command `anvil --help`

### Preparing for deployment

To use forge script, we need to modify the `.env` file, check the `.env.example`. 

1. `DEPLOYER_PRIVATE_KEY` should be the account used to deploy the contracts, for anvil, you can choose any of the accounts given to you by anvil. (You will be given 10 [default] accounts to use, choose any one of the private keys).
2. `ETHERSCAN_API_KEY`
3. `HEIMDALL_ID`

### Deployment of contracts on anvil (Adjusted mainly for matic-cli)

#### Deploy Root contracts
```bash
forge script scripts/deployment-scripts/deployContracts.s.sol:DeploymentScript \
    --rpc-url http://localhost:<PORT> \
    --private-key <DEPLOYER_PRIVATE_KEY> \
    --broadcast
```

#### Deploy DrainStakeManager
```bash
forge script scripts/deployment-scripts/drainStakeManager.s.sol:DrainStakeManagerDeployment \
    --rpc-url http://localhost:<PORT> \
    --private-key <DEPLOYER_PRIVATE_KEY> \
    --broadcast
```

#### Deploy child contracts
```bash
forge script scripts/deployment-scripts/childContractDeployment.s.sol:ChildContractDeploymentScript \
    --rpc-url http://localhost:<PORT> \
    --private-key <DEPLOYER_PRIVATE_KEY> \
    --broadcast
```

#### Initialize state
```bash
forge script scripts/deployment-scripts/initializeState.s.sol:InitializeStateScript \
    --rpc-url http://localhost:<PORT> \
    --private-key <DEPLOYER_PRIVATE_KEY> \
    --broadcast
```

#### Sync Child State to root
```bash
forge script scripts/deployment-scripts/syncChildStateToRoot.s.sol:SyncChildStateToRootScript \
    --rpc-url http://localhost:<PORT> \
    --private-key <DEPLOYER_PRIVATE_KEY> \
    --broadcast
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

## Contact

For more discussions, please head to the [R&D Discord](https://discord.gg/0xPolygonRnD)
