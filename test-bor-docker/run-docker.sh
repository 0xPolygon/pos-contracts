#!/usr/bin/env sh

# The bor v2 image has ENTRYPOINT ["bor"], so the CMD arguments below are
# passed directly to bor — no shell wrapper / start.sh indirection needed.
# v2 differences from the legacy invocation:
#   - single `bor server` invocation (no separate `init` step; -chain handles it)
#   - `-miner.etherbase` must be explicit (v1 implicitly used the first unlocked account)
#   - `-bor.devfakeauthor` required to mine without a validator set
docker run --name bor-test --platform linux/amd64 -it -d -p 9545:9545 \
  -v "$(pwd):/bordata" \
  ghcr.io/0xpolygon/bor:latest \
  server \
  -chain /bordata/genesis.json \
  -datadir /bordata/data \
  -port 30303 \
  -http -http.addr '0.0.0.0' -http.vhosts '*' -http.corsdomain '*' \
  -http.port 9545 \
  -http.api 'personal,db,eth,net,web3,txpool,miner,admin,bor' \
  -keystore /bordata/keystore \
  -unlock '0x9fb29aac15b9a4b7f17c3385939b007540f4d791,0x96C42C56fdb78294F96B0cFa33c92bed7D75F96a' \
  -password /bordata/password.txt \
  -allow-insecure-unlock \
  -disable-bor-wallet=false \
  -miner.etherbase '0x9fb29aac15b9a4b7f17c3385939b007540f4d791' \
  -miner.gaslimit '20000000' \
  -bor.withoutheimdall \
  -bor.devfakeauthor \
  -mine
