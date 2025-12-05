#!/usr/bin/env python3
"""
Diagnose issues with the stress test
"""

import asyncio
import aiohttp
import json
from web3 import Web3
from eth_account import Account

async def diagnose():
    rpc_url = "http://127.0.0.1:8545"
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    
    print("=== STRESS TEST DIAGNOSTICS ===\n")
    
    # 1. Check RPC connection
    print("1. Checking RPC connection...")
    try:
        connected = web3.is_connected()
        print(f"   Connected to RPC: {connected}")
        if connected:
            print(f"   Latest block: {web3.eth.block_number}")
            print(f"   Chain ID: {web3.eth.chain_id}")
    except Exception as e:
        print(f"   ERROR connecting to RPC: {e}")
        return
    
    # 2. Check accounts
    print("\n2. Checking test accounts...")
    try:
        with open('stress_test_accounts.json', 'r') as f:
            accounts = json.load(f)
        print(f"   Found {len(accounts)} test accounts")
        
        # Check balance of first few accounts
        for i, acc in enumerate(accounts[:3]):
            balance = web3.eth.get_balance(acc['address'])
            print(f"   Account {i}: {acc['address']} - Balance: {web3.from_wei(balance, 'ether')} ETH")
    except Exception as e:
        print(f"   ERROR loading accounts: {e}")
    
    # 3. Test transaction sending
    print("\n3. Testing transaction sending...")
    if accounts and balance > 0:
        try:
            from_account = accounts[0]
            to_account = accounts[1]
            
            # Get nonce
            nonce = web3.eth.get_transaction_count(from_account['address'])
            print(f"   From account nonce: {nonce}")
            
            # Create transaction
            tx = {
                'from': from_account['address'],
                'to': to_account['address'],
                'value': web3.to_wei(0.0001, 'ether'),
                'gas': 21000,
                'gasPrice': web3.to_wei('10', 'gwei'),
                'nonce': nonce,
                'chainId': web3.eth.chain_id
            }
            
            print(f"   Transaction details:")
            print(f"     Chain ID: {tx['chainId']}")
            print(f"     Gas: {tx['gas']}")
            print(f"     Gas Price: {tx['gasPrice']}")
            
            # Sign and send
            signed = Account.sign_transaction(tx, from_account['private_key'])
            tx_hash = web3.eth.send_raw_transaction(signed.rawTransaction)
            print(f"   Transaction sent! Hash: {tx_hash.hex()}")
            
            # Wait for receipt
            receipt = web3.eth.wait_for_transaction_receipt(tx_hash, timeout=10)
            print(f"   Transaction confirmed in block: {receipt['blockNumber']}")
            print(f"   Status: {'Success' if receipt['status'] == 1 else 'Failed'}")
            
        except Exception as e:
            print(f"   ERROR sending transaction: {e}")
    else:
        print("   Cannot test - accounts not funded")
    
    # 4. Check block timestamps
    print("\n4. Checking block timestamp precision...")
    async with aiohttp.ClientSession() as session:
        current_block = web3.eth.block_number
        
        for i in range(5):
            block_num = current_block - i
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_getBlockByNumber",
                "params": [hex(block_num), False],
                "id": 1
            }
            
            async with session.post(rpc_url, json=payload) as response:
                result = await response.json()
                if 'result' in result and result['result']:
                    timestamp = int(result['result']['timestamp'], 16)
                    print(f"   Block {block_num}: timestamp = {timestamp}")
                    if i > 0:
                        prev_timestamp = int(prev_result['result']['timestamp'], 16)
                        diff_ms = (prev_timestamp - timestamp) * 1000
                        print(f"     Time diff from previous: {diff_ms}ms")
                    prev_result = result

if __name__ == "__main__":
    asyncio.run(diagnose())