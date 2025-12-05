#!/usr/bin/env python3
"""
Fund stress test accounts for 20,000 TPS testing
Optimized for funding large numbers of accounts efficiently
"""

import json
import time
import asyncio
import aiohttp
from web3 import Web3
from eth_account import Account
from typing import List, Dict

# Configuration
FUNDER_PRIVATE_KEY = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
RPC_URL = "http://127.0.0.1:8545"  # Local Sei node
AMOUNT_PER_ACCOUNT = 0.1  # ETH per account for gas fees
NUM_ACCOUNTS = 500  # Increased for 20k TPS testing

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

def generate_accounts(num_accounts):
    """Generate test accounts with private keys (same as stress test)"""
    accounts = []
    print(f"Generating {num_accounts} accounts...")
    for i in range(num_accounts):
        acct = Account.create()
        accounts.append({
            'address': acct.address,
            'private_key': acct.key.hex()
        })
        if (i + 1) % 50 == 0:
            print(f"  Generated {i + 1}/{num_accounts} accounts...")
    return accounts

async def fund_accounts_batch(accounts_to_fund: List[Dict], start_nonce: int, batch_size: int = 20):
    """Fund a batch of accounts asynchronously"""
    async with aiohttp.ClientSession() as session:
        tasks = []
        
        for i, account in enumerate(accounts_to_fund[:batch_size]):
            # Build transaction
            amount_wei = w3.to_wei(AMOUNT_PER_ACCOUNT, 'ether')
            transaction = {
                'nonce': start_nonce + i,
                'to': account['address'],
                'value': amount_wei,
                'gas': 21000,
                'gasPrice': w3.to_wei('10', 'gwei'),
                'chainId': w3.eth.chain_id
            }
            
            # Sign transaction
            signed_txn = funder.sign_transaction(transaction)
            
            # Create request payload
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_sendRawTransaction",
                "params": [signed_txn.rawTransaction.hex()],
                "id": i
            }
            
            # Send transaction asynchronously
            task = session.post(RPC_URL, json=payload)
            tasks.append((account['address'], task))
        
        # Execute all tasks
        results = await asyncio.gather(*[t[1] for t in tasks], return_exceptions=True)
        
        successful = 0
        failed = 0
        
        for (address, _), result in zip(tasks, results):
            if isinstance(result, Exception):
                print(f"Failed to fund {address[:10]}...: {str(result)}")
                failed += 1
            else:
                try:
                    response = await result.json()
                    if 'result' in response:
                        successful += 1
                    else:
                        print(f"Error funding {address[:10]}...: {response.get('error', 'Unknown error')}")
                        failed += 1
                except Exception as e:
                    print(f"Failed to parse response for {address[:10]}...: {str(e)}")
                    failed += 1
        
        return successful, failed

async def fund_all_accounts(test_accounts: List[Dict]):
    """Fund all test accounts in batches"""
    total_accounts = len(test_accounts)
    batch_size = 20  # Send 20 transactions at a time
    
    # Get starting nonce
    nonce = w3.eth.get_transaction_count(funder_address)
    
    print(f"\nFunding {total_accounts} accounts in batches of {batch_size}...")
    
    total_successful = 0
    total_failed = 0
    
    for i in range(0, total_accounts, batch_size):
        batch = test_accounts[i:i + batch_size]
        print(f"\nProcessing batch {i//batch_size + 1}/{(total_accounts + batch_size - 1)//batch_size}")
        
        successful, failed = await fund_accounts_batch(batch, nonce, len(batch))
        total_successful += successful
        total_failed += failed
        nonce += len(batch)
        
        # Progress update
        funded_so_far = i + len(batch)
        if funded_so_far <= total_accounts:
            print(f"Progress: {funded_so_far}/{total_accounts} accounts processed")
            print(f"  Successful: {total_successful}, Failed: {total_failed}")
        
        # Small delay between batches to avoid overwhelming the node
        if i + batch_size < total_accounts:
            await asyncio.sleep(0.5)
    
    return total_successful, total_failed

def main():
    """Main funding function"""
    # Check funder balance
    balance = w3.eth.get_balance(funder_address)
    balance_eth = w3.from_wei(balance, 'ether')
    print(f"Funder balance: {balance_eth} ETH")
    
    # Check if we should load existing accounts or generate new ones
    try:
        with open('stress_test_accounts.json', 'r') as f:
            existing_accounts = json.load(f)
        if len(existing_accounts) == NUM_ACCOUNTS:
            print(f"\nFound existing {len(existing_accounts)} accounts in stress_test_accounts.json")
            use_existing = input("Use existing accounts? (y/n): ").lower() == 'y'
            if use_existing:
                test_accounts = existing_accounts
                print("Using existing accounts")
            else:
                test_accounts = generate_accounts(NUM_ACCOUNTS)
        else:
            print(f"\nExisting accounts ({len(existing_accounts)}) don't match target ({NUM_ACCOUNTS})")
            test_accounts = generate_accounts(NUM_ACCOUNTS)
    except FileNotFoundError:
        print("\nNo existing accounts found, generating new ones...")
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
        print(f"Shortfall: {total_with_gas - balance_eth} ETH")
        return
    
    # Run the async funding process
    start_time = time.time()
    successful, failed = asyncio.run(fund_all_accounts(test_accounts))
    end_time = time.time()
    
    print(f"\n{'='*60}")
    print(f"Funding complete in {end_time - start_time:.1f} seconds!")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    
    # Final balance check
    final_balance = w3.eth.get_balance(funder_address)
    final_balance_eth = w3.from_wei(final_balance, 'ether')
    print(f"\nFinal funder balance: {final_balance_eth} ETH")
    print(f"ETH spent: {balance_eth - final_balance_eth:.4f} ETH")
    
    # Verify a few sample accounts were funded
    print(f"\nVerifying sample accounts:")
    for i in range(min(5, len(test_accounts))):
        sample_balance = w3.eth.get_balance(test_accounts[i]['address'])
        print(f"  Account {i+1}: {w3.from_wei(sample_balance, 'ether')} ETH")
    
    print(f"\nAccounts are ready for high-performance stress testing!")
    print(f"Run: python3 stress_test_20k_tps.py")
    print(f"Or run updated tests: python3 stress_test_blocktime_fixed.py")

if __name__ == "__main__":
    main()