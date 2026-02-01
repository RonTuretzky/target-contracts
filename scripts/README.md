# Bridge Docker Image

Bridges EigenLayer operator state from L1 to L2.

## Image

```
ghcr.io/ronturetzky/target-contracts/bridge:pr-1
```

## Usage

```bash
docker run --rm --platform linux/amd64 \
  -e PRIVATE_KEY="0x..." \
  -e L1_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY" \
  -e L2_RPC_URL="https://gnosis-mainnet.g.alchemy.com/v2/YOUR_KEY" \
  -e REGISTRY_COORDINATOR_ADDRESS="0x..." \
  ghcr.io/ronturetzky/target-contracts/bridge:pr-1
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PRIVATE_KEY` | Yes | Private key for transactions (needs funds on both L1 and L2) |
| `L1_RPC_URL` | Yes | RPC URL for L1 (Sepolia, Holesky, Mainnet) |
| `L2_RPC_URL` | Yes | RPC URL for L2 (Gnosis, Arbitrum, etc.) |
| `REGISTRY_COORDINATOR_ADDRESS` | Yes | EigenLayer RegistryCoordinator address on L1 |

## What It Does

1. Deploys `MiddlewareShim` on L1 (reads from the RegistryCoordinator)
2. Deploys `RegistryCoordinatorMimic`, `BLSSignatureChecker`, `SP1HeliosMock` on L2
3. Snapshots operator state on L1
4. Generates storage proof
5. Bridges state to L2

## Expected Output

```
[INFO] Step 1: Deploying L1 contracts...
[INFO] MiddlewareShim: 0x...

[INFO] Step 2: Deploying L2 contracts...
[INFO] RegistryCoordinatorMimic: 0x...
[INFO] BLSSignatureChecker: 0x...

[INFO] Step 3: Updating L1 MiddlewareShim (snapshotting operator state)...
[INFO] Transaction hash: 0x...

[INFO] Step 4: Generating mock proof...
[INFO] SP1Helios address: 0x...

[INFO] Step 5: Bridging state to L2 mimic...
[INFO] State bridged successfully!

[INFO] Verification complete:
  - Quorum count: 1
  - Last updated block: ...

========================================
Bridge Complete!
========================================

L1 Contracts:
  MiddlewareShim: 0x...

L2 Contracts:
  RegistryCoordinatorMimic: 0x...
  BLSSignatureChecker: 0x...
  SP1HeliosMock: 0x...
```
