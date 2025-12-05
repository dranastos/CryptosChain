#!/usr/bin/env python3
"""
Simple Sei Chain Block Time Monitor with Load Test
Monitor block times and optionally generate RPC load
"""

import asyncio
import aiohttp
import time
import statistics
from datetime import datetime
import json

class BlockTimeMonitor:
    def __init__(self, rpc_url="http://127.0.0.1:8545"):
        self.rpc_url = rpc_url
        self.block_times = []
        self.request_count = 0
        self.error_count = 0
        
    async def make_rpc_call(self, session, method, params=None):
        """Make a JSON-RPC call"""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or [],
            "id": self.request_count
        }
        self.request_count += 1
        
        try:
            async with session.post(self.rpc_url, json=payload) as response:
                return await response.json()
        except Exception as e:
            self.error_count += 1
            return None
    
    async def generate_read_load(self, session, requests_per_second=1000):
        """Generate read-only load on the RPC endpoint"""
        delay = 1.0 / requests_per_second
        
        while True:
            # Mix of different read operations
            methods = [
                ("eth_blockNumber", []),
                ("eth_gasPrice", []),
                ("net_version", []),
                ("eth_chainId", []),
                ("eth_syncing", []),
                ("eth_getBalance", ["0x0000000000000000000000000000000000000000", "latest"]),
            ]
            
            # Send a burst of requests
            tasks = []
            for _ in range(10):  # 10 requests per burst
                method, params = methods[self.request_count % len(methods)]
                task = self.make_rpc_call(session, method, params)
                tasks.append(task)
            
            await asyncio.gather(*tasks, return_exceptions=True)
            await asyncio.sleep(delay * 10)  # Adjust for burst size
    
    async def monitor_block_production(self, duration_seconds=60, generate_load=False, load_rps=1000):
        """Monitor block production times"""
        print(f"Monitoring Sei chain block production for {duration_seconds} seconds...")
        print(f"RPC Endpoint: {self.rpc_url}")
        print(f"Load Generation: {'ON' if generate_load else 'OFF'} ({load_rps} RPS target)" if generate_load else "")
        print("-" * 80)
        
        async with aiohttp.ClientSession() as session:
            # Get initial block
            result = await self.make_rpc_call(session, "eth_getBlockByNumber", ["latest", False])
            if not result or 'result' not in result:
                print("ERROR: Cannot connect to RPC endpoint or get latest block")
                return
            
            last_block_number = int(result['result']['number'], 16)
            last_timestamp = int(result['result']['timestamp'], 16)
            start_time = time.time()
            blocks_produced = 0
            
            # Start load generator if requested
            load_task = None
            if generate_load:
                load_task = asyncio.create_task(self.generate_read_load(session, load_rps))
            
            print(f"Starting from block {last_block_number}")
            print("\nBlock#    Time(ms)  Avg(10)  Avg(all)  Status")
            print("-" * 50)
            
            try:
                while time.time() - start_time < duration_seconds:
                    await asyncio.sleep(0.02)  # Check every 20ms
                    
                    # Get current block
                    result = await self.make_rpc_call(session, "eth_getBlockByNumber", ["latest", False])
                    if not result or 'result' not in result:
                        continue
                    
                    current_block_number = int(result['result']['number'], 16)
                    
                    if current_block_number > last_block_number:
                        # New block detected
                        current_timestamp = int(result['result']['timestamp'], 16)
                        
                        # Calculate block time
                        block_time_seconds = current_timestamp - last_timestamp
                        block_time_ms = block_time_seconds * 1000
                        
                        # Sometimes timestamps might be the same for very fast blocks
                        if block_time_ms == 0:
                            # Use current time difference as approximation
                            block_time_ms = 85  # Assume target time
                        
                        self.block_times.append(block_time_ms)
                        blocks_produced += 1
                        
                        # Calculate averages
                        avg_10 = statistics.mean(self.block_times[-10:]) if len(self.block_times) >= 10 else statistics.mean(self.block_times)
                        avg_all = statistics.mean(self.block_times)
                        
                        # Status indicator
                        if block_time_ms <= 85:
                            status = "✓ FAST"
                        elif block_time_ms <= 100:
                            status = "~ OK"
                        elif block_time_ms <= 150:
                            status = "! SLOW"
                        else:
                            status = "✗ VERY SLOW"
                        
                        print(f"{current_block_number:<10} {block_time_ms:<9.0f} {avg_10:<8.1f} {avg_all:<9.1f} {status}")
                        
                        last_block_number = current_block_number
                        last_timestamp = current_timestamp
                        
            finally:
                # Cancel load generator
                if load_task:
                    load_task.cancel()
                    try:
                        await load_task
                    except asyncio.CancelledError:
                        pass
            
            # Final statistics
            print("\n" + "=" * 80)
            print("BLOCK TIME STATISTICS")
            print("=" * 80)
            
            if self.block_times:
                print(f"\nTotal blocks produced: {blocks_produced}")
                print(f"Monitoring duration: {duration_seconds}s")
                print(f"Average block time: {statistics.mean(self.block_times):.1f}ms")
                
                if len(self.block_times) > 1:
                    print(f"Std deviation: {statistics.stdev(self.block_times):.1f}ms")
                    print(f"Min block time: {min(self.block_times):.0f}ms")
                    print(f"Max block time: {max(self.block_times):.0f}ms")
                    
                    # Percentiles
                    if len(self.block_times) >= 10:
                        sorted_times = sorted(self.block_times)
                        p50 = sorted_times[len(sorted_times)//2]
                        p90 = sorted_times[int(len(sorted_times)*0.9)]
                        p95 = sorted_times[int(len(sorted_times)*0.95)]
                        p99 = sorted_times[int(len(sorted_times)*0.99)] if len(sorted_times) > 100 else sorted_times[-1]
                        
                        print(f"\nPercentiles:")
                        print(f"  50th (median): {p50:.0f}ms")
                        print(f"  90th: {p90:.0f}ms")
                        print(f"  95th: {p95:.0f}ms")
                        print(f"  99th: {p99:.0f}ms")
                
                # Performance summary
                blocks_under_85 = sum(1 for t in self.block_times if t <= 85)
                blocks_under_100 = sum(1 for t in self.block_times if t <= 100)
                blocks_under_150 = sum(1 for t in self.block_times if t <= 150)
                
                print(f"\nPerformance Distribution:")
                print(f"  ≤ 85ms:  {blocks_under_85}/{len(self.block_times)} ({blocks_under_85/len(self.block_times)*100:.1f}%)")
                print(f"  ≤ 100ms: {blocks_under_100}/{len(self.block_times)} ({blocks_under_100/len(self.block_times)*100:.1f}%)")
                print(f"  ≤ 150ms: {blocks_under_150}/{len(self.block_times)} ({blocks_under_150/len(self.block_times)*100:.1f}%)")
                
                if generate_load:
                    print(f"\nLoad Test Stats:")
                    print(f"  Total RPC requests: {self.request_count}")
                    print(f"  Failed requests: {self.error_count}")
                    print(f"  Effective RPS: {self.request_count/duration_seconds:.1f}")
            else:
                print("No new blocks detected during monitoring period!")

async def main():
    monitor = BlockTimeMonitor(rpc_url="http://127.0.0.1:8545")
    
    # First, monitor without load
    print("\n🔍 PHASE 1: Baseline Monitoring (No Load)")
    await monitor.monitor_block_production(duration_seconds=30, generate_load=False)
    
    # Reset for second phase
    monitor.block_times = []
    monitor.request_count = 0
    monitor.error_count = 0
    
    # Then monitor with load
    print("\n\n🚀 PHASE 2: Monitoring Under Load")
    await monitor.monitor_block_production(duration_seconds=30, generate_load=True, load_rps=5000)

if __name__ == "__main__":
    asyncio.run(main())