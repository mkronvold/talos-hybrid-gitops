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

# Load site metadata
load_site_metadata() {
    local site_code=$1
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/.site-metadata"
    
    if [[ ! -f "$metadata_file" ]]; then
        error "Site metadata not found: $metadata_file"
        error "Site may not exist or was not created with new-site.sh"
        return 1
    fi
    
    source "$metadata_file"
    
    if [[ -z "${PLATFORM:-}" ]]; then
        error "Platform not defined in site metadata"
        return 1
    fi
    
    log "✓ Loaded site metadata: $site_code (platform: $PLATFORM)"
}

# Usage information
usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <site-code> [cluster-file] [options]

${YELLOW}Deploy infrastructure and Talos clusters for a specific site.${NC}

${GREEN}Arguments:${NC}
  site-code     Site identifier (e.g., ny1d, sf2p, la1s)
  cluster-file  (Optional) Path to Omni cluster YAML configuration

${GREEN}Note:${NC}
  Platform (vsphere/proxmox) is automatically detected from site configuration.
  terraform.tfvars.{site} is automatically updated with accumulated totals:
    - node_count: sum of all cluster nodes
    - cpu/memory/disk: maximum values across all clusters

${GREEN}Site Code Format:${NC}
  <city><zone><env>
  
  Examples:
    ny1d - New York, Zone 1, Dev
    sf2p - San Francisco, Zone 2, Prod
    la1s - Los Angeles, Zone 1, Staging

${GREEN}Examples:${NC}
  # Deploy NY Zone 1 Dev cluster (platform auto-detected)
  $0 ny1d clusters/omni/ny1d/web.yaml
  
  # Deploy SF Zone 2 Prod cluster (platform auto-detected)
  $0 sf2p clusters/omni/sf2p/data.yaml
  
  # Deploy infrastructure only (manual cluster config later)
  $0 la1s

