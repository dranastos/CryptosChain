# CryptosChain

A high-performance Cosmos SDK blockchain with full EVM compatibility. CryptosChain combines the interoperability of the Cosmos ecosystem with Ethereum-compatible smart contract execution.

## Features

- **Dual Execution Environment**: Native Cosmos SDK transactions and EVM smart contracts on the same chain
- **EVM Compatibility**: Full Ethereum Virtual Machine support for Solidity smart contracts
- **MetaMask Ready**: Compatible with MetaMask, web3.js, and ethers.js
- **IBC Enabled**: Inter-Blockchain Communication for cross-chain transfers
- **CosmWasm Support**: WebAssembly smart contracts
- **Token Factory**: Permissionless token creation
- **Price Oracle**: Decentralized price feeds via validator voting
- **Scheduled Minting**: Epoch-based token distribution system

## Chain Parameters

| Parameter | Value |
|-----------|-------|
| Chain ID | `cryptos-testnet-beta` |
| Binary | `cryptosd` |
| Address Prefix | `cryptos` |
| Native Denom | `ucryptos` |
| Decimal Places | 6 (1 cryptos = 1,000,000 ucryptos) |
| Block Time | ~1 second |
| Max Validators | 35 |
| Unbonding Period | 21 days |

## Prerequisites

- **Go**: Version 1.21+ (tested with 1.24.5)
- **Git**: For cloning the repository
- **Make**: For building
- **Docker** (optional): For running a local cluster

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Storage | 500 GB SSD | 1 TB NVMe SSD |
| Network | 100 Mbps | 1 Gbps |

## Installation

### Clone the Repository

```bash
git clone https://github.com/dranastos/CryptosChain.git
cd CryptosChain
```

### Build from Source

```bash
# Build the binary to ./build/cryptosd
make build

# Or install to $GOPATH/bin
make install
```

### Verify Installation

```bash
./build/cryptosd version
```

## Running a Node

### Quick Start (Local Development)

Initialize and start a local single-node chain:

```bash
# Initialize the chain
./scripts/initialize_local_chain.sh

# Start the node
./build/cryptosd start
```

### Docker Cluster (4 Nodes)

Run a local 4-node testnet with Docker:

```bash
# Build and start cluster
make docker-cluster-start

# Or start without rebuilding
make docker-cluster-start-skipbuild
```

### Join an Existing Network

1. Initialize your node:
```bash
./build/cryptosd init <your-moniker> --chain-id cryptos-testnet-beta
```

2. Copy the genesis file from the network:
```bash
cp genesis.json ~/.cryptos/config/genesis.json
```

3. Configure seeds/persistent peers in `~/.cryptos/config/config.toml`

4. Start the node:
```bash
./build/cryptosd start
```

## Node Configuration

Configuration files are located in `~/.cryptos/config/`:

| File | Purpose |
|------|---------|
| `app.toml` | Application settings (API, gRPC, EVM RPC) |
| `config.toml` | Tendermint/CometBFT settings |
| `genesis.json` | Initial chain state |

### Node Modes

| Mode | Use Case | EVM RPC |
|------|----------|---------|
| `validator` | Block production | Disabled |
| `full` | RPC queries, indexing | Enabled |
| `archive` | Historical data | Enabled |
| `seed` | Peer discovery | Disabled |

Set the node mode in `app.toml`:
```toml
[node]
mode = "full"
```

## Key Management

### Create a New Key

```bash
./build/cryptosd keys add <key-name>
```

### Import Existing Key

```bash
./build/cryptosd keys add <key-name> --recover
```

### List Keys

```bash
./build/cryptosd keys list
```

## CLI Commands

### Query Balance

```bash
./build/cryptosd query bank balances <address>
```

### Send Tokens

```bash
./build/cryptosd tx bank send <from-key> <to-address> <amount>ucryptos \
  --chain-id cryptos-testnet-beta \
  --gas auto \
  --gas-adjustment 1.3
```

### Delegate to Validator

