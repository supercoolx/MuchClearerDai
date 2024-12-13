RPC="https://data-seed-prebsc-1-s1.binance.org:8545/"
PRIVATE_KEY="a1305b4b65a88b7e435199410c5ef68f762f0fd0d9a2b6384253ab15a0d879a9"

forge script ./script/Deploy.sol:DeployScript --rpc-url="$RPC" --private-key="$PRIVATE_KEY" --broadcast
# forge script ./test/All.sol:DPOSDAOtest --rpc-url="$RPC" --private-key="$PRIVATE_KEY" --broadcast
