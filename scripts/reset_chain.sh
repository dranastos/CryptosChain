#!/bin/bash
#
# CRYPTOS CHAIN - COMPLETE RESET SCRIPT
# ======================================
# This script performs a complete chain reset:
#   1. Removes all existing chain data
#   2. Creates new treasury and validator accounts (WITH MNEMONICS SAVED!)
#   3. Uses the TEMPLATE genesis.json from the repo (preserves all custom settings)
#   4. Updates only dynamic parts (addresses, keys, genesis time)
#   5. Configures the validator for block production
#   6. Starts the chain
#
# IMPORTANT: Mnemonics are saved to ~/.cryptos/MNEMONICS_BACKUP.txt
#            KEEP THIS FILE SECURE!
#
# Usage: ./scripts/reset_chain.sh [--no-start]
#        --no-start: Initialize everything but don't start the chain
#

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Chain configuration
CHAIN_ID="cryptos-testnet-beta"
CHAIN_HOME="${HOME}/.cryptos"
KEYRING_BACKEND="test"
BINARY="${PROJECT_ROOT}/build/cryptosd"
MONIKER="validator1"

# Template genesis from repo (contains all custom settings: oracle, distribution, mint, etc.)
TEMPLATE_GENESIS="${PROJECT_ROOT}/genesis.json"

# Token amounts (in ucryptos - 1 CRYPTOS = 1,000,000 ucryptos)
VALIDATOR_BALANCE="1100000000000"        # 1,100,000 CRYPTOS (1.1 million)
TREASURY_BALANCE="998900000000000"       # 998,900,000 CRYPTOS (998.9 million)
VALIDATOR_STAKE="1000000000000"          # 1,000,000 CRYPTOS (1 million)

# Output files
MNEMONICS_FILE="${CHAIN_HOME}/MNEMONICS_BACKUP.txt"
ACCOUNTS_FILE="${CHAIN_HOME}/accounts_info.json"

# Parse arguments
START_CHAIN=true
for arg in "$@"; do
    case $arg in
        --no-start)
            START_CHAIN=false
            shift
            ;;
    esac
done

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo ""
    echo "============================================"
    echo "  $1"
    echo "============================================"
    echo ""
}

print_section() {
    echo ""
    echo "--- $1 ---"
}

check_binary() {
    if [ ! -f "${BINARY}" ]; then
        echo "ERROR: Binary not found at ${BINARY}"
        echo "Please run 'make build' first from the project root"
        exit 1
    fi
    echo "Binary found: ${BINARY}"
}