```bash
./build/cryptosd tx staking delegate <validator-address> <amount>ucryptos \
  --from <key-name> \
  --chain-id cryptos-testnet-beta
```

### Query Validators

```bash
./build/cryptosd query staking validators
```

## EVM / Ethereum Compatibility

CryptosChain exposes standard Ethereum JSON-RPC endpoints.

### RPC Endpoints

- HTTP: `http://localhost:8545`
- WebSocket: `ws://localhost:8546`

### Connect with MetaMask

1. Open MetaMask and add a custom network
2. Network Name: `Cryptos Testnet`
3. RPC URL: `http://<node-ip>:8545`
4. Chain ID: Check current chain ID via RPC
5. Currency Symbol: `CRYPTOS`

### Deploy Contracts

Use standard Ethereum tooling:
- Hardhat
- Foundry
- Remix IDE
- Truffle

Example with ethers.js:
```javascript
const provider = new ethers.JsonRpcProvider('http://localhost:8545');
const wallet = new ethers.Wallet(privateKey, provider);
// Deploy contracts as usual
```

## Staking Parameters

| Parameter | Value |
|-----------|-------|
| Max Validators | 35 |
| Unbonding Time | 21 days |
| Min Commission | 5% |
| Max Voting Power | 20% |
| Historical Entries | 10,000 |

## Token Economics

### Distribution

- Community Tax: 10%
- Base Proposer Reward: 0%
- Bonus Proposer Reward: 0%

### Minting Schedule

The chain implements scheduled token releases distributed daily:

| Year | Annual Release (ucryptos) |
|------|---------------------------|
| 2025 | 50,000,000,000,000 |
| 2026 | 50,000,000,000,000 |
| 2027 | 50,000,000,000,000 |
| 2028 | 50,000,000,000,000 |
| 2029 | 50,000,000,000,000 |
| 2030 | 50,000,000,000,000 |
| 2031 | 50,000,000,000,000 |

## Project Structure

```
CryptosChain/
├── app/                    # Core application logic
│   ├── app.go              # Main application struct
│   ├── ante.go             # Transaction ante handlers
│   └── params/             # Node configuration
├── cmd/seid/               # CLI entry point
├── x/                      # Custom modules
│   ├── evm/                # Ethereum Virtual Machine
│   ├── mint/               # Token minting
│   ├── oracle/             # Price oracle
│   ├── epoch/              # Time-based epochs
│   └── tokenfactory/       # Token creation
├── scripts/                # Setup and utility scripts
├── docker/                 # Docker configurations
├── proto/                  # Protocol buffer definitions
└── Makefile                # Build automation
```

## Custom Modules

### EVM Module
Full Ethereum Virtual Machine integration with precompiled contracts for Cosmos SDK functionality.

### Mint Module
Scheduled token distribution based on yearly release schedules, distributed daily through epoch hooks.

### Oracle Module
Decentralized price feeds where validators vote on asset prices. Validators face slashing for incorrect data.

### Epoch Module
Time-based epoch management (default: 60 seconds) that triggers scheduled actions across modules.

### Token Factory Module
Permissionless token creation with format: `factory/{creator}/{subdenom}`

## Development

### Run Tests

```bash
make test
```

### Linting

```bash
make lint
```

### Build with RocksDB

```bash
make install-rocksdb
```

### Generate Protobuf

```bash
make proto-gen
```

## Useful Scripts

| Script | Purpose |
|--------|---------|
| `scripts/initialize_local_chain.sh` | Setup local development chain |
| `scripts/initialize_validator.sh` | Initialize a validator node |
| `scripts/reset_chain.sh` | Reset chain state |
| `scripts/derive_evm_address.sh` | Derive EVM address from Cosmos address |

## API Documentation

API documentation is available via Swagger when running a full node:
- REST API: `http://localhost:1317/swagger/`

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is based on the Sei Protocol codebase.

## Links

- [Cosmos SDK Documentation](https://docs.cosmos.network/)
- [Tendermint Documentation](https://docs.tendermint.com/)
- [Ethereum JSON-RPC](https://ethereum.org/en/developers/docs/apis/json-rpc/)
