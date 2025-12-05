# Sei Chain Block Time Stress Testing

Two scripts are provided to test if Sei can maintain its 85ms block time under load:

## 1. Simple Block Time Monitor (`simple_blocktime_test.py`)

This script monitors block production and can generate RPC load to stress test the node.

### Usage:
```bash
# Run the full test (baseline + load test)
python3 simple_blocktime_test.py

# Or run with custom RPC endpoint
python3 simple_blocktime_test.py
```

### Features:
- Real-time block time monitoring
- Two-phase testing: baseline (no load) then under load
- Generates read-only RPC load (5000 requests/second)
- Shows statistics including percentiles and performance distribution
- No setup required - works out of the box

### What it tests:
- Makes rapid RPC calls (eth_blockNumber, eth_gasPrice, etc.)
- Monitors how block production times are affected
- Shows if 85ms target is maintained under load

## 2. Transaction Stress Test (`stress_test_blocktime.py`)

More comprehensive test that sends actual transactions.

### Prerequisites:
```bash
pip install web3 eth-account aiohttp
```

### Usage:
```bash
python3 stress_test_blocktime.py
```

### Note:
This script requires funded accounts to send transactions. For a quick test without funding accounts, use the simple monitor above.

## Expected Results

The Sei chain should maintain:
- Average block time around 85ms
- Most blocks (>90%) under 100ms
- Minimal degradation under load

## Example Output:
```
Block#    Time(ms)  Avg(10)  Avg(all)  Status
--------------------------------------------------
12345     85        84.2     85.1      ✓ FAST
12346     87        85.0     85.3      ~ OK
12347     82        84.8     85.1      ✓ FAST
```

## Interpreting Results:
- ✓ FAST: Block time ≤ 85ms (target achieved)
- ~ OK: Block time 86-100ms (acceptable)
- ! SLOW: Block time 101-150ms (degraded)
- ✗ VERY SLOW: Block time > 150ms (poor performance)