check_template_genesis() {
    if [ ! -f "${TEMPLATE_GENESIS}" ]; then
        echo "ERROR: Template genesis.json not found at ${TEMPLATE_GENESIS}"
        echo "This file contains all custom chain settings (oracle, distribution, mint, etc.)"
        exit 1
    fi
    echo "Template genesis found: ${TEMPLATE_GENESIS}"
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

print_header "CRYPTOS CHAIN - COMPLETE RESET"

echo "Configuration:"
echo "  Chain ID:        ${CHAIN_ID}"
echo "  Home Dir:        ${CHAIN_HOME}"
echo "  Moniker:         ${MONIKER}"
echo "  Binary:          ${BINARY}"
echo "  Template Genesis: ${TEMPLATE_GENESIS}"
echo ""

# Check prerequisites
check_binary
check_template_genesis

# =============================================================================
# STEP 1: COMPLETE CLEANUP
# =============================================================================

print_section "Step 1: Complete Cleanup"

if [ -d "${CHAIN_HOME}" ]; then
    echo "Removing existing chain directory: ${CHAIN_HOME}"
    rm -rf "${CHAIN_HOME}"
    echo "Cleanup complete."
else
    echo "No existing chain directory found."
fi

# Create fresh directory
mkdir -p "${CHAIN_HOME}"
echo "Created fresh chain directory."

# =============================================================================
# STEP 2: CREATE ACCOUNTS AND SAVE MNEMONICS
# =============================================================================

print_section "Step 2: Creating Accounts (SAVING MNEMONICS!)"

# Create the mnemonics backup file with proper permissions
touch "${MNEMONICS_FILE}"
chmod 600 "${MNEMONICS_FILE}"

# Write header to mnemonics file
cat > "${MNEMONICS_FILE}" << 'EOF'
================================================================================
                    CRYPTOS CHAIN - MNEMONIC BACKUP
================================================================================

                    !!! CRITICAL SECURITY WARNING !!!

  These are the recovery phrases for your blockchain accounts.
  Anyone with access to these phrases can control your funds.

  - Store this file in a SECURE location
  - Consider writing these down on paper
  - DELETE this file after backing up securely
  - NEVER share these mnemonics with anyone

================================================================================

EOF

echo "Creating VALIDATOR account..."
echo ""

# Create validator account and capture FULL output (mnemonic is on stderr)
VALIDATOR_OUTPUT=$(${BINARY} keys add validator1 --keyring-backend ${KEYRING_BACKEND} 2>&1)

# Display the output
echo "${VALIDATOR_OUTPUT}"

# Save to mnemonics file
cat >> "${MNEMONICS_FILE}" << EOF
--------------------------------------------------------------------------------
VALIDATOR ACCOUNT (validator1)
--------------------------------------------------------------------------------
Created: $(date)

${VALIDATOR_OUTPUT}

================================================================================

EOF

# Get validator address
VALIDATOR_ADDR=$(${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} -a)
echo ""
echo "Validator Address: ${VALIDATOR_ADDR}"

echo ""
echo "Creating TREASURY account..."
echo ""

# Create treasury account and capture FULL output
TREASURY_OUTPUT=$(${BINARY} keys add treasury --keyring-backend ${KEYRING_BACKEND} 2>&1)

# Display the output
echo "${TREASURY_OUTPUT}"

# Save to mnemonics file
cat >> "${MNEMONICS_FILE}" << EOF
--------------------------------------------------------------------------------
TREASURY ACCOUNT (treasury)
--------------------------------------------------------------------------------
Created: $(date)

${TREASURY_OUTPUT}

================================================================================
EOF

# Get treasury address
TREASURY_ADDR=$(${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} -a)
echo ""
echo "Treasury Address: ${TREASURY_ADDR}"

# Also extract and display just the mnemonics clearly
VALIDATOR_MNEMONIC=$(echo "${VALIDATOR_OUTPUT}" | tail -1)
TREASURY_MNEMONIC=$(echo "${TREASURY_OUTPUT}" | tail -1)

# =============================================================================
# STEP 2b: DERIVE EVM ADDRESSES FOR ADDRESS ASSOCIATIONS
# =============================================================================

print_section "Step 2b: Deriving EVM Addresses"

# Function to derive EVM address from base64 public key
derive_evm_address() {
    local PUBKEY_BASE64="$1"

    # Create a temporary Go program to derive the EVM address
    cat > /tmp/derive_evm.go << 'GOEOF'
package main

import (
    "encoding/hex"
    "fmt"
    "os"

    "github.com/ethereum/go-ethereum/crypto"
)

func main() {
    if len(os.Args) < 2 {
        os.Exit(1)
    }
    pubkeyHex := os.Args[1]
    pubkeyBytes, err := hex.DecodeString(pubkeyHex)
    if err != nil {
        os.Exit(1)
    }
    if len(pubkeyBytes) == 33 {
        pubkey, err := crypto.DecompressPubkey(pubkeyBytes)
        if err != nil {
            os.Exit(1)
        }
        fmt.Println(crypto.PubkeyToAddress(*pubkey).Hex())
    }
}
GOEOF

    # Decode base64 to hex
    local PUBKEY_HEX=$(echo "$PUBKEY_BASE64" | base64 -d | xxd -p | tr -d '\n')

    # Run the Go program from project root to use go.mod
    cd "$PROJECT_ROOT"
    go run /tmp/derive_evm.go "$PUBKEY_HEX" 2>/dev/null
}

# Get validator public key (base64) from keyring
VALIDATOR_KEY_INFO=$(${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} --output json)
VALIDATOR_PUBKEY_JSON=$(echo "$VALIDATOR_KEY_INFO" | sed 's/.*"pubkey":"//;s/"}$//' | sed 's/\\"/"/g')
VALIDATOR_PUBKEY_BASE64=$(echo "$VALIDATOR_PUBKEY_JSON" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

# Get treasury public key (base64) from keyring
TREASURY_KEY_INFO=$(${BINARY} keys show treasury --keyring-backend ${KEYRING_BACKEND} --output json)
TREASURY_PUBKEY_JSON=$(echo "$TREASURY_KEY_INFO" | sed 's/.*"pubkey":"//;s/"}$//' | sed 's/\\"/"/g')
TREASURY_PUBKEY_BASE64=$(echo "$TREASURY_PUBKEY_JSON" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

echo "Validator pubkey (base64): ${VALIDATOR_PUBKEY_BASE64}"
echo "Treasury pubkey (base64): ${TREASURY_PUBKEY_BASE64}"

# Derive EVM addresses
VALIDATOR_EVM_ADDR=$(derive_evm_address "$VALIDATOR_PUBKEY_BASE64")
TREASURY_EVM_ADDR=$(derive_evm_address "$TREASURY_PUBKEY_BASE64")

# Convert to lowercase for consistency
VALIDATOR_EVM_ADDR_LOWER=$(echo "$VALIDATOR_EVM_ADDR" | tr '[:upper:]' '[:lower:]')
TREASURY_EVM_ADDR_LOWER=$(echo "$TREASURY_EVM_ADDR" | tr '[:upper:]' '[:lower:]')

echo ""
echo "Validator EVM Address: ${VALIDATOR_EVM_ADDR}"
echo "Treasury EVM Address:  ${TREASURY_EVM_ADDR}"

# Clean up
rm -f /tmp/derive_evm.go

# =============================================================================
# STEP 3: INITIALIZE CHAIN (creates config directory structure)
# =============================================================================

print_section "Step 3: Initializing Chain Structure"

echo "Running: ${BINARY} init ${MONIKER} --chain-id ${CHAIN_ID}"
${BINARY} init ${MONIKER} --chain-id ${CHAIN_ID} > /dev/null 2>&1
echo "Chain structure initialized."

# =============================================================================
# STEP 4: COPY TEMPLATE GENESIS AND UPDATE DYNAMIC PARTS
# =============================================================================

print_section "Step 4: Applying Template Genesis with Custom Settings"

GENESIS_FILE="${CHAIN_HOME}/config/genesis.json"

echo "Copying template genesis (preserves oracle, distribution, mint, slashing settings)..."
cp "${TEMPLATE_GENESIS}" "${GENESIS_FILE}"

# Get the validator's public key for gentx
VALIDATOR_PUBKEY=$(${BINARY} keys show validator1 --keyring-backend ${KEYRING_BACKEND} --pubkey)
echo "Validator PubKey: ${VALIDATOR_PUBKEY}"

# Update genesis with new account addresses and balances
echo "Updating account addresses and balances..."

# Create the balances array with new addresses
jq --arg validator_addr "$VALIDATOR_ADDR" \
   --arg treasury_addr "$TREASURY_ADDR" \
   --arg validator_balance "$VALIDATOR_BALANCE" \
   --arg treasury_balance "$TREASURY_BALANCE" \
   '.app_state.bank.balances = [
     {
       "address": $validator_addr,
       "coins": [{"denom": "ucryptos", "amount": $validator_balance}]
     },
     {
       "address": $treasury_addr,
       "coins": [{"denom": "ucryptos", "amount": $treasury_balance}]
     }
   ]' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Update auth accounts
echo "Updating auth accounts..."
jq --arg validator_addr "$VALIDATOR_ADDR" \
   --arg treasury_addr "$TREASURY_ADDR" \
   '.app_state.auth.accounts = [
     {
       "@type": "/cosmos.auth.v1beta1.BaseAccount",
       "address": $validator_addr,
       "pub_key": null,
       "account_number": "0",
       "sequence": "0"
     },
     {
       "@type": "/cosmos.auth.v1beta1.BaseAccount",
       "address": $treasury_addr,
       "pub_key": null,
       "account_number": "1",
       "sequence": "0"
     }
   ]' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Update genesis time
GENESIS_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000000000Z")
echo "Setting genesis time: ${GENESIS_TIME}"
jq --arg genesis_time "$GENESIS_TIME" \
   '.genesis_time = $genesis_time' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Update chain ID
jq --arg chain_id "$CHAIN_ID" \
   '.chain_id = $chain_id' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Clear oracle whitelist (no price feeds needed at genesis)
echo "Clearing oracle whitelist..."
jq '.app_state.oracle.params.whitelist = []' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Add EVM address associations (array of objects with sei_address and eth_address)
echo "Adding EVM address associations..."
jq --arg validator_evm "$VALIDATOR_EVM_ADDR" \
   --arg validator_cosmos "$VALIDATOR_ADDR" \
   --arg treasury_evm "$TREASURY_EVM_ADDR" \
   --arg treasury_cosmos "$TREASURY_ADDR" \
   '.app_state.evm.address_associations = [
     {
       "sei_address": $validator_cosmos,
       "eth_address": $validator_evm
     },
     {
       "sei_address": $treasury_cosmos,
       "eth_address": $treasury_evm
     }
   ]' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

