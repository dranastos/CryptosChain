package app

import (
	"github.com/btcsuite/btcd/btcec/v2"
	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	"github.com/sei-protocol/sei-chain/utils/helpers"
	evmkeeper "github.com/sei-protocol/sei-chain/x/evm/keeper"
)

// CreateEVMAssociationHook creates a hook function that automatically associates
// Cosmos addresses with their corresponding EVM addresses when a public key is set.
// This ensures that balances are always visible on both Cosmos and EVM sides without
// requiring manual association transactions.
func CreateEVMAssociationHook(evmKeeper *evmkeeper.Keeper) func(ctx sdk.Context, acc authtypes.AccountI) {
	return func(ctx sdk.Context, acc authtypes.AccountI) {
		// Skip if no pubkey
		pubKey := acc.GetPubKey()
		if pubKey == nil {
			return
		}

		seiAddr := acc.GetAddress()

		// Skip if already associated
		if _, associated := evmKeeper.GetEVMAddress(ctx, seiAddr); associated {
			return
		}

		// Try to parse the pubkey and derive the EVM address
		pk, err := btcec.ParsePubKey(pubKey.Bytes())
		if err != nil {
			// Not a secp256k1 key (e.g., multisig, ed25519), skip
			return
		}

		// Derive the EVM address from the uncompressed public key
		evmAddr, err := helpers.PubkeyToEVMAddress(pk.SerializeUncompressed())
		if err != nil {
			ctx.Logger().Error("EVM association hook: failed to derive EVM address",
				"address", seiAddr.String(), "error", err)
			return
		}

		// Create the association
		evmKeeper.SetAddressMapping(ctx, seiAddr, evmAddr)

		ctx.Logger().Info("EVM association hook: auto-associated addresses",
			"sei_address", seiAddr.String(),
			"evm_address", evmAddr.Hex())
	}
}
