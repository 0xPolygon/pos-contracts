#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

# Executes cleanup function at script exit.
trap cleanup EXIT

# get current directory
PWD=$(pwd)

cleanup() {
  echo "Cleaning up"
  pkill -f anvil
  cd $PWD/test-bor-docker
  bash stop-docker.sh
  cd ..
  echo "Done"
}

start_testrpc() {
  npm run testrpc > /dev/null &
}

start_blockchain() {
  cd $PWD/test-bor-docker
  bash run-docker.sh
  cd ..
}

# Poll an RPC endpoint until eth_chainId succeeds or timeout is hit.
# Args: <name> <url> <timeout-seconds>
wait_for_rpc() {
  local name="$1"
  local url="$2"
  local timeout="$3"
  echo "Waiting up to ${timeout}s for $name RPC at $url..."
  local i=0
  while [[ "$i" -lt "$timeout" ]]; do
    if curl -sf -X POST -H 'content-type: application/json' \
         -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
         "$url" > /dev/null 2>&1; then
      echo "$name ready (took ${i}s)"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "$name did not become ready in ${timeout}s" >&2
  return 1
}


echo "Starting our own testrpc instance"
start_testrpc

echo "Starting our own geth instance"
start_blockchain

# Both anvil and bor boot asynchronously — block here until each one's RPC
# answers eth_chainId. Without this wait, the early tests (e.g. ChildErc20,
# DepositManager) hit "could not detect network" from ethers because the
# JsonRpcProvider in artifacts.js gets created before bor is serving.
wait_for_rpc anvil http://localhost:8545 30
wait_for_rpc bor http://localhost:9545 60

export LOCAL_NETWORK=true
npm run test:hardhat "$@"