echo "EVM address associations added:"
echo "  ${VALIDATOR_EVM_ADDR_LOWER} -> ${VALIDATOR_ADDR}"
echo "  ${TREASURY_EVM_ADDR_LOWER} -> ${TREASURY_ADDR}"

echo "Template genesis applied with new addresses."

# =============================================================================
# STEP 5: GENERATE VALIDATOR TRANSACTION
# =============================================================================

print_section "Step 5: Generating Validator Transaction (gentx)"

echo "Creating gentx with stake of ${VALIDATOR_STAKE} ucryptos..."
${BINARY} gentx validator1 ${VALIDATOR_STAKE}ucryptos \
    --chain-id ${CHAIN_ID} \
    --keyring-backend ${KEYRING_BACKEND} \
    --moniker ${MONIKER}

echo "Collecting gentxs..."
${BINARY} collect-gentxs > /dev/null 2>&1
echo "Gentx collected."

# =============================================================================
# STEP 6: ADD VALIDATOR TO GENESIS (CRITICAL FOR BLOCK PRODUCTION!)
# =============================================================================

print_section "Step 6: Adding Validator to Genesis (Critical!)"

# Extract validator public key from priv_validator_key.json
KEY=$(jq '.pub_key' ${CHAIN_HOME}/config/priv_validator_key.json -c)
echo "Validator Public Key: ${KEY}"

