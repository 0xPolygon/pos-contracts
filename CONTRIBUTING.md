# Contributing

- [Setup](#setup)
- [Pre-commit Hooks](#pre-commit-hooks)
- [Branching](#branching)
  - [Main](#main)
  - [Dev](#dev)
  - [Feature](#feature)
  - [Fix](#fix)
- [Code Practices](#code-practices)
  - [Code Style](#code-style)
  - [Interfaces](#interfaces)
  - [NatSpec \& Comments](#natspec--comments)
- [Versioning](#versioning)
- [Testing](#testing)
- [Deployment](#deployment)
- [Releases](#releases)

## Setup

See the [README](README.md#development) for local environment setup (foundry, npm dependencies, interface generation, build). In addition, contributors should install pre-commit:

- [Install pre-commit](https://pre-commit.com/#installation)
- Enable the hooks: `pre-commit install`

## Pre-commit Hooks

Follow the [setup steps](#setup) to enable pre-commit hooks. To ensure consistency in our formatting `pre-commit` is used to check whether code was formatted properly and the documentation is up to date. Whenever a commit does not meet the checks implemented by pre-commit, the commit will fail and the pre-commit checks will modify the files to make the commits pass. Include these changes in your commit for the next commit attempt to succeed. On pull requests the CI checks whether all pre-commit hooks were run correctly.
This repo includes the following pre-commit hooks that are defined in the `.pre-commit-config.yaml`:

- `mixed-line-ending`: This hook ensures that all files have the same line endings (LF).
- `format`: This hook uses `forge fmt` to format all Solidity files.
- `prettier`: All remaining files are formatted using prettier.

## Branching

This section outlines the branching strategy of this repo.

### Main

The main branch reflects the deployed state on all networks. Any pull requests into this branch MUST come from the dev branch. The main branch is protected and requires a separate code review by the security team. Whenever the main branch is updated, a new release is created with the latest version. For more information on versioning, check [here](#versioning).

### Dev

This is the active development branch. All pull requests into this branch MUST come from fix or feature branches. Once code is complete and audited, dev is merged into main for release.

### Feature

Any new feature should be developed on a separate branch. The naming convention for these branches is `feat/*`. Once the feature is complete, a pull request into the dev branch can be created.

### Fix

Any bug fixes should be developed on a separate branch. The naming convention for these branches is `fix/*`. Once the fix is complete, a pull request into the dev branch can be created.

## Code Practices

### Code Style

The repo follows the official [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html). In addition to that, this repo also borrows the following rules from [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/GUIDELINES.md#solidity-conventions):

- Internal or private state variables or functions should have an underscore prefix.

  ```solidity
  contract TestContract {
      uint256 private _privateVar;
      uint256 internal _internalVar;
      function _testInternal() internal { ... }
      function _testPrivate() private { ... }
  }
  ```

- Events should generally be emitted immediately after the state change that they
  represent, and should be named in the past tense. Some exceptions may be made for gas
  efficiency if the result doesn't affect observable ordering of events.

  ```solidity
  function _burn(address who, uint256 value) internal {
      super._burn(who, value);
      emit TokensBurned(who, value);
  }
  ```

- Interface names should have a capital I prefix.

  ```solidity
  interface IERC777 {
  ```

- Contracts not intended to be used standalone should be marked abstract
  so they are required to be inherited to other contracts.

  ```solidity
  abstract contract AccessControl is ..., {
  ```

- Unchecked arithmetic blocks should contain comments explaining why overflow is guaranteed not to happen. If the reason is immediately apparent from the line above the unchecked block, the comment may be omitted.

### Interfaces

Every contract MUST implement their corresponding interface that includes all externally callable functions, errors and events.

### NatSpec & Comments

Interfaces should be the entrypoint for all contracts. When exploring the a contract within the repository, the interface MUST contain all relevant information to understand the functionality of the contract in the form of NatSpec comments. This includes all externally callable functions, errors and events. The NatSpec documentation MUST be added to the functions, errors and events within the interface. This allows a reader to understand the functionality of a function before moving on to the implementation. The implementing functions MUST point to the NatSpec documentation in the interface using `@inheritdoc`. Internal and private functions shouldn't have NatSpec documentation except for `@dev` comments, whenever more context is needed. Additional comments within a function should only be used to give more context to more complex operations, otherwise the code should be kept readable and self-explanatory.

## Versioning

This repo utilizes [semantic versioning](https://semver.org/) for smart contracts. When contracts are modified, only the version of the changed contracts should be updated — unmodified contracts remain on the version of their last change.

## Testing

See the [README](README.md#testing) for the test workflow (forge tests, hardhat tests, coverage, local bor chain).

## Deployment

Forge scripts live under `script/`, organised as:

- `script/setup/` — system deployment / scaffolding
- `script/upgrades/` — proxy implementation swaps and new deployments
- `script/updates/` — governance setting/config updates

Pre-configured RPCs in `foundry.toml` (all use Tenderly's public gateways — no API key required, rate-limited):

- `anvil` — local (127.0.0.1:8545)
- `mainnet` — Ethereum Mainnet
- `sepolia` — Ethereum Sepolia
- `polygon_pos` — Polygon PoS
- `polygon_amoy` — Polygon Amoy testnet

Select a network with `--rpc-url <name>`. To override a default with a private endpoint (higher limits, or a Tenderly access-token URL), set the per-chain env var Foundry honours — e.g. `MAINNET_RPC_URL`, `POLYGON_POS_RPC_URL`. Add `--broadcast` to send transactions, and `--verify` to verify on Etherscan (requires `ETHERSCAN_API_KEY` for Ethereum networks and `POLYGONSCAN_API_KEY` for Polygon networks in `.env`). If verification times out, re-run with `--resume` instead of `--broadcast`.


## Releases

Releases should be created whenever the code on the main branch is updated to reflect a deployment or an upgrade on a network. The release should be named after the version of the contracts deployed or upgraded.
The release should include the following:

- In case of a MAJOR version
  - changelog
  - summary of breaking changes
  - summary of new features
  - summary of fixes
- In case of a MINOR version
  - changelog
  - summary of new features
  - summary of fixes
- In case of a PATCH version
  - changelog
  - summary of fixes
- Deployment information (can be copied from the generated log files)
  - Addresses of the deployed contracts
