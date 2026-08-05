#!/usr/bin/env bash
# Verify that the repo's sources still compile to exactly the bytecode deployed
# on-chain for every non-upgradeable (pinned) contract in pinned-contracts.json.
#
# Usage: script/pinning/verify-bytecode.sh [chainid ...]   (default: all chains)
#
# Each contract is compiled with the solc version it was originally deployed
# with (--use <ver>), into a separate out dir, then its deployedBytecode is
# compared against `cast code <address>`. See compare_bytecode.py for the
# comparison levels. Exit code 1 if any contract has a logic-level mismatch.
set -euo pipefail
cd "$(dirname "$0")/../.."

CONFIG=script/pinning/pinned-contracts.json
WORK=verify-onchain
ISTAKE=contracts/staking/stakeManager/IStakeManager.sol
mkdir -p "$WORK/build" "$WORK/onchain" "$WORK/liveness"

CHAINS=("$@")
if [ ${#CHAINS[@]} -eq 0 ]; then
  CHAINS=($(jq -r '.rpc | keys[]' "$CONFIG"))
fi

# Restore any temporary edits / regenerated templates on exit, no matter what.
# `process-templates.cjs` globs ALL **/*.template, so rendering ChainIdMixin also
# rewrites the tracked test-bor-docker/genesis.json (cosmetic reformat) — restore it.
cleanup() {
  git checkout -- "$ISTAKE" 2>/dev/null || true
  node tools/process-templates.cjs >/dev/null 2>&1 || true
  git checkout -- test-bor-docker/genesis.json 2>/dev/null || true
}
trap cleanup EXIT

# The 0.5.11-era proxies (Deposit/WithdrawManagerProxy) reach IStakeManager.sol,
# which is hard-pinned to `pragma solidity 0.5.17` and refuses to build under
# 0.5.11. Relax it to the floor pragma for the duration of the run (restored by
# the trap). This is a build-only concession, not a source change.
sed -i.bak 's/^pragma solidity 0.5.17;/pragma solidity ^0.5.2;/' "$ISTAKE" && rm -f "$ISTAKE.bak"

# 1. build each contract with its deploy-time solc version AND its pinned
#    bor-chain-id (ChainIdMixin is per-contract; default 137 for non-consumers).
#    Auto-detect would float solc to 0.5.17 and the template to its 15001 default.
: > "$WORK/build-failures.log"
for cid in $(jq -r '[.contracts[] | select(.exclude != true) | (.borChainId // "137")] | unique | .[]' "$CONFIG"); do
  echo "==> render ChainIdMixin with bor-chain-id $cid"
  node tools/process-templates.cjs -c "$cid" >/dev/null
  for pair in $(jq -r --arg cid "$cid" '[.contracts[] | select(.exclude != true) | select((.borChainId // "137") == $cid) | "\(.solc)|\(.file)"] | unique | .[]' "$CONFIG"); do
    v=${pair%%|*} f=${pair#*|}
    echo "==>   forge build --use $v $f"
    if FOUNDRY_OUT="$WORK/build/out-$v" forge build --use "$v" --force "$f" >/dev/null 2>"$WORK/.builderr"; then
      # --force cleans the out dir each build, so persist artifacts before the
      # next iteration wipes them. Key the cache by bor-chain-id as well as solc:
      # one source file can be deployed at two different chain ids, and without
      # $cid the later build silently overwrites the earlier one, leaving both
      # entries compared against the wrong artifact.
      mkdir -p "$WORK/artifacts/$cid/$v"
      cp -R "$WORK/build/out-$v/$(basename "$f")" "$WORK/artifacts/$cid/$v/"
    else
      echo "BUILD FAILED ($v, chainid $cid): $f" | tee -a "$WORK/build-failures.log"
      sed -n '1,6p' "$WORK/.builderr"
    fi
  done
done

# 2. fetch on-chain runtime code (cached per address)
for chain in "${CHAINS[@]}"; do
  rpc=$(jq -r --arg c "$chain" '.rpc[$c]' "$CONFIG")
  for addr in $(jq -r --arg c "$chain" '.contracts[] | select(.chain == $c) | select(.exclude != true) | .address' "$CONFIG"); do
    out="$WORK/onchain/${chain}_$(echo "$addr" | tr 'A-F' 'a-f').hex"
    if [ ! -s "$out" ]; then
      echo "==> cast code $addr (chain $chain)"
      cast code "$addr" --rpc-url "$rpc" > "$out"
    fi
  done
done

# 2b. resolve liveness pointers. Bytecode at a fixed address is immutable, so comparing it can
#     never catch the system being re-pointed at a DIFFERENT address — a proxy upgrade or a Registry
#     re-registration leaves the old address, and this check, perfectly green. That has already
#     happened once (Registry.erc20Predicate moved 0x626fb210... -> 0x4EeA1780...). So for entries
#     that are reached through a pointer, ask the live system what it points at now and require it
#     to still be the address we pin. NOT cached: this is the one value that can change.
for chain in "${CHAINS[@]}"; do
  rpc=$(jq -r --arg c "$chain" '.rpc[$c]' "$CONFIG")
  while IFS='|' read -r addr target sig; do
    [ -z "$addr" ] && continue
    out="$WORK/liveness/${chain}_$(echo "$addr" | tr 'A-F' 'a-f').addr"
    echo "==> cast call $target $sig (chain $chain)"
    cast call "$target" "$sig" --rpc-url "$rpc" >"$out" 2>/dev/null || echo "CALL_FAILED" >"$out"
  done < <(jq -r --arg c "$chain" '.contracts[]
             | select(.chain == $c) | select(.exclude != true) | select(.liveness)
             | "\(.address)|\(.liveness.target)|\(.liveness.sig)"' "$CONFIG")
done

# 3. compare
python3 script/pinning/compare_bytecode.py "$CONFIG" "$WORK" "${CHAINS[@]}"