# Calculate voting power (stake amount / 1,000,000)
VALIDATOR_POWER=$(echo "${VALIDATOR_STAKE}" | sed 's/000000$//')
echo "Validator Power: ${VALIDATOR_POWER}"

# Add validator to genesis.json validators array
echo "Adding validator to genesis validators array..."

jq --arg power "$VALIDATOR_POWER" \
   --arg name "$MONIKER" \
   --argjson pub_key "$KEY" \
   '.validators = [{
     "power": $power,
     "pub_key": $pub_key,
     "name": $name
   }]' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

# Ensure min_txs_in_block is 0 (allows empty blocks for single validator)
jq '.consensus_params.block.min_txs_in_block = "0"' "${GENESIS_FILE}" > /tmp/genesis_tmp.json && mv /tmp/genesis_tmp.json "${GENESIS_FILE}"

echo "Validator added to genesis."

# Verify validator was added
echo ""
echo "Verifying validator in genesis..."
jq '.validators' ${GENESIS_FILE}

# =============================================================================
# STEP 7: CONFIGURE NETWORK SETTINGS
# =============================================================================

print_section "Step 7: Configuring Network Settings"

CONFIG_FILE="${CHAIN_HOME}/config/config.toml"
APP_CONFIG="${CHAIN_HOME}/config/app.toml"

# Set mode to validator
sed -i 's/mode = "full"/mode = "validator"/g' ${CONFIG_FILE}
echo "Set mode to validator"

# Listen on all interfaces for P2P
sed -i 's|laddr = "tcp://127.0.0.1:26656"|laddr = "tcp://0.0.0.0:26656"|g' ${CONFIG_FILE}
echo "Configured P2P to listen on 0.0.0.0:26656"

# Listen on all interfaces for RPC
sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' ${CONFIG_FILE}
echo "Configured RPC to listen on 0.0.0.0:26657"

# Fix minimum gas prices (ensure it uses ucryptos, not usei)
sed -i 's/minimum-gas-prices = "0.02usei"/minimum-gas-prices = "0.02ucryptos"/g' ${APP_CONFIG}
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.02ucryptos"/g' ${APP_CONFIG}
echo "Set minimum gas prices to 0.02ucryptos"

echo "Network configuration complete."

# =============================================================================
# STEP 8: SAVE ACCOUNT INFORMATION
# =============================================================================

print_section "Step 8: Saving Account Information"

# Get node ID
NODE_ID=$(${BINARY} tendermint show-node-id)
IP_ADDR=$(hostname -I | awk '{print $1}')

# Create JSON accounts file
cat > "${ACCOUNTS_FILE}" << EOF
{
  "chain_id": "${CHAIN_ID}",
  "created_at": "$(date -Iseconds)",
  "validator1": {
    "name": "validator1",
    "address": "${VALIDATOR_ADDR}",
    "evm_address": "${VALIDATOR_EVM_ADDR}",
    "balance_cryptos": "1100000",
    "balance_ucryptos": "${VALIDATOR_BALANCE}",
    "staked_ucryptos": "${VALIDATOR_STAKE}"
  },
  "treasury": {
    "name": "treasury",
    "address": "${TREASURY_ADDR}",
    "evm_address": "${TREASURY_EVM_ADDR}",
    "balance_cryptos": "998900000",
    "balance_ucryptos": "${TREASURY_BALANCE}"
  },
  "total_supply": {
    "cryptos": "1000000000",
    "ucryptos": "1000000000000000"
  },
  "node": {
    "id": "${NODE_ID}",
    "ip": "${IP_ADDR}",
    "p2p_port": "26656",
    "rpc_port": "26657",
    "persistent_peer": "${NODE_ID}@${IP_ADDR}:26656"
  }
}
EOF

