RPC="HTTP://127.0.0.1:7545"
PRIVATE_KEY="0xf302eead2bb0092c98a1d1b1292b4dbe05290256e6fdf51f5d598e41504eba4d"

forge script ./script/Deploy.sol:DeployScript --rpc-url="$RPC" --private-key="$PRIVATE_KEY" --broadcast
# forge script ./test/All.sol:DPOSDAOtest --rpc-url="$RPC" --private-key="$PRIVATE_KEY" --broadcast
