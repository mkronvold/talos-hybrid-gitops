#!/usr/bin/env bash
set -euo pipefail

# Deploy Infrastructure - Hybrid Approach
# This script provisions VMs with Terraform and configures clusters with Omni

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v terraform &> /dev/null; then
        error "terraform not found. Install from https://www.terraform.io/downloads"
        missing=1
    fi
    
    if ! command -v omnictl &> /dev/null; then
        error "omnictl not found. Install from https://omni.siderolabs.com"
        missing=1
    fi
    
    if [[ -z "${OMNI_ENDPOINT:-}" ]]; then
        error "OMNI_ENDPOINT not set. Export OMNI_ENDPOINT=https://omni.siderolabs.com"
        missing=1
    fi
    
    if [[ -z "${OMNI_API_KEY:-}" ]]; then
        error "OMNI_API_KEY not set. Get your API key from Omni and export OMNI_API_KEY=<key>"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Deploy Terraform infrastructure
deploy_terraform() {
    local platform=$1
    local terraform_dir="${PROJECT_ROOT}/terraform/${platform}"
    
    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    log "Deploying $platform infrastructure with Terraform..."
    
    cd "$terraform_dir"
    
    if [[ ! -f "terraform.tfvars" ]]; then
        error "terraform.tfvars not found. Copy from terraform.tfvars.example and fill in values"
        return 1
    fi
    
    terraform init
    terraform plan -out=tfplan
    
    read -p "Apply Terraform plan? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        warn "Terraform apply cancelled"
        return 1
    fi
    
    terraform apply tfplan
    
    log "$platform infrastructure deployed successfully"
    
    # Save outputs for reference
    terraform output -json > "${PROJECT_ROOT}/clusters/omni/${platform}-terraform-output.json"
    
    cd "$PROJECT_ROOT"
}

# Wait for VMs to boot and register with Omni
wait_for_machines() {
    local expected_count=$1
    local timeout=300
    local elapsed=0
    
    log "Waiting for machines to register with Omni (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local count=$(omnictl get machines --quiet | wc -l)
        
        if [[ $count -ge $expected_count ]]; then
            log "All $expected_count machines registered with Omni"
            return 0
        fi
        
        echo -n "."
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    error "Timeout waiting for machines to register"
    return 1
}

# Apply Omni cluster configuration
apply_omni_config() {
    local cluster_file=$1
    
    if [[ ! -f "$cluster_file" ]]; then
        error "Cluster file not found: $cluster_file"
        return 1
    fi
    
    log "Applying Omni cluster configuration: $(basename "$cluster_file")"
    
    omnictl apply -f "$cluster_file"
    
    log "Cluster configuration applied. Check status with: omnictl get clusters"
}

# Main deployment workflow
main() {
    local platform=${1:-}
    local cluster_file=${2:-}
    
    if [[ -z "$platform" ]]; then
        echo "Usage: $0 <platform> [cluster-file]"
        echo ""
        echo "Platforms: vsphere, proxmox"
        echo "Example: $0 vsphere clusters/omni/prod-vsphere.yaml"
        echo ""
        echo "Required environment variables:"
        echo "  OMNI_ENDPOINT - Omni API endpoint"
        echo "  OMNI_API_KEY  - Omni API key"
        exit 1
    fi
    
    check_prerequisites
    
    # Step 1: Deploy infrastructure with Terraform
    log "=== Step 1: Deploy Infrastructure ==="
    deploy_terraform "$platform"
    
    # Step 2: Wait for machines to register with Omni
    log "=== Step 2: Wait for Machine Registration ==="
    warn "Machines should boot and auto-register with Omni"
    warn "Make sure VMs can reach ${OMNI_ENDPOINT}"
    
    # Get expected node count from terraform output
    local node_count=$(terraform -chdir="terraform/${platform}" output -json | jq -r '.omni_registration_info.value.node_count')
    wait_for_machines "$node_count"
    
    # Step 3: Label machines for allocation (optional, can be done via Omni UI)
    log "=== Step 3: Label Machines ==="
    warn "You may need to label machines in Omni UI or with omnictl"
    warn "Example: omnictl patch machine <machine-id> --patch '[{\"op\":\"add\",\"path\":\"/metadata/labels/platform\",\"value\":\"${platform}\"}]'"
    
    # Step 4: Apply cluster configuration
    if [[ -n "$cluster_file" ]]; then
        log "=== Step 4: Apply Cluster Configuration ==="
        apply_omni_config "$cluster_file"
    else
        log "=== Step 4: Manual Cluster Configuration ==="
        warn "No cluster file specified. Apply manually with:"
        warn "  omnictl apply -f clusters/omni/${platform}-*.yaml"
    fi
    
    log "=== Deployment Complete ==="
    log "Next steps:"
    log "  1. Check cluster status: omnictl get clusters"
    log "  2. Get kubeconfig: omnictl kubeconfig <cluster-name> > kubeconfig"
    log "  3. Bootstrap Flux: flux bootstrap github ..."
}

main "$@"
