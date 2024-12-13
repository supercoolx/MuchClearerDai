CHAIN_ID=97
COMPILER_VERSION="v0.6.2+commit.bacdbe57"
BSCSCAN_API_KEY="878JTXKSN3GPS7XG5ICQEER99K6SWWKQX6"
CONTRACT_ADDRESS="0x733abd3c7829033b117d64f61534a291c6c70425"
CONTRACT_SOURCE="src/tokenAdapters.sol:ERC20Adapter"

forge verify-contract $CONTRACT_ADDRESS $CONTRACT_SOURCE --watch --etherscan-api-key $BSCSCAN_API_KEY --chain $CHAIN_ID --compiler-version $COMPILER_VERSION --constructor-args $(cast abi-encode "constructor(address,bytes32,address)" "0x0da8730a32c700791add740bf7a45585a27fff14" "0x92d6310469a67b269ee5e0d2a48c84207650ba161e2b36668e1ce951a5db69e5" "0x15aa649ba25bb2e0a51754bda5973c567abf1c05")
    # --chain-id $CHAIN_ID \
    # --num-of-optimizations 1000000 \
    # --watch \
    # --constructor-args $(cast abi-encode "constructor()" ) \
    # --etherscan-api-key $BSCSCAN_API_KEY \
    # --compiler-version v0.8.10+commit.fc410830 \