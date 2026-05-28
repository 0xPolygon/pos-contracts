#!/usr/bin/env sh

docker run --name bor-test --platform linux/amd64 -it -d -p 9545:9545 -v $(pwd):/bordata maticnetwork/bor:v0.2.8 /bin/sh -c "cd /bordata; sh start.sh"
