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
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Usage information
usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <site-code> <platform> [cluster-file]

${YELLOW}Deploy infrastructure and Talos clusters for a specific site.${NC}

${GREEN}Arguments:${NC}
  site-code     Site identifier (e.g., ny1d, sf2p, la1s)
  platform      Infrastructure platform: vsphere or proxmox
  cluster-file  (Optional) Path to Omni cluster YAML configuration

${GREEN}Site Code Format:${NC}
  <city><zone><env>
  
  Examples:
    ny1d - New York, Zone 1, Dev
    sf2p - San Francisco, Zone 2, Prod
    la1s - Los Angeles, Zone 1, Staging

${GREEN}Examples:${NC}
  # Deploy NY Zone 1 Dev cluster on vSphere
  $0 ny1d vsphere clusters/omni/ny1d-cluster.yaml
  
  # Deploy SF Zone 2 Prod cluster on Proxmox
  $0 sf2p proxmox clusters/omni/sf2p-cluster.yaml
  
  # Deploy infrastructure only (manual cluster config later)
  $0 la1s vsphere

${GREEN}Required Environment Variables:${NC}
  OMNI_ENDPOINT  - Omni API endpoint (https://omni.siderolabs.com)
  OMNI_API_KEY   - Omni API key

${GREEN}Configuration Files:${NC}
  Terraform: terraform/<platform>/terraform.tfvars.<site-code>
  Cluster:   clusters/omni/<site-code>-cluster.yaml

${GREEN}Workflow:${NC}
  1. Validates site code and prerequisites
  2. Provisions VMs with Terraform (uses workspace per site)
  3. Waits for machines to register with Omni
  4. Applies cluster configuration to Omni
  5. Saves kubeconfig for cluster access

EOF
    exit 1
}

