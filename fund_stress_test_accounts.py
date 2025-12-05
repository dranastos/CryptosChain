#!/usr/bin/env python3
"""
Fund stress test accounts with ETH for transaction fees
"""

import json
import time
from web3 import Web3
from eth_account import Account

# Configuration
FUNDER_PRIVATE_KEY = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
RPC_URL = "http://127.0.0.1:8545"  # Local Sei node
AMOUNT_PER_ACCOUNT = 0.1  # ETH per account for gas fees
NUM_ACCOUNTS = 50  # Must match stress test configuration

# Connect to Web3
w3 = Web3(Web3.HTTPProvider(RPC_URL))

# Create funder account from private key
funder = Account.from_key(FUNDER_PRIVATE_KEY)
funder_address = funder.address

print(f"Funder address: {funder_address}")

# Check connection
if not w3.is_connected():
    print("Failed to connect to Sei node!")
    exit(1)

print(f"Connected to Sei node at {RPC_URL}")
print(f"Chain ID: {w3.eth.chain_id}")

# Generate the same test accounts as stress test
def generate_accounts(num_accounts):
    """Generate test accounts with private keys (same as stress test)"""
    accounts = []
    for i in range(num_accounts):
        acct = Account.create()
        accounts.append({
            'address': acct.address,
            'private_key': acct.key.hex()
        })
    return accounts

def fund_account(to_address, amount_eth, nonce):
    """Send ETH to a test account"""
    try:
        # Convert ETH to Wei
        amount_wei = w3.to_wei(amount_eth, 'ether')
        
        # Build transaction
        transaction = {
            'nonce': nonce,
            'to': to_address,
            'value': amount_wei,
            'gas': 21000,
            'gasPrice': w3.to_wei('10', 'gwei'),
            'chainId': w3.eth.chain_id
        }
        
        # Sign transaction
        signed_txn = funder.sign_transaction(transaction)
        
        # Send transaction
        tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
        
        print(f"Funded {to_address[:10]}... with {amount_eth} ETH - tx: {tx_hash.hex()[:16]}...")
        
        return tx_hash
        
    except Exception as e:
        print(f"Error funding {to_address}: {str(e)}")
        return None

def main():
    """Main funding function"""
    # Check funder balance
    balance = w3.eth.get_balance(funder_address)
    balance_eth = w3.from_wei(balance, 'ether')
    print(f"Funder balance: {balance_eth} ETH")
    
    # Generate test accounts (these need to match the stress test accounts)
    test_accounts = generate_accounts(NUM_ACCOUNTS)
    
    # Save account details for reference
    with open('stress_test_accounts.json', 'w') as f:
        json.dump(test_accounts, f, indent=2)
    print(f"\nSaved {len(test_accounts)} test accounts to stress_test_accounts.json")
    
    # Calculate total required
    total_required = len(test_accounts) * AMOUNT_PER_ACCOUNT
    gas_buffer = 0.01 * len(test_accounts)  # Gas for funding transactions
    total_with_gas = total_required + gas_buffer
    
    print(f"\nFunding requirements:")
    print(f"  Accounts to fund: {len(test_accounts)}")
    print(f"  ETH per account: {AMOUNT_PER_ACCOUNT}")
    print(f"  Total ETH needed: {total_required}")
    print(f"  Plus gas buffer: {gas_buffer}")
    print(f"  Total required: {total_with_gas}")
    
    if balance_eth < total_with_gas:
        print(f"\nERROR: Insufficient balance!")
        print(f"Have: {balance_eth} ETH, Need: {total_with_gas} ETH")
        return
    
    # Get starting nonce
    nonce = w3.eth.get_transaction_count(funder_address)
    
    # Fund each account
    print(f"\nFunding {len(test_accounts)} accounts...")
    successful = 0
    failed = 0
    tx_hashes = []
    
    for i, account in enumerate(test_accounts):
        tx_hash = fund_account(account['address'], AMOUNT_PER_ACCOUNT, nonce + i)
        if tx_hash:
            successful += 1
            tx_hashes.append(tx_hash)
        else:
            failed += 1
        
        # Progress update
        if (i + 1) % 10 == 0:
            print(f"Progress: {i + 1}/{len(test_accounts)} accounts funded")
    
    print(f"\n{'='*60}")
    print(f"Funding complete!")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    
    # Wait for confirmations
    if tx_hashes:
        print(f"\nWaiting for confirmations...")
        confirmed = 0
        for tx_hash in tx_hashes[-5:]:  # Check last 5 transactions
            try:
                receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
                if receipt.status == 1:
                    confirmed += 1
            except:
                pass
        print(f"Sample confirmations: {confirmed}/5")
    
    # Final balance check
    final_balance = w3.eth.get_balance(funder_address)
    final_balance_eth = w3.from_wei(final_balance, 'ether')
    print(f"\nFinal funder balance: {final_balance_eth} ETH")
    print(f"ETH spent: {balance_eth - final_balance_eth:.4f} ETH")
    
    # Verify a sample account was funded
    if test_accounts:
        sample_balance = w3.eth.get_balance(test_accounts[0]['address'])
        print(f"\nSample account balance: {w3.from_wei(sample_balance, 'ether')} ETH")
    
    print(f"\nAccounts are ready for stress testing!")
    print(f"Run: python3 stress_test_blocktime.py")

if __name__ == "__main__":
    main()