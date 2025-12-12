#!/bin/bash
#
# CRYPTOS CHAIN - NATIVE POINTER SETUP
# =====================================
# This script registers the ucryptos native token as an ERC20 pointer
# so that balances are visible and usable on both Cosmos and EVM sides.
#
# Prerequisites:
#   - Chain must be running
#   - Validator account must have funds for gas + deposit
#
# Usage: ./scripts/setup_native_pointer.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CHAIN_ID="cryptos-testnet-beta"
BINARY="${PROJECT_ROOT}/build/cryptosd"
KEYRING_BACKEND="test"

echo "============================================"
echo "  CRYPTOS - Native Pointer Setup"
echo "============================================"
echo ""

# Check if chain is running
if ! ${BINARY} status 2>/dev/null | grep -q "latest_block"; then
    echo "ERROR: Chain does not appear to be running."
    echo "Please start the chain first with: ${BINARY} start"
    exit 1
fi

echo "Chain is running. Checking current pointer status..."
echo ""

# Check if pointer already exists
POINTER_STATUS=$(${BINARY} query evm pointer NATIVE ucryptos 2>/dev/null || echo "error")
if echo "$POINTER_STATUS" | grep -q "exists: true"; then
    echo "Native pointer for ucryptos already exists!"
    echo "$POINTER_STATUS"
    exit 0
fi

echo "Native pointer does not exist. Creating via governance proposal..."
echo ""

# Submit the proposal
echo "Step 1: Submitting governance proposal..."
TX_RESULT=$(${BINARY} tx evm add-erc-native-pointer \
    "Register CRYPTOS Native Pointer" \
    "Register ERC20 pointer for ucryptos native token to enable unified EVM/Cosmos balances" \
    ucryptos \
    "Cryptos" \
    "CRYPTOS" \
    6 \
    10000000ucryptos \
    --from validator1 \
    --keyring-backend ${KEYRING_BACKEND} \
    --chain-id ${CHAIN_ID} \
    --gas auto \
    --gas-adjustment 1.5 \
    --fees 100000ucryptos \
    -y 2>&1)

echo "$TX_RESULT"
sleep 3

# Get proposal ID
PROPOSAL_ID=$(${BINARY} query gov proposals --output json 2>/dev/null | jq -r '.proposals[-1].proposal_id')
echo ""
echo "Proposal ID: ${PROPOSAL_ID}"

if [ -z "$PROPOSAL_ID" ] || [ "$PROPOSAL_ID" = "null" ]; then
    echo "ERROR: Failed to get proposal ID"
    exit 1
fi

# Vote YES
echo ""
echo "Step 2: Voting YES on proposal ${PROPOSAL_ID}..."
${BINARY} tx gov vote ${PROPOSAL_ID} yes \
    --from validator1 \
    --keyring-backend ${KEYRING_BACKEND} \
    --chain-id ${CHAIN_ID} \
    --gas auto \
    --gas-adjustment 1.5 \
    --fees 50000ucryptos \
    -y 2>&1

echo ""
echo "Step 3: Waiting for voting period to end (30 seconds)..."
echo ""

# Wait for voting period and check status
for i in {1..40}; do
    sleep 3
    STATUS=$(${BINARY} query gov proposal ${PROPOSAL_ID} --output json 2>/dev/null | jq -r '.status')
    echo "  Check $i: Status = $STATUS"

    if [ "$STATUS" = "PROPOSAL_STATUS_PASSED" ]; then
        echo ""
        echo "============================================"
        echo "  Proposal PASSED!"
        echo "============================================"
        break
    elif [ "$STATUS" = "PROPOSAL_STATUS_REJECTED" ]; then
        echo ""
        echo "ERROR: Proposal was rejected!"
        exit 1
    elif [ "$STATUS" = "PROPOSAL_STATUS_FAILED" ]; then
        echo ""
        echo "ERROR: Proposal failed!"
        exit 1
    fi
done

# Verify the pointer was created
echo ""
echo "Step 4: Verifying native pointer..."
sleep 2
POINTER_STATUS=$(${BINARY} query evm pointer NATIVE ucryptos 2>/dev/null)
echo "$POINTER_STATUS"

if echo "$POINTER_STATUS" | grep -q "exists: true"; then
    POINTER_ADDR=$(echo "$POINTER_STATUS" | grep "pointer:" | awk '{print $2}')
    echo ""
    echo "============================================"
    echo "  SUCCESS! Native Pointer Created"
    echo "============================================"
    echo ""
    echo "ERC20 Contract Address: ${POINTER_ADDR}"
    echo ""
    echo "You can now:"
    echo "  1. Query EVM balance via eth_getBalance"
    echo "  2. Use ucryptos in EVM transactions"
    echo "  3. Import the token in MetaMask using the contract address"
    echo ""
else
    echo ""
    echo "WARNING: Pointer may not have been created yet."
    echo "Please check again with: ${BINARY} query evm pointer NATIVE ucryptos"
fi
