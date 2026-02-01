#!/bin/bash

#######################################################################
# Bridge EigenLayer Operator State from L1 to L2
#
# This script deploys the bridge contracts and bridges operator state
# from an L1 registry coordinator to an L2 mimic contract.
#
# Required Environment Variables:
#   PRIVATE_KEY              - Private key for deployment and transactions
#   L1_RPC_URL               - RPC URL for L1 (e.g., Sepolia)
#   L2_RPC_URL               - RPC URL for L2 (e.g., Gnosis)
#   REGISTRY_COORDINATOR_ADDRESS - L1 registry coordinator to bridge from
#
# Optional Environment Variables:
#   SLOT_NUMBER              - Slot number for mock proof (default: 12345)
#   SKIP_DEPLOY              - Set to "true" to skip deployment and use existing contracts
#   L1_DEPLOY_FILE           - Path to existing L1 deployment file (required if SKIP_DEPLOY=true)
#   L2_DEPLOY_FILE           - Path to existing L2 deployment file (required if SKIP_DEPLOY=true)
#
#######################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate required environment variables
validate_env() {
    local missing=()

    [[ -z "$PRIVATE_KEY" ]] && missing+=("PRIVATE_KEY")
    [[ -z "$L1_RPC_URL" ]] && missing+=("L1_RPC_URL")
    [[ -z "$L2_RPC_URL" ]] && missing+=("L2_RPC_URL")
    [[ -z "$REGISTRY_COORDINATOR_ADDRESS" ]] && missing+=("REGISTRY_COORDINATOR_ADDRESS")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
}

# Get script directory and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(cd "$SCRIPT_DIR/../contracts" && pwd)"
ARTIFACTS_DIR="$CONTRACTS_DIR/artifacts"

# Default values
SLOT_NUMBER="${SLOT_NUMBER:-12345}"
SKIP_DEPLOY="${SKIP_DEPLOY:-false}"

# Validate environment
validate_env

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

# Set output paths
L1_OUT_PATH="${L1_DEPLOY_FILE:-$ARTIFACTS_DIR/l1-deploy.json}"
L2_OUT_PATH="${L2_DEPLOY_FILE:-$ARTIFACTS_DIR/l2-deploy.json}"
PROOF_FILE="$ARTIFACTS_DIR/middlewareDataProof.json"

cd "$CONTRACTS_DIR"

#######################################################################
# Step 1: Deploy L1 Contracts (MiddlewareShim)
#######################################################################

if [[ "$SKIP_DEPLOY" != "true" ]]; then
    log_info "Step 1: Deploying L1 contracts to $(echo $L1_RPC_URL | sed 's/\/.*//g')..."

    export REGISTRY_COORDINATOR_ADDRESS
    export PRIVATE_KEY
    export L1_OUT_PATH

    forge script script/e2e/DeployL1.s.sol:DeployL1 \
        --broadcast \
        --rpc-url "$L1_RPC_URL" \
        --quiet

    log_info "L1 contracts deployed. Output: $L1_OUT_PATH"
else
    log_info "Step 1: Skipping L1 deployment (SKIP_DEPLOY=true)"
    if [[ ! -f "$L1_OUT_PATH" ]]; then
        log_error "L1 deployment file not found: $L1_OUT_PATH"
        exit 1
    fi
fi

# Read L1 deployment addresses
MIDDLEWARE_SHIM_ADDRESS=$(jq -r '.middlewareShim' "$L1_OUT_PATH")
log_info "MiddlewareShim: $MIDDLEWARE_SHIM_ADDRESS"

#######################################################################
# Step 2: Deploy L2 Contracts (RegistryCoordinatorMimic)
#######################################################################

if [[ "$SKIP_DEPLOY" != "true" ]]; then
    log_info "Step 2: Deploying L2 contracts..."

    export MIDDLEWARE_SHIM_ADDRESS
    export SP1HELIOS_ADDRESS="0x0000000000000000000000000000000000000000"
    export IS_SP1HELIOS_MOCK="true"
    export L2_OUT_PATH

    forge script script/e2e/DeployL2.s.sol:DeployL2 \
        --broadcast \
        --rpc-url "$L2_RPC_URL" \
        --quiet

    log_info "L2 contracts deployed. Output: $L2_OUT_PATH"
else
    log_info "Step 2: Skipping L2 deployment (SKIP_DEPLOY=true)"
    if [[ ! -f "$L2_OUT_PATH" ]]; then
        log_error "L2 deployment file not found: $L2_OUT_PATH"
        exit 1
    fi
fi

# Read L2 deployment addresses
REGISTRY_COORDINATOR_MIMIC=$(jq -r '.registryCoordinatorMimic' "$L2_OUT_PATH")
BLS_SIGNATURE_CHECKER=$(jq -r '.blsSignatureChecker' "$L2_OUT_PATH")
log_info "RegistryCoordinatorMimic: $REGISTRY_COORDINATOR_MIMIC"
log_info "BLSSignatureChecker: $BLS_SIGNATURE_CHECKER"

#######################################################################
# Step 3: Update L1 Shim (Snapshot operator state)
#######################################################################

log_info "Step 3: Updating L1 MiddlewareShim (snapshotting operator state)..."

