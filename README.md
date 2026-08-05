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

Coverage is not part of CI — run it locally on demand:

```
npm run coverage
```

The report is written to `coverage/` (gitignored). Open `coverage/index.html` to browse.

## Verifying on-chain bytecode

`main` is meant to reproduce the exact runtime bytecode of what is deployed. This checks that it
still does: for every contract in `script/pinning/pinned-contracts.json` it builds from source and
compares against `eth_getCode` at the deployed address.

Requires `forge`, `cast`, `jq` and `python3`.

```
script/pinning/verify-bytecode.sh
```

Pass chain ids to narrow the run (`1` = Ethereum, `137` = Polygon PoS); the default is every chain:

```
script/pinning/verify-bytecode.sh 1
```

RPC endpoints come from the `rpc` map in the inventory, which points at the `foundry.toml` aliases —
override with `MAINNET_RPC_URL` / `POLYGON_POS_RPC_URL` if you need better rate limits.

### Reading the output

It prints a table and exits non-zero if anything is a real mismatch.

| Status | Meaning |
|---|---|
| `MATCH_NO_META` | **The expected pass.** Identical once the trailing metadata is stripped. |
| `MATCH` | Byte-identical including metadata. Rare — see below. |
| `MISMATCH` | Logic differs. Both stripped blobs are dumped to `verify-onchain/diffs/`. |
| `STALE_POINTER` | The live system no longer points at the address we pin — see below. |
| `POINTER_UNRESOLVED` | The liveness call could not be read at all. Usually a flaky RPC, **not** drift — retry before investigating. |
| `NO_CODE` / `MISSING_ARTIFACT` | Nothing deployed at the address / the local build produced no artifact. |

Only `MATCH` and `MATCH_NO_META` pass; every other status exits non-zero. Verifying zero contracts
(a typo'd chain argument, say) is also an error rather than a clean run.

`MATCH_NO_META` rather than `MATCH` is the normal result: solc appends a CBOR trailer that hashes the
source paths and compiler settings, so it is never reproducible and is stripped from both sides before
comparing. Everything before it must match byte for byte.

Artifacts, cached on-chain code, `results.json` and any diffs land in `verify-onchain/` (gitignored).

### The inventory

`script/pinning/pinned-contracts.json` is the source of truth; read its `_comment` for the full
schema. The fields that matter:

- `solc` — the compiler the contract was **deployed** with. Contracts are built one group at a time
  with `--use`, because a single auto-detected version does not reproduce all of them.
- `borChainId` — contracts embedding `ChainIdMixin` bake the chain id into their bytecode, and the
  live contracts do **not** all use the same value (some are `137`, some `15001`). The script
  re-renders the template per group, so no single build could cover them all.
- `upgradeable` — an implementation behind a proxy or Registry lookup. Not a strict pin, but verified
  informationally: the repo should still reproduce whatever is live today.
- `exclude` — documented but skipped, for contracts that legitimately cannot reproduce from current
  source. Do not add this to silence a regression.
- `liveness` — a `target` + `sig` call whose returned address must still equal the entry's own
  `address`. Bytecode at a fixed address is immutable, so comparing bytecode can never detect the
  system being re-pointed at a **different** address: after a proxy upgrade or a Registry
  re-registration the old address keeps its code and the check would stay green while `main` no
  longer mirrors what is live. That has already happened once — `Registry.erc20Predicate()` moved
  from `0x626fb210…` to `0x4EeA1780…`. Add it to anything reached through a pointer; a drift is
  reported as `STALE_POINTER` naming the address now returned, and the fix is to repoint the
  inventory and re-run to see whether the new implementation still reproduces.

Because those build inputs are load-bearing, a plain `forge build` will *silently* mismatch several
contracts. Any CI guard has to drive the build the same way this script does.

The script temporarily relaxes `IStakeManager`'s pragma so the 0.5.11-era proxies compile, and
re-renders `ChainIdMixin`; both are restored on exit, including the `test-bor-docker/genesis.json`
that template processing rewrites as a side effect.

## Contact

For more discussions, please head to the [R&D Discord](https://discord.gg/0xPolygonRnD)
