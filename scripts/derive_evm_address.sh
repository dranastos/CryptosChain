#!/bin/bash

# Script to derive EVM address from a Cosmos account's public key
# Usage:
#   ./scripts/derive_evm_address.sh <cosmos_address>  (queries chain)
#   ./scripts/derive_evm_address.sh --pubkey <base64_pubkey>  (direct derivation)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN_DIR="$(dirname "$SCRIPT_DIR")"

show_usage() {
    echo "Usage:"
    echo "  $0 <cosmos_address>              Query chain for pubkey and derive EVM address"
    echo "  $0 --pubkey <base64_pubkey>      Derive EVM address from base64 public key"
    echo "  $0 --from-keyring <key_name>     Get pubkey from local keyring"
    echo ""
    echo "Examples:"
    echo "  $0 cryptos1abc123..."
    echo "  $0 --pubkey 'Aw/YsHUNrlz0tGj+1FX5aMaWMBPM2rh6wmrzKBLi/OF4'"
    echo "  $0 --from-keyring treasury"
    echo ""
    echo "This script derives the EVM address from a Cosmos secp256k1 public key."
}

if [ -z "$1" ]; then
    show_usage
    exit 1
fi

PUBKEY_BASE64=""
COSMOS_ADDR=""

if [ "$1" == "--pubkey" ]; then
    if [ -z "$2" ]; then
        echo "Error: --pubkey requires a base64 public key argument"
        exit 1
    fi
    PUBKEY_BASE64="$2"
    COSMOS_ADDR="(provided pubkey)"
elif [ "$1" == "--from-keyring" ]; then
    if [ -z "$2" ]; then
        echo "Error: --from-keyring requires a key name argument"
        exit 1
    fi
    KEY_NAME="$2"
    echo "Getting public key for '$KEY_NAME' from keyring..."

    KEY_INFO=$(${CHAIN_DIR}/build/cryptosd keys show "$KEY_NAME" --keyring-backend test --output json 2>/dev/null || true)
    if [ -z "$KEY_INFO" ]; then
        echo "Error: Key '$KEY_NAME' not found in keyring"
        exit 1
    fi

    COSMOS_ADDR=$(echo "$KEY_INFO" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
    # The pubkey is nested JSON, so we need to extract it differently
    # Format: "pubkey":"{\"@type\":...,\"key\":\"BASE64\"}"
    PUBKEY_JSON=$(echo "$KEY_INFO" | sed 's/.*"pubkey":"//;s/"}$//' | sed 's/\\"/"/g')
    PUBKEY_BASE64=$(echo "$PUBKEY_JSON" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$PUBKEY_BASE64" ]; then
        echo "Error: Could not extract public key from keyring"
        exit 1
    fi

    echo "Found address: $COSMOS_ADDR"
else
    COSMOS_ADDR=$1

    echo "Querying account $COSMOS_ADDR..."

    # Query the account
    ACCOUNT_JSON=$(${CHAIN_DIR}/build/cryptosd query auth account "$COSMOS_ADDR" --output json 2>/dev/null || true)

    if [ -z "$ACCOUNT_JSON" ]; then
        echo "Error: Could not query account. Make sure the chain is running."
        echo ""
        echo "Alternative: Use --pubkey or --from-keyring if you have the public key locally"
        exit 1
    fi

    # Extract the base64 public key
    PUBKEY_BASE64=$(echo "$ACCOUNT_JSON" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$PUBKEY_BASE64" ]; then
    echo "Error: Account does not have a public key set."
    echo ""
    echo "The account needs to send at least one transaction to reveal its public key."
    echo "Alternatively, you can provide the public key manually if you have it from genesis."
    exit 1
fi

echo "Found public key (base64): $PUBKEY_BASE64"

# Decode base64 to hex
PUBKEY_HEX=$(echo "$PUBKEY_BASE64" | base64 -d | xxd -p | tr -d '\n')
echo "Public key (hex): $PUBKEY_HEX"

# Now derive the EVM address using a small Go program
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
        fmt.Println("Usage: derive_evm <hex_pubkey>")
        os.Exit(1)
    }

    pubkeyHex := os.Args[1]
    pubkeyBytes, err := hex.DecodeString(pubkeyHex)
    if err != nil {
        fmt.Printf("Error decoding hex: %v\n", err)
        os.Exit(1)
    }

    var evmAddr string

    if len(pubkeyBytes) == 33 {
        // Compressed public key
        pubkey, err := crypto.DecompressPubkey(pubkeyBytes)
        if err != nil {
            fmt.Printf("Error decompressing: %v\n", err)
            os.Exit(1)
        }
        evmAddr = crypto.PubkeyToAddress(*pubkey).Hex()
    } else if len(pubkeyBytes) == 65 {
        // Uncompressed with prefix
        pubkey, err := crypto.UnmarshalPubkey(pubkeyBytes)
        if err != nil {
            fmt.Printf("Error unmarshaling: %v\n", err)
            os.Exit(1)
        }
        evmAddr = crypto.PubkeyToAddress(*pubkey).Hex()
    } else {
        fmt.Printf("Unexpected key length: %d\n", len(pubkeyBytes))
        os.Exit(1)
    }

    fmt.Println(evmAddr)
}
GOEOF

# Run the Go program from within the chain directory to use go.mod
cd "$CHAIN_DIR"
EVM_ADDR=$(go run /tmp/derive_evm.go "$PUBKEY_HEX")

echo ""
echo "========================================"
echo "Cosmos Address: $COSMOS_ADDR"
echo "EVM Address:    $EVM_ADDR"
echo "========================================"
echo ""
echo "To add this to genesis address_associations in genesis.json:"
echo ""
echo "In the \"evm\" section, under \"address_associations\", add:"
echo "  \"$(echo $EVM_ADDR | tr '[:upper:]' '[:lower:]')\": \"$COSMOS_ADDR\""
echo ""

# Cleanup
rm -f /tmp/derive_evm.go