echo "Account info saved to: ${ACCOUNTS_FILE}"

# =============================================================================
# STEP 9: VERIFY CUSTOM SETTINGS PRESERVED
# =============================================================================

print_section "Step 9: Verifying Custom Settings Preserved"

echo "Distribution (community_tax = 10% for treasury):"
jq '.app_state.distribution.params.community_tax' ${GENESIS_FILE}

echo ""
echo "Mint (token_release_schedule - 5% inflation for 20 years):"
jq '.app_state.mint.params.token_release_schedule | length' ${GENESIS_FILE}
echo "releases configured"

echo ""
echo "Oracle (slash_fraction = 0 - disabled, whitelist = empty):"
jq '.app_state.oracle.params | {slash_fraction, whitelist}' ${GENESIS_FILE}

echo ""
echo "Slashing (all penalties = 0 - disabled):"
jq '.app_state.slashing.params | {slash_fraction_double_sign, slash_fraction_downtime}' ${GENESIS_FILE}

echo ""
echo "EVM Address Associations:"
jq '.app_state.evm.address_associations' ${GENESIS_FILE}

# =============================================================================
# FINAL SUMMARY
# =============================================================================

print_header "INITIALIZATION COMPLETE!"

echo "CHAIN CONFIGURATION:"
echo "  Chain ID:     ${CHAIN_ID}"
echo "  Moniker:      ${MONIKER}"
echo ""
echo "ACCOUNTS:"
echo "  Validator:    ${VALIDATOR_ADDR}"
echo "    EVM:        ${VALIDATOR_EVM_ADDR}"
echo "    Balance:    1,100,000 CRYPTOS"
echo "    Staked:     1,000,000 CRYPTOS"
echo ""
echo "  Treasury:     ${TREASURY_ADDR}"
echo "    EVM:        ${TREASURY_EVM_ADDR}"
echo "    Balance:    998,900,000 CRYPTOS"
echo ""
echo "TOTAL SUPPLY:   1,000,000,000 CRYPTOS"
echo ""
echo "CUSTOM SETTINGS PRESERVED:"
echo "  - Distribution: 10% to treasury"
echo "  - Inflation: 5% annually (20 years)"
echo "  - Oracle: Disabled (slash_fraction=0, whitelist=empty)"
echo "  - Slashing: All penalties disabled"
echo "  - EVM: Address associations pre-configured"
echo ""
echo "NODE INFO:"
echo "  Node ID:      ${NODE_ID}"
echo "  IP Address:   ${IP_ADDR}"
echo "  P2P:          tcp://${IP_ADDR}:26656"
echo "  RPC:          tcp://${IP_ADDR}:26657"
echo ""
echo "IMPORTANT FILES:"
echo "  Genesis:      ${GENESIS_FILE}"
echo "  Config:       ${CONFIG_FILE}"
echo "  App Config:   ${APP_CONFIG}"
echo "  Accounts:     ${ACCOUNTS_FILE}"
echo ""

print_header "!!! MNEMONICS SAVED !!!"
echo "BACKUP FILE: ${MNEMONICS_FILE}"
echo ""
echo "The mnemonics for both accounts have been saved to the file above."
echo "PLEASE BACK THIS UP SECURELY AND THEN DELETE IT!"
echo ""

# Display mnemonics one more time clearly
echo "============================================"
echo "  VALIDATOR MNEMONIC (24 words):"
echo "============================================"
echo "${VALIDATOR_MNEMONIC}"
echo ""
echo "============================================"
echo "  TREASURY MNEMONIC (24 words):"
echo "============================================"
echo "${TREASURY_MNEMONIC}"
echo ""

# =============================================================================
# START CHAIN (if requested)
# =============================================================================

if [ "$START_CHAIN" = true ]; then
    print_header "Starting Chain..."
    echo "Command: ${BINARY} start --chain-id ${CHAIN_ID}"
    echo ""
    echo "Press Ctrl+C to stop the chain."
    echo ""

    # Start the chain
    ${BINARY} start --chain-id ${CHAIN_ID}
else
    print_header "Chain Ready to Start"
    echo "Run the following command to start the chain:"
    echo ""
    echo "  ${BINARY} start --chain-id ${CHAIN_ID}"
    echo ""
    echo "Or:"
    echo ""
    echo "  cd ${PROJECT_ROOT} && ./build/cryptosd start --chain-id ${CHAIN_ID}"
    echo ""
fi