${GREEN}Required Environment Variables:${NC}
  OMNI_ENDPOINT            - Omni API endpoint (https://damocles.na-west-1.omni.siderolabs.io)
  OMNI_SERVICE_ACCOUNT_KEY - Omni service account key

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
        error "OMNI_ENDPOINT not set. Export OMNI_ENDPOINT=<omni-endpoint-url>"
        missing=1
    fi
    
    if [[ -z "${OMNI_SERVICE_ACCOUNT_KEY:-}" ]]; then
        error "OMNI_SERVICE_ACCOUNT_KEY not set. Get your service account key from Omni and export OMNI_SERVICE_ACCOUNT_KEY=<key>"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Calculate total requirements across all clusters for a site
calculate_site_totals() {
    local site_code=$1
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    
    local total_nodes=0
    local max_cpu=0
    local max_memory=0
    local max_disk=0
    
    # Parse all cluster YAML files for this site
    if [[ -d "$site_dir" ]]; then
        while IFS= read -r yaml_file; do
            [[ -f "$yaml_file" ]] || continue
            
            # Extract values from cluster file comments (Per-node resources section only)
            local nodes=$(grep -A 10 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Total Nodes:" | head -1 | awk '{print $5}')
            local cpu=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - CPU:" | head -1 | awk '{print $4}')
            local memory=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Memory:" | head -1 | awk '{print $4}')
            local disk=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Disk:" | head -1 | awk '{print $4}')
            
            if [[ -n "$nodes" && -n "$cpu" && -n "$memory" && -n "$disk" ]]; then
                total_nodes=$((total_nodes + nodes))
                [[ $cpu -gt $max_cpu ]] && max_cpu=$cpu
                [[ $memory -gt $max_memory ]] && max_memory=$memory
                [[ $disk -gt $max_disk ]] && max_disk=$disk
            fi
        done < <(find "$site_dir" -maxdepth 1 -name "*.yaml" -type f ! -name ".*")
    fi
    
    echo "$total_nodes $max_cpu $max_memory $max_disk"
}

# Extract node configuration from cluster YAML
extract_cluster_config() {
    local cluster_file=$1
    
    if [[ ! -f "$cluster_file" ]]; then
        error "Cluster file not found: $cluster_file"
        return 1
    fi
    
    log "Extracting configuration from: $(basename "$cluster_file")"
    
    # Extract values from comments at the end of the cluster file
    local node_count=$(grep "^# - Total Nodes:" "$cluster_file" | awk '{print $5}')
    local cpu=$(grep "^# - CPU:" "$cluster_file" | awk '{print $4}')
    local memory=$(grep "^# - Memory:" "$cluster_file" | awk '{print $4}')
    local disk=$(grep "^# - Disk:" "$cluster_file" | awk '{print $4}')
    
    # Validate extracted values
    if [[ -z "$node_count" ]] || [[ -z "$cpu" ]] || [[ -z "$memory" ]] || [[ -z "$disk" ]]; then
        warn "Could not extract all values from cluster file"
        info "Expected format in cluster file comments:"
        info "# - Total Nodes: <count>"
        info "# - CPU: <cores> cores"
        info "# - Memory: <mb> MB"
        info "# - Disk: <gb> GB"
        return 1
    fi
    
    echo "$node_count $cpu $memory $disk"
    return 0
}

# Update terraform.tfvars with node configuration
update_terraform_tfvars() {
    local site_code=$1
    local platform=$2
    local total_nodes=$3
    local cpu=$4
    local memory=$5
    local disk=$6
    local accumulate=${7:-true}
    
    local terraform_dir="${PROJECT_ROOT}/terraform/${platform}"
    local tfvars_file="${terraform_dir}/terraform.tfvars.${site_code}"
    
    if [[ ! -f "$tfvars_file" ]]; then
        warn "Terraform tfvars file not found: $tfvars_file"
        warn "Cannot update node configuration automatically"
        return 1
    fi
    
    log "Updating Terraform configuration: $tfvars_file"
    
    # If accumulating, calculate totals from all cluster files
    if [[ "$accumulate" == "true" ]]; then
        info "Calculating total requirements across all clusters for site $site_code..."
        local totals=$(calculate_site_totals "$site_code")
        read -r total_nodes cpu memory disk <<< "$totals"
        
        if [[ $total_nodes -eq 0 ]]; then
            warn "No cluster configurations found, using provided values"
            total_nodes=$3
            cpu=$4
            memory=$5
            disk=$6
        fi
    fi
    
    # Create backup
    cp "$tfvars_file" "${tfvars_file}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Update node_count
    if grep -q "^node_count" "$tfvars_file"; then
        sed -i "s/^node_count[[:space:]]*=.*/node_count     = ${total_nodes}/" "$tfvars_file"
    else
        echo "node_count     = ${total_nodes}" >> "$tfvars_file"
    fi
    
    # Update node_cpu (use max across all clusters)
    if grep -q "^node_cpu" "$tfvars_file"; then
        sed -i "s/^node_cpu[[:space:]]*=.*/node_cpu       = ${cpu}/" "$tfvars_file"
    else
        echo "node_cpu       = ${cpu}" >> "$tfvars_file"
    fi
    
    # Update node_memory (use max across all clusters)
    if grep -q "^node_memory" "$tfvars_file"; then
        sed -i "s/^node_memory[[:space:]]*=.*/node_memory    = ${memory}/" "$tfvars_file"
    else
        echo "node_memory    = ${memory}" >> "$tfvars_file"
    fi
    
    # Update node_disk_size (use max across all clusters)
    if grep -q "^node_disk_size" "$tfvars_file"; then
        sed -i "s/^node_disk_size[[:space:]]*=.*/node_disk_size = ${disk}/" "$tfvars_file"
    else
        echo "node_disk_size = ${disk}" >> "$tfvars_file"
    fi
    
    log "✓ Updated Terraform variables:"
    log "    node_count     = ${total_nodes} (sum of all clusters)"
    log "    node_cpu       = ${cpu} (max across clusters)"
    log "    node_memory    = ${memory} (max across clusters)"
    log "    node_disk_size = ${disk} (max across clusters)"
    
    return 0
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
    local timeout=600
    local elapsed=0
    
    log "Waiting for $expected_count unused ready machines for site $site_code (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        # Count ready machines that are:
        # 1. Available (ready-to-use label present)
        # 2. Not assigned to a cluster
        # 3. Optionally match site label if present
        local count=$(omnictl get machinestatus -o json 2>/dev/null | jq -s '
            [.[] | select(
                (.metadata.labels | has("omni.sidero.dev/ready-to-use")) and
                .spec.cluster == ""
            )] | length
        ' 2>/dev/null || echo "0")
        
        if [[ $count -ge $expected_count ]]; then
            log "✓ Found $count unused ready machines (need $expected_count)"
            return 0
        fi
        
        echo -n "."
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    error "Timeout waiting for machines to register"
    warn "Check that VMs can reach $OMNI_ENDPOINT"
    warn "Current unused ready machines: $(omnictl get machinestatus -o json 2>/dev/null | jq -s '[.[] | select((.metadata.labels | has("omni.sidero.dev/ready-to-use")) and .spec.cluster == "")] | length' 2>/dev/null || echo "0")"
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
    
    "${SCRIPT_DIR}/apply-cluster.sh" "$cluster_file"
    
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
    if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        if [[ $# -lt 1 ]]; then
            error "Missing required arguments"
            echo ""
        fi
        usage
    fi
    
    local site_code=$1
    local cluster_file=${2:-}
    
    # Convert site code to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    # Load site metadata to get platform
    load_site_metadata "$site_code" || exit 1
    
    local platform="$PLATFORM"
    
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
    
    # Always update tfvars from all cluster files
    log "=== Updating Terraform Configuration ==="
    info "Calculating total requirements across all clusters for site $site_code..."
    local totals=$(calculate_site_totals "$site_code")
    read -r node_count cpu memory disk <<< "$totals"
    
    if [[ $node_count -gt 0 ]]; then
        update_terraform_tfvars "$site_code" "$platform" "$node_count" "$cpu" "$memory" "$disk" "true"
    else
        warn "No cluster configurations found for site $site_code"
        warn "Skipping tfvars update"
    fi
    echo ""
    
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
    local output_file="${PROJECT_ROOT}/clusters/omni/${site_code}-terraform-output.json"
    local node_count=4
    
    if [[ -f "$output_file" ]]; then
        node_count=$(jq -r '.omni_registration_info.value.node_count // 3' "$output_file" 2>/dev/null || echo "4")
    else
        warn "Terraform output file not found, defaulting to $node_count nodes"
    fi
    
    info "Expecting $node_count unused ready machines for $site_code"
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
        warn "  ./scripts/apply-cluster.sh clusters/omni/${site_code}/<cluster>.yaml"
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
