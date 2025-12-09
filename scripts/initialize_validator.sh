#!/bin/bash

# Cryptos Chain Validator Initialization Script
# Run this AFTER setup_accounts.sh

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CHAIN_ID="cryptos-testnet-beta"
CHAIN_HOME="${HOME}/.cryptos"
KEYRING_BACKEND="test"
BINARY="${PROJECT_ROOT}/build/cryptosd"
MONIKER="validator1"

# Token amounts (in ucryptos - 1 CRYPTOS = 1,000,000 ucryptos)
VALIDATOR_BALANCE="1100000000000"        # 1,100,000 CRYPTOS
TREASURY_BALANCE="998900000000000000"    # 998,900,000 CRYPTOS
VALIDATOR_STAKE="1000000000000"          # 1,000,000 CRYPTOS staked (leaving 100,000 for fees)

echo "============================================"
echo "  Cryptos Chain Validator Initialization"
echo "============================================"
echo ""

# Check if accounts exist
if ! ${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} > /dev/null 2>&1; then
    echo "ERROR: validator1 account not found!"
    echo "Please run ./scripts/setup_accounts.sh first"
    exit 1
fi

if ! ${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} > /dev/null 2>&1; then
    echo "ERROR: treasury account not found!"
    echo "Please run ./scripts/setup_accounts.sh first"
    exit 1
fi

# Get addresses
VALIDATOR_ADDR=$(${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} -a)
TREASURY_ADDR=$(${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} -a)

echo "Validator Address: ${VALIDATOR_ADDR}"
echo "Treasury Address: ${TREASURY_ADDR}"
echo ""

# Clean up existing chain data
echo "Cleaning up existing chain data..."
rm -rf "${CHAIN_HOME}/data"
rm -rf "${CHAIN_HOME}/config/genesis.json"
rm -rf "${CHAIN_HOME}/config/gentx"

# Initialize the chain
echo "Initializing chain..."
${BINARY} init ${MONIKER} --chain-id ${CHAIN_ID} > /dev/null 2>&1

echo "Adding genesis accounts..."
# Add validator account
${BINARY} add-genesis-account ${VALIDATOR_ADDR} ${VALIDATOR_BALANCE}ucryptos --keyring-backend ${KEYRING_BACKEND}

# Add treasury account
${BINARY} add-genesis-account ${TREASURY_ADDR} ${TREASURY_BALANCE}ucryptos --keyring-backend ${KEYRING_BACKEND}

echo "Generating gentx..."
${BINARY} gentx validator1 ${VALIDATOR_STAKE}ucryptos \
    --chain-id ${CHAIN_ID} \
    --keyring-backend ${KEYRING_BACKEND} \
    --moniker ${MONIKER}

echo "Collecting gentxs..."
${BINARY} collect-gentxs > /dev/null 2>&1

# Update genesis with proper consensus parameters
echo "Updating genesis configuration..."
GENESIS_FILE="${CHAIN_HOME}/config/genesis.json"

# CRITICAL: Add validator to genesis validators array (required for block production)
echo "Adding validator to genesis..."
KEY=$(jq '.pub_key' ${CHAIN_HOME}/config/priv_validator_key.json -c)
VALIDATOR_POWER=$(echo "${VALIDATOR_STAKE}" | sed 's/000000$//')  # Remove 6 zeros for power

cat ${GENESIS_FILE} | jq '.validators = [{}]' > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json ${GENESIS_FILE}
cat ${GENESIS_FILE} | jq '.validators[0] += {"power":"'${VALIDATOR_POWER}'"}' > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json ${GENESIS_FILE}
cat ${GENESIS_FILE} | jq '.validators[0] += {"pub_key":'${KEY}'}' > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json ${GENESIS_FILE}
cat ${GENESIS_FILE} | jq '.validators[0] += {"name":"'${MONIKER}'"}' > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json ${GENESIS_FILE}

# Set min_txs_in_block to 0 to allow empty blocks
cat ${GENESIS_FILE} | jq '.consensus_params.block.min_txs_in_block = "0"' > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json ${GENESIS_FILE}

# Verify the EVM address associations were created
echo ""
echo "Verifying EVM address associations..."
EVM_ASSOCIATIONS=$(cat ${GENESIS_FILE} | jq '.app_state.evm.address_associations')
echo "EVM Associations: ${EVM_ASSOCIATIONS}"

# Update config.toml for networking
CONFIG_FILE="${CHAIN_HOME}/config/config.toml"
echo ""
echo "Configuring network settings..."

# Set mode to validator
sed -i 's/mode = "full"/mode = "validator"/g' ${CONFIG_FILE}

# Listen on all interfaces for P2P
sed -i 's|laddr = "tcp://127.0.0.1:26656"|laddr = "tcp://0.0.0.0:26656"|g' ${CONFIG_FILE}

# Listen on all interfaces for RPC
sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' ${CONFIG_FILE}

# Update app.toml
APP_CONFIG="${CHAIN_HOME}/config/app.toml"
sed -i 's/minimum-gas-prices = "0.02usei"/minimum-gas-prices = "0.02ucryptos"/g' ${APP_CONFIG}

# Get node ID
NODE_ID=$(${BINARY} tendermint show-node-id)
IP_ADDR=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================"
echo "  Initialization Complete!"
echo "============================================"
echo ""
echo "Chain ID: ${CHAIN_ID}"
echo "Moniker: ${MONIKER}"
echo ""
echo "ACCOUNTS:"
echo "  Validator: ${VALIDATOR_ADDR}"
echo "    Balance: 1,100,000 CRYPTOS"
echo "    Staked:  1,000,000 CRYPTOS"
echo ""
echo "  Treasury: ${TREASURY_ADDR}"
echo "    Balance: 998,900,000 CRYPTOS"
echo ""
echo "TOTAL SUPPLY: 1,000,000,000 CRYPTOS"
echo ""
echo "NODE CONNECTION INFO:"
echo "  Node ID: ${NODE_ID}"
echo "  IP Address: ${IP_ADDR}"
echo "  P2P Port: 26656"
echo "  RPC Port: 26657"
echo ""
echo "  Persistent Peer: ${NODE_ID}@${IP_ADDR}:26656"
echo ""
echo "FILES:"
echo "  Genesis: ${GENESIS_FILE}"
echo "  Config: ${CONFIG_FILE}"
echo ""
echo "To start the validator, run:"
echo "  ${BINARY} start --chain-id ${CHAIN_ID}"
echo ""
