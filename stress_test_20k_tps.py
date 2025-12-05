#!/usr/bin/env python3
"""
Sei Chain High-Performance Stress Test - 20,000 TPS Target
Optimized for maximum throughput with connection pooling and concurrent batching
"""

import asyncio
import aiohttp
import time
import statistics
from datetime import datetime
from typing import List, Dict, Tuple
import json
import random
from web3 import Web3
from eth_account import Account
import concurrent.futures
from aiohttp import TCPConnector

class SeiHighPerformanceStressTest:
    def __init__(self, rpc_url="http://127.0.0.1:8545", num_accounts=500, use_saved_accounts=True):
        self.rpc_url = rpc_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        self.num_accounts = num_accounts
        self.use_saved_accounts = use_saved_accounts
        self.accounts = []
        self.block_times = []
        self.tx_results = {
            'sent': 0,
            'confirmed': 0,
            'failed': 0,
            'pending': 0
        }
        # Connection pool settings for high throughput
        self.connector_settings = {
            'limit': 200,  # Total connection pool size
            'limit_per_host': 200,  # Connections per host
            'ttl_dns_cache': 300,
            'enable_cleanup_closed': True
        }
        
    def generate_accounts(self) -> List[Dict]:
        """Generate test accounts with private keys"""
        accounts = []
        for i in range(self.num_accounts):
            acct = Account.create()
            accounts.append({
                'address': acct.address,
                'private_key': acct.key.hex()
            })
        return accounts
    
    async def get_block_height(self, session) -> int:
        """Get current block height"""
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        }
        async with session.post(self.rpc_url, json=payload) as response:
            result = await response.json()
            return int(result['result'], 16)
    
    async def get_block_by_number(self, session, block_num) -> Dict:
        """Get block details by number"""
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getBlockByNumber",
            "params": [hex(block_num), False],
            "id": 1
        }
        async with session.post(self.rpc_url, json=payload) as response:
            result = await response.json()
            return result['result']
    
    async def monitor_blocks(self, duration_seconds=60):
        """Monitor block production for specified duration"""
        print(f"Monitoring block production for {duration_seconds} seconds...")
        
        connector = TCPConnector(**self.connector_settings)
        async with aiohttp.ClientSession(connector=connector) as session:
            start_time = time.time()
            start_real_time = time.perf_counter()  # High precision timer
            
            last_block = await self.get_block_height(session)
            last_block_time = time.perf_counter()
            
            blocks_produced = 0
            block_time_measurements = []
            
            while time.time() - start_time < duration_seconds:
                await asyncio.sleep(0.02)  # Check every 20ms for better precision
                
                try:
                    current_block = await self.get_block_height(session)
                    
                    if current_block > last_block:
                        # New block detected
                        current_block_time = time.perf_counter()
                        
                        # Calculate block time based on actual measurement
                        blocks_diff = current_block - last_block
                        time_diff_ms = (current_block_time - last_block_time) * 1000
                        
                        # Average block time for this interval
                        avg_block_time_ms = time_diff_ms / blocks_diff
                        
                        # Record each block's estimated time
                        for _ in range(blocks_diff):
                            self.block_times.append(avg_block_time_ms)
                            block_time_measurements.append(avg_block_time_ms)
                        
                        # Real-time feedback
                        if blocks_produced % 10 == 0:
                            recent_avg = statistics.mean(block_time_measurements[-10:]) if len(block_time_measurements) >= 10 else statistics.mean(block_time_measurements)
                            print(f"Block {current_block}: {avg_block_time_ms:.1f}ms (avg last 10: {recent_avg:.1f}ms)")
                        
                        last_block = current_block
                        last_block_time = current_block_time
                        blocks_produced += blocks_diff
                        
                except Exception as e:
                    print(f"Error monitoring blocks: {e}")
                    
            # Calculate overall statistics
            total_time_s = time.perf_counter() - start_real_time
            print(f"\nMonitoring complete: {blocks_produced} blocks in {total_time_s:.1f}s")
            if blocks_produced > 0:
                print(f"Average block time: {total_time_s * 1000 / blocks_produced:.1f}ms")
                    
            return blocks_produced
    
    async def send_transaction_batch_optimized(self, session, from_account, nonce_start, batch_size=100):
        """Send a large batch of transactions with optimized parallel processing"""
        # Pre-compute all transactions
        transactions = []
        for i in range(batch_size):
            tx = {
                'from': from_account['address'],
                'to': self.accounts[random.randint(0, len(self.accounts)-1)]['address'],
                'value': self.web3.to_wei(0.0001, 'ether'),
                'gas': 21000,
                'gasPrice': self.web3.to_wei('10', 'gwei'),
                'nonce': nonce_start + i,
                'chainId': 713714  # Sei testnet chain ID
            }
            signed = Account.sign_transaction(tx, from_account['private_key'])
            transactions.append(signed.rawTransaction.hex())
        
        # Send all transactions in parallel batches
        batch_tasks = []
        sub_batch_size = 20  # Send in sub-batches to avoid overwhelming the node
        
        for i in range(0, len(transactions), sub_batch_size):
            sub_batch = transactions[i:i+sub_batch_size]
            for j, tx_hex in enumerate(sub_batch):
                payload = {
                    "jsonrpc": "2.0",
                    "method": "eth_sendRawTransaction",
                    "params": [tx_hex],
                    "id": i + j
                }
                task = session.post(self.rpc_url, json=payload)
                batch_tasks.append(task)
        
        # Execute all tasks
        responses = await asyncio.gather(*batch_tasks, return_exceptions=True)
        
        success_count = 0
        for response in responses:
            if isinstance(response, Exception):
                self.tx_results['failed'] += 1
            else:
                try:
                    result = await response.json()
                    if 'result' in result:
                        self.tx_results['sent'] += 1
                        success_count += 1
                    else:
                        self.tx_results['failed'] += 1
                except:
                    self.tx_results['failed'] += 1
        
        return success_count
    
    async def stress_test_transactions_optimized(self, tps_target=20000, duration_seconds=30):
        """Send transactions at target TPS rate with optimized concurrency"""
        print(f"\nStarting HIGH-PERFORMANCE transaction stress test at {tps_target} TPS for {duration_seconds} seconds...")
        
        # Load accounts
        if self.use_saved_accounts:
            try:
                with open('stress_test_accounts.json', 'r') as f:
                    self.accounts = json.load(f)
                print(f"Loaded {len(self.accounts)} pre-funded test accounts from file")
            except FileNotFoundError:
                print("No saved accounts found, generating new ones...")
                print("WARNING: These accounts need to be funded first!")
                self.accounts = self.generate_accounts()
        else:
            self.accounts = self.generate_accounts()
            print(f"Generated {len(self.accounts)} test accounts (need funding!)")
        
        # Get initial nonces for all accounts
        print("Getting account nonces...")
        nonce_counters = {}
        for acc in self.accounts:
            nonce_counters[acc['address']] = self.web3.eth.get_transaction_count(acc['address'])
        
        # Create connection pool for high throughput
        connector = TCPConnector(**self.connector_settings)
        
        async with aiohttp.ClientSession(connector=connector) as session:
            start_time = time.time()
            
            # Calculate optimal batching for 20,000 TPS
            # We'll send larger batches less frequently to achieve high throughput
            transactions_per_batch = 2000  # Large batch size
            batch_interval = transactions_per_batch / tps_target  # Time between batches
            concurrent_senders = min(100, len(self.accounts))  # Use many accounts concurrently
            txs_per_account = transactions_per_batch // concurrent_senders
            
            print(f"Configuration: {transactions_per_batch} txs per batch, {batch_interval:.3f}s interval, {concurrent_senders} concurrent senders")
            
            last_batch_time = time.time()
            
            while time.time() - start_time < duration_seconds:
                current_time = time.time()
                
                # Rate limiting - wait for next batch window
                time_since_last_batch = current_time - last_batch_time
                if time_since_last_batch < batch_interval:
                    await asyncio.sleep(batch_interval - time_since_last_batch)
                
                # Select accounts to send from
                sending_accounts = random.sample(self.accounts, concurrent_senders)
                
                # Create tasks for parallel execution
                tasks = []
                for account in sending_accounts:
                    task = self.send_transaction_batch_optimized(
                        session, 
                        account, 
                        nonce_counters[account['address']],
                        txs_per_account
                    )
                    tasks.append(task)
                    nonce_counters[account['address']] += txs_per_account
                
                # Execute all tasks concurrently
                await asyncio.gather(*tasks)
                
                last_batch_time = time.time()
                
                # Progress update
                elapsed = int(time.time() - start_time)
                if elapsed > 0 and elapsed % 2 == 0:  # More frequent updates
                    current_tps = self.tx_results['sent'] / max(1, elapsed)
                    print(f"[{elapsed}s] Sent: {self.tx_results['sent']} | Failed: {self.tx_results['failed']} | TPS: {current_tps:.0f}")
    
    async def run_full_test(self, stress_duration=30, monitor_duration=60):
        """Run complete stress test with monitoring"""
        print("=" * 80)
        print("SEI CHAIN HIGH-PERFORMANCE STRESS TEST - 20,000 TPS TARGET")
        print("=" * 80)
        
        # Check connection
        if not self.web3.is_connected():
            print("ERROR: Cannot connect to Sei node at", self.rpc_url)
            return
        
        print(f"Connected to Sei node at {self.rpc_url}")
        print(f"Latest block: {self.web3.eth.block_number}")
        print(f"Chain ID: {self.web3.eth.chain_id}")
        
        # Phase 1: Baseline measurement (no load)
        print("\nPhase 1: Measuring baseline block time (no load)...")
        baseline_blocks = await self.monitor_blocks(30)
        
        if self.block_times:
            baseline_avg = statistics.mean(self.block_times)
            baseline_std = statistics.stdev(self.block_times) if len(self.block_times) > 1 else 0
            print(f"\nBaseline Results:")
            print(f"  Average block time: {baseline_avg:.1f}ms")
            print(f"  Std deviation: {baseline_std:.1f}ms")
            print(f"  Min: {min(self.block_times):.1f}ms, Max: {max(self.block_times):.1f}ms")
        
        # Phase 2: Stress test with monitoring
        print(f"\nPhase 2: HIGH-PERFORMANCE stress testing with 20,000 TPS target...")
        self.block_times = []  # Reset for stress test
        
        # Run stress test and monitoring concurrently
        stress_task = asyncio.create_task(self.stress_test_transactions_optimized(tps_target=20000, duration_seconds=stress_duration))
        monitor_task = asyncio.create_task(self.monitor_blocks(monitor_duration))
        
        await asyncio.gather(stress_task, monitor_task)
        
        # Phase 3: Analysis
        print("\n" + "=" * 80)
        print("HIGH-PERFORMANCE STRESS TEST RESULTS")
        print("=" * 80)
        
        if self.block_times:
            avg_block_time = statistics.mean(self.block_times)
            std_block_time = statistics.stdev(self.block_times) if len(self.block_times) > 1 else 0
            percentile_95 = statistics.quantiles(self.block_times, n=20)[18] if len(self.block_times) > 20 else max(self.block_times)
            
            print(f"\nBlock Time Statistics Under 20,000 TPS Load:")
            print(f"  Average: {avg_block_time:.1f}ms")
            print(f"  Std Dev: {std_block_time:.1f}ms")
            print(f"  Min: {min(self.block_times):.1f}ms")
            print(f"  Max: {max(self.block_times):.1f}ms")
            print(f"  95th percentile: {percentile_95:.1f}ms")
            
            # Check if 85ms target is maintained
            blocks_under_100ms = sum(1 for t in self.block_times if t <= 100)
            blocks_under_85ms = sum(1 for t in self.block_times if t <= 85)
            
            print(f"\nPerformance vs Target:")
            print(f"  Blocks under 85ms: {blocks_under_85ms}/{len(self.block_times)} ({blocks_under_85ms/len(self.block_times)*100:.1f}%)")
            print(f"  Blocks under 100ms: {blocks_under_100ms}/{len(self.block_times)} ({blocks_under_100ms/len(self.block_times)*100:.1f}%)")
            
            print(f"\nTransaction Statistics:")
            print(f"  Transactions sent: {self.tx_results['sent']}")
            print(f"  Transactions failed: {self.tx_results['failed']}")
            actual_tps = self.tx_results['sent'] / stress_duration
            print(f"  Actual TPS achieved: {actual_tps:.1f}")
            print(f"  Target TPS: 20,000")
            print(f"  Achievement rate: {(actual_tps / 20000) * 100:.1f}%")
            
            # Verdict
            print(f"\nVERDICT:")
            if avg_block_time <= 85 and actual_tps >= 18000:
                print(f"  ✓ Chain MAINTAINED 85ms average block time under 20,000 TPS load!")
            elif avg_block_time <= 100 and actual_tps >= 15000:
                print(f"  ~ Chain maintained sub-100ms block time under high load")
            else:
                print(f"  ✗ Chain struggled under 20,000 TPS target load")
                if actual_tps < 10000:
                    print(f"  Note: Could only achieve {actual_tps:.0f} TPS. Consider:")
                    print(f"    - Checking node resources (CPU, memory, disk I/O)")
                    print(f"    - Verifying network connectivity")
                    print(f"    - Ensuring accounts are properly funded")

async def main():
    # Create high-performance tester
    tester = SeiHighPerformanceStressTest(
        rpc_url="http://127.0.0.1:8545",
        num_accounts=500  # More accounts for better distribution
    )
    
    await tester.run_full_test(
        stress_duration=30,  # How long to send transactions
        monitor_duration=45  # How long to monitor blocks
    )

if __name__ == "__main__":
    asyncio.run(main())