TX_RESULT=$(cast send \
    --rpc-url "$L1_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --json \
    "$MIDDLEWARE_SHIM_ADDRESS" \
    "updateMiddlewareDataHash()")

TX_HASH=$(echo "$TX_RESULT" | jq -r '.transactionHash')
log_info "Transaction hash: $TX_HASH"

# Wait for confirmation
sleep 3

BLOCK_NUMBER=$(cast receipt --rpc-url "$L1_RPC_URL" "$TX_HASH" --json | jq -r '.blockNumber')
log_info "Operator state snapshotted at block: $BLOCK_NUMBER"

#######################################################################
# Step 4: Generate Mock Proof
#######################################################################

log_info "Step 4: Generating mock proof..."

# Get SP1Helios address from mimic
SP1HELIOS_ADDRESS=$(cast call "$REGISTRY_COORDINATOR_MIMIC" "LITE_CLIENT()(address)" --rpc-url "$L2_RPC_URL")
log_info "SP1Helios address: $SP1HELIOS_ADDRESS"

# Get middleware block number
MIDDLEWARE_BLOCK_NUMBER=$(cast call "$MIDDLEWARE_SHIM_ADDRESS" "lastBlockNumber()" --rpc-url "$L1_RPC_URL" | cast to-dec)
log_info "Middleware block number: $MIDDLEWARE_BLOCK_NUMBER"

# Get latest block and proof data
LATEST_BLOCK=$(cast block latest --rpc-url "$L1_RPC_URL" --json | jq -r '.number')
log_info "Latest L1 block: $LATEST_BLOCK"

# Get storage proof for slot 0 (middlewareDataHash)
STORAGE_SLOT=0
PROOF_DATA=$(cast proof -B "$LATEST_BLOCK" "$MIDDLEWARE_SHIM_ADDRESS" "$STORAGE_SLOT" --json --rpc-url "$L1_RPC_URL")

# Get execution state root
EXECUTION_STATE_ROOT=$(cast block "$LATEST_BLOCK" --rpc-url "$L1_RPC_URL" --json | jq -r '.stateRoot')
log_info "Execution state root: $EXECUTION_STATE_ROOT"

# Set execution state root on SP1Helios mock
log_info "Setting execution state root on SP1Helios mock..."
cast send "$SP1HELIOS_ADDRESS" \
    "setExecutionStateRoot(uint256,bytes32)" \
    "$SLOT_NUMBER" \
    "$EXECUTION_STATE_ROOT" \
    --rpc-url "$L2_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    > /dev/null 2>&1

# Create proof JSON file
jq -n \
    --arg middlewareBlockNumber "$MIDDLEWARE_BLOCK_NUMBER" \
    --arg slotNumber "$SLOT_NUMBER" \
    --arg storageHash "$(echo "$PROOF_DATA" | jq -r '.storageHash')" \
    --arg executionStateRoot "$EXECUTION_STATE_ROOT" \
    --argjson storageProof "$(echo "$PROOF_DATA" | jq -r '.storageProof[0].proof')" \
    --argjson accountProof "$(echo "$PROOF_DATA" | jq -r '.accountProof')" \
    '{
        "middlewareBlockNumber": $middlewareBlockNumber,
        "slotNumber": $slotNumber,
        "storageHash": $storageHash,
        "executionStateRoot": $executionStateRoot,
        "storageProof": $storageProof,
        "accountProof": $accountProof
    }' > "$PROOF_FILE"

log_info "Mock proof saved to: $PROOF_FILE"

#######################################################################
# Step 5: Update L2 Mimic (Bridge state)
#######################################################################

log_info "Step 5: Bridging state to L2 mimic..."

export PROOF_FILE
export REGISTRY_COORDINATOR_MIMIC_ADDRESS="$REGISTRY_COORDINATOR_MIMIC"
export BLS_SIGNATURE_CHECKER_ADDRESS="$BLS_SIGNATURE_CHECKER"
export MIDDLEWARE_SHIM_ADDRESS
export IS_SP1HELIOS_MOCK="true"
export L1_RPC_URL
export L2_RPC_URL
export PRIVATE_KEY

forge script script/e2e/UpdateMimic.s.sol:UpdateMimic \
    --broadcast \
    --quiet

log_info "State bridged successfully!"

#######################################################################
# Verify bridged state
#######################################################################

log_info "Verifying bridged state on L2..."

QUORUM_COUNT=$(cast call "$REGISTRY_COORDINATOR_MIMIC" "quorumCount()(uint8)" --rpc-url "$L2_RPC_URL")
LAST_BLOCK=$(cast call "$REGISTRY_COORDINATOR_MIMIC" "lastBlockNumber()(uint32)" --rpc-url "$L2_RPC_URL")

log_info "Verification complete:"
echo "  - Quorum count: $QUORUM_COUNT"
echo "  - Last updated block: $LAST_BLOCK"

#######################################################################
# Summary
#######################################################################

echo ""
echo "========================================"
echo "Bridge Complete!"
echo "========================================"
echo ""
echo "L1 Contracts ($(echo $L1_RPC_URL | sed 's|https://||' | cut -d'.' -f1)):"
echo "  MiddlewareShim: $MIDDLEWARE_SHIM_ADDRESS"
echo ""
echo "L2 Contracts:"
echo "  RegistryCoordinatorMimic: $REGISTRY_COORDINATOR_MIMIC"
echo "  BLSSignatureChecker: $BLS_SIGNATURE_CHECKER"
echo "  SP1HeliosMock: $SP1HELIOS_ADDRESS"
echo ""
echo "Deployment files:"
echo "  L1: $L1_OUT_PATH"
echo "  L2: $L2_OUT_PATH"
echo "  Proof: $PROOF_FILE"
echo ""
