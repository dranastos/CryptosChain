#!/bin/bash

# Cryptos Chain Account Setup Script
# This script generates validator and treasury accounts
# Run this BEFORE initializing the chain

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CHAIN_HOME="${HOME}/.cryptos"
KEYRING_BACKEND="test"
BINARY="${PROJECT_ROOT}/build/cryptosd"

# Output file for account info
ACCOUNTS_FILE="${CHAIN_HOME}/accounts_info.json"

echo "============================================"
echo "  Cryptos Chain Account Setup"
echo "============================================"
echo ""

# Create keyring directory if it doesn't exist
mkdir -p "${CHAIN_HOME}"

# Check if accounts already exist
if ${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} > /dev/null 2>&1; then
    echo "WARNING: validator1 account already exists!"
    read -p "Do you want to delete and recreate? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        ${BINARY} keys delete validator1 --keyring-backend ${KEYRING_BACKEND} -y
    else
        echo "Skipping validator1 creation..."
    fi
fi

if ${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} > /dev/null 2>&1; then
    echo "WARNING: treasury account already exists!"
    read -p "Do you want to delete and recreate? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        ${BINARY} keys delete treasury --keyring-backend ${KEYRING_BACKEND} -y
    else
        echo "Skipping treasury creation..."
    fi
fi

echo ""
echo "Creating validator1 account..."
echo "============================================"
VALIDATOR_OUTPUT=$(${BINARY} keys add validator1 --keyring-backend ${KEYRING_BACKEND} 2>&1)
echo "${VALIDATOR_OUTPUT}"

# Extract validator address
VALIDATOR_ADDR=$(${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} -a)
echo ""
echo "Validator Address: ${VALIDATOR_ADDR}"

echo ""
echo "Creating treasury account..."
echo "============================================"
TREASURY_OUTPUT=$(${BINARY} keys add treasury --keyring-backend ${KEYRING_BACKEND} 2>&1)
echo "${TREASURY_OUTPUT}"

# Extract treasury address
TREASURY_ADDR=$(${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} -a)
echo ""
echo "Treasury Address: ${TREASURY_ADDR}"

echo ""
echo "============================================"
echo "  Account Summary"
echo "============================================"
echo ""
echo "VALIDATOR1:"
echo "  Address: ${VALIDATOR_ADDR}"
echo "  Balance: 1,100,000 CRYPTOS (1100000000000 ucryptos)"
echo ""
echo "TREASURY:"
echo "  Address: ${TREASURY_ADDR}"
echo "  Balance: 998,900,000 CRYPTOS (998900000000000000 ucryptos)"
echo ""
echo "Total Supply: 1,000,000,000 CRYPTOS (1 billion)"
echo ""

# Save account info to file
cat > "${ACCOUNTS_FILE}" << EOF
{
  "validator1": {
    "address": "${VALIDATOR_ADDR}",
    "balance_cryptos": "1100000",
    "balance_ucryptos": "1100000000000"
  },
  "treasury": {
    "address": "${TREASURY_ADDR}",
    "balance_cryptos": "998900000",
    "balance_ucryptos": "998900000000000000"
  },
  "total_supply": {
    "cryptos": "1000000000",
    "ucryptos": "1000000000000000000"
  }
}
EOF

echo "Account info saved to: ${ACCOUNTS_FILE}"
echo ""
echo "============================================"
echo "  IMPORTANT: Save your mnemonics above!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Save the mnemonic phrases shown above securely"
echo "  2. Run: ./scripts/initialize_validator.sh"
echo ""