# Validate site code format
validate_site_code() {
    local site_code=$1
    
    if [ ${#site_code} -ne 4 ]; then
        error "Invalid site code format: $site_code"
        error "Expected format: <city><zone><env> (e.g., ny1d, sf2p)"
        usage
    fi
    
    if ! [[ $site_code =~ ^[a-z]{2}[0-9][dsp]$ ]]; then
        error "Invalid site code format: $site_code"
        error "Expected: 2 lowercase letters + 1 digit + environment (d/s/p)"
        error "Examples: ny1d, sf2p, la1s"
        usage
    fi
    
    log "✓ Site code validated: $site_code"
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
    local site_code=$1
    local platform=$2
    local terraform_dir="${PROJECT_ROOT}/terraform/${platform}"
    local var_file="terraform.tfvars.${site_code}"
    
    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    log "Deploying $platform infrastructure for site: $site_code"
    
    cd "$terraform_dir"
    
    if [[ ! -f "$var_file" ]]; then
        error "Configuration file not found: $var_file"
        info "Create it from the example:"
        info "  cd $terraform_dir"
        info "  cp terraform.tfvars.example $var_file"
        info "  # Edit with site-specific settings"
        return 1
    fi
    
    # Initialize Terraform
    terraform init -upgrade
    
    # Create or select workspace for site isolation
    log "Setting up Terraform workspace: $site_code"
    terraform workspace select "$site_code" 2>/dev/null || terraform workspace new "$site_code"
    
    # Plan with site-specific variables
    terraform plan -var-file="$var_file" -out="tfplan-${site_code}"
    
    echo ""
    read -p "Apply Terraform plan? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        warn "Terraform apply cancelled"
        rm -f "tfplan-${site_code}"
        return 1
    fi
    
    terraform apply "tfplan-${site_code}"
    rm -f "tfplan-${site_code}"
    
    log "$platform infrastructure deployed successfully for $site_code"
    
    # Save outputs for reference
    mkdir -p "${PROJECT_ROOT}/clusters/omni"
    terraform output -json > "${PROJECT_ROOT}/clusters/omni/${site_code}-terraform-output.json"
    
    cd "$PROJECT_ROOT"
}

# Wait for VMs to boot and register with Omni
wait_for_machines() {
    local site_code=$1
    local expected_count=$2
    local timeout=300
    local elapsed=0
    
    log "Waiting for $site_code machines to register with Omni (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        # Count total machines (could filter by labels in future)
        local count=$(omnictl get machines --quiet 2>/dev/null | wc -l)
        
        if [[ $count -ge $expected_count ]]; then
            log "At least $expected_count machines registered with Omni"
            return 0
        fi
        
        echo -n "."
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    error "Timeout waiting for machines to register"
    warn "Check that VMs can reach $OMNI_ENDPOINT"
    return 1
}

# Apply Omni cluster configuration
apply_omni_config() {
    local site_code=$1
    local cluster_file=$2
    
    if [[ ! -f "$cluster_file" ]]; then
        error "Cluster file not found: $cluster_file"
        return 1
    fi
    
    log "Applying Omni cluster configuration for $site_code: $(basename "$cluster_file")"
    
    omnictl apply -f "$cluster_file"
    
    log "Cluster configuration applied. Check status with: omnictl get clusters"
}

# Get kubeconfig for cluster
get_kubeconfig() {
    local site_code=$1
    local cluster_name=$2
    local kubeconfig_file="${PROJECT_ROOT}/kubeconfig-${site_code}"
    
    log "Retrieving kubeconfig for cluster: $cluster_name"
    
    # Wait a moment for cluster to be ready
    sleep 5
    
    if omnictl kubeconfig "$cluster_name" > "$kubeconfig_file" 2>/dev/null; then
        log "✓ Kubeconfig saved to: $kubeconfig_file"
        info "Use it with: export KUBECONFIG=$kubeconfig_file"
        return 0
    else
        warn "Could not retrieve kubeconfig yet. Cluster may still be provisioning."
        warn "Try later with: omnictl kubeconfig $cluster_name > kubeconfig-$site_code"
        return 1
    fi
}

# Main deployment workflow
main() {
    # Parse arguments
    if [[ $# -lt 2 ]]; then
        error "Missing required arguments"
        echo ""
        usage
    fi
    
    local site_code=$1
    local platform=$2
    local cluster_file=${3:-}
    
    # Convert site code to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    # Validate platform
    if [[ "$platform" != "vsphere" && "$platform" != "proxmox" ]]; then
        error "Invalid platform: $platform"
        error "Must be: vsphere or proxmox"
        usage
    fi
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    Talos Hybrid GitOps - Infrastructure Deployment        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site:${NC}     $site_code"
    echo -e "${BLUE}Platform:${NC} $platform"
    if [[ -n "$cluster_file" ]]; then
        echo -e "${BLUE}Cluster:${NC}  $(basename "$cluster_file")"
    fi
    echo ""
    
    validate_site_code "$site_code"
    check_prerequisites
    
    # Step 1: Deploy infrastructure with Terraform
    log "=== Step 1: Deploy Infrastructure ==="
    deploy_terraform "$site_code" "$platform" || {
        error "Terraform deployment failed"
        exit 1
    }
    
    # Step 2: Wait for machines to register with Omni
    log "=== Step 2: Wait for Machine Registration ==="
    warn "Machines should boot and auto-register with Omni"
    warn "Make sure VMs can reach ${OMNI_ENDPOINT}"
    
    # Get expected node count from terraform output
    local terraform_dir="${PROJECT_ROOT}/terraform/${platform}"
    cd "$terraform_dir"
    local node_count=$(terraform output -json 2>/dev/null | jq -r '.node_count.value // 3' || echo "3")
    cd "$PROJECT_ROOT"
    
    info "Expecting $node_count machines to register"
    wait_for_machines "$site_code" "$node_count" || {
        warn "Not all machines registered, but continuing..."
    }
    
    # Step 3: Show registered machines
    log "=== Step 3: Registered Machines ==="
    omnictl get machines || warn "Could not list machines"
    echo ""
    info "Label machines if needed:"
    info "  omnictl patch machine <id> --patch '[{\"op\":\"add\",\"path\":\"/metadata/labels/site\",\"value\":\"$site_code\"}]'"
    
    # Step 4: Apply cluster configuration
    if [[ -n "$cluster_file" ]]; then
        log "=== Step 4: Apply Cluster Configuration ==="
        apply_omni_config "$site_code" "$cluster_file" || {
            error "Cluster configuration failed"
            exit 1
        }
        
        # Try to extract cluster name from file
        local cluster_name=$(basename "$cluster_file" .yaml)
        
        # Step 5: Get kubeconfig
        log "=== Step 5: Retrieve Kubeconfig ==="
        get_kubeconfig "$site_code" "$cluster_name" || {
            warn "Kubeconfig retrieval failed - cluster may still be provisioning"
        }
    else
        log "=== Step 4: Manual Cluster Configuration ==="
        warn "No cluster file specified. Apply manually with:"
        warn "  omnictl apply -f clusters/omni/${site_code}-cluster.yaml"
    fi
    
    # Summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Deployment Complete!                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Site: $site_code | Platform: $platform"
    echo ""
    log "Next steps:"
    log "  1. Check cluster status:"
    log "     ${GREEN}omnictl get clusters${NC}"
    echo ""
    log "  2. Monitor cluster provisioning:"
    log "     ${GREEN}omnictl get machines${NC}"
    echo ""
    if [[ -f "${PROJECT_ROOT}/kubeconfig-${site_code}" ]]; then
        log "  3. Use kubeconfig:"
        log "     ${GREEN}export KUBECONFIG=${PROJECT_ROOT}/kubeconfig-${site_code}${NC}"
        log "     ${GREEN}kubectl get nodes${NC}"
    else
        log "  3. Get kubeconfig when ready:"
        log "     ${GREEN}omnictl kubeconfig <cluster-name> > kubeconfig-${site_code}${NC}"
    fi
    echo ""
    log "  4. Bootstrap Flux (optional):"
    log "     ${GREEN}flux bootstrap github --owner=<user> --repository=<repo> ...${NC}"
    echo ""
}

main "$@"
