#!/usr/bin/env bash

set -euo pipefail

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
${GREEN}Usage:${NC} $0 <site-code> <cluster-name> [options]

${YELLOW}Create a new Omni cluster configuration for a site.${NC}

${GREEN}Arguments:${NC}
  site-code      Site identifier (e.g., ny1d, sf2p)
  cluster-name   Cluster name (e.g., web, data, ml)

${GREEN}Options:${NC}
  --control-planes <n>   Number of control plane nodes (default: 3)
  --workers <n>          Number of worker nodes (default: 3)
  --cpu <n>              CPU cores per node (default: 4)
  --memory <mb>          Memory in MB per node (default: 8192)
  --disk <gb>            Disk size in GB per node (default: 100)
  --k8s-version <ver>    Kubernetes version (default: v1.29.0)
  --talos-version <ver>  Talos version (default: v1.9.5)
  --help                 Show this help message

${GREEN}Note:${NC}
  Platform is automatically detected from site configuration.

${GREEN}Examples:${NC}
  # Create basic cluster with defaults (3 CP + 3 workers)
  $0 ny1d web
  
  # Create cluster with custom sizing
  $0 sf2p data --control-planes 5 --workers 10 --cpu 8 --memory 16384
  
  # Create small dev cluster
  $0 la1s dev --control-planes 1 --workers 2 --cpu 2 --memory 4096

${GREEN}Generated Files:${NC}
  clusters/omni/<site-code>/<cluster-name>.yaml

${GREEN}Cluster Naming:${NC}
  Full cluster name will be: <site-code>-<cluster-name>
  Examples:
    ny1d-web  (NY Zone 1 Dev, web cluster)
    sf2p-data (SF Zone 2 Prod, data cluster)

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
        usage
    fi
}

# Validate cluster name
validate_cluster_name() {
    local name=$1
    
    if ! [[ $name =~ ^[a-z0-9-]+$ ]]; then
        error "Invalid cluster name: $name"
        error "Must contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
}

# Parse environment from site code
get_environment() {
    local site_code=$1
    local env_char="${site_code: -1}"
    
    case $env_char in
        d) echo "development" ;;
        s) echo "staging" ;;
        p) echo "production" ;;
        *) echo "unknown" ;;
    esac
}

# Create cluster YAML
create_cluster_yaml() {
    local site_code=$1
    local cluster_name=$2
    local control_planes=$3
    local workers=$4
    local cpu=$5
    local memory=$6
    local disk=$7
    local k8s_version=$8
    local talos_version=$9
    local platform=${10}
    
    local full_cluster_name="${site_code}-${cluster_name}"
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    local yaml_file="${site_dir}/${cluster_name}.yaml"
    local environment=$(get_environment "$site_code")
    
    # Ensure site directory exists
    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
        error "Create the site first with: ./scripts/new-site.sh $site_code"
        exit 1
    fi
    
    log "Creating cluster configuration: $full_cluster_name"
    
    cat > "$yaml_file" <<EOF
---
# Cluster: ${full_cluster_name}
# Site: ${site_code}
# Environment: ${environment}
# Created: $(date)

apiVersion: v1alpha1
kind: Cluster
name: ${full_cluster_name}
labels:
  site: ${site_code}
  environment: ${environment}
  platform: ${platform}
  cluster: ${cluster_name}
kubernetes:
  version: ${k8s_version}
talos:
  version: ${talos_version}
features:
  enableWorkloadProxy: true
  diskEncryption: false
  useEmbeddedDiscoveryService: true

---
# Control plane machine set
apiVersion: v1alpha1
kind: MachineSet
name: ${full_cluster_name}-control-planes
cluster: ${full_cluster_name}
machineClass:
  name: control-plane
  machineCount: ${control_planes}
  
  # Machine allocation strategy
  allocationStrategy:
    type: static  # Manually assign machines via Omni UI or labels
  
  # Machine requirements
  requirements:
    - key: "site"
      operator: "In"
      values: ["${site_code}"]
    - key: "platform"
      operator: "In"
      values: ["${platform}"]

patches:
  - |
    machine:
      install:
        disk: /dev/sda
      kubelet:
        nodeIP:
          validSubnets:
            - 0.0.0.0/0  # Use primary interface IP
        extraArgs:
          rotate-server-certificates: "true"
      network:
        interfaces:
          - interface: eth0
            dhcp: true
      time:
        servers:
          - time.cloudflare.com
          - time.google.com
    cluster:
      controllerManager:
        extraArgs:
          bind-address: "0.0.0.0"
      scheduler:
        extraArgs:
          bind-address: "0.0.0.0"
      apiServer:
        certSANs:
          - ${full_cluster_name}.local
          - ${full_cluster_name}.example.com
      proxy:
        disabled: false
      discovery:
        enabled: true
        registries:
          service:
            disabled: false

---
# Worker machine set
apiVersion: v1alpha1
kind: MachineSet
name: ${full_cluster_name}-workers
cluster: ${full_cluster_name}
machineClass:
  name: worker
  machineCount: ${workers}
  
  allocationStrategy:
    type: static
  
  requirements:
    - key: "site"
      operator: "In"
      values: ["${site_code}"]
    - key: "platform"
      operator: "In"
      values: ["${platform}"]

patches:
  - |
    machine:
      install:
        disk: /dev/sda
      kubelet:
        nodeIP:
          validSubnets:
            - 0.0.0.0/0
        extraArgs:
          rotate-server-certificates: "true"
      network:
        interfaces:
          - interface: eth0
            dhcp: true
      time:
        servers:
          - time.cloudflare.com
          - time.google.com

---
# Resource requirements for Terraform
# These values should match your terraform.tfvars configuration

# Node specifications:
# - Control Planes: ${control_planes}
# - Workers: ${workers}
# - Total Nodes: $((control_planes + workers))
#
# Per-node resources:
# - CPU: ${cpu} cores
# - Memory: ${memory} MB
# - Disk: ${disk} GB
#
# Total resources:
# - CPU: $((cpu * (control_planes + workers))) cores
# - Memory: $((memory * (control_planes + workers))) MB ($((memory * (control_planes + workers) / 1024)) GB)
# - Disk: $((disk * (control_planes + workers))) GB

# Update terraform/vsphere/terraform.tfvars.${site_code}:
#   node_count     = $((control_planes + workers))
#   node_cpu       = ${cpu}
#   node_memory    = ${memory}
#   node_disk_size = ${disk}
EOF
    
    log "✓ Created: $yaml_file"
    
    return 0
}

# Update site README with cluster info
update_site_readme() {
    local site_code=$1
    local cluster_name=$2
    local control_planes=$3
    local workers=$4
    
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    local readme_file="${site_dir}/README.md"
    local full_cluster_name="${site_code}-${cluster_name}"
    
    if [[ ! -f "$readme_file" ]]; then
        warn "Site README not found, skipping update"
        return 0
    fi
    
    log "Updating site README..."
    
    # Check if this is the first cluster
    if grep -q "(none yet)" "$readme_file"; then
        # Replace the "none yet" line
        sed -i "s/| (none yet).*/| ${full_cluster_name} | ${control_planes} | ${workers} | not deployed | $(date +%Y-%m-%d) |/" "$readme_file"
    else
        # Add new line before the last table line (which should be empty or end of table)
        sed -i "/^## Notes/i | ${full_cluster_name} | ${control_planes} | ${workers} | not deployed | $(date +%Y-%m-%d) |" "$readme_file"
    fi
    
    log "✓ Updated: $readme_file"
}

# Main function
main() {
    # Parse arguments
    if [[ $# -lt 2 ]]; then
        error "Missing required arguments"
        echo ""
        usage
    fi
    
    local site_code=$1
    local cluster_name=$2
    shift 2
    
    # Convert to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    cluster_name=$(echo "$cluster_name" | tr '[:upper:]' '[:lower:]')
    
    # Default values
    local control_planes=3
    local workers=3
    local cpu=4
    local memory=8192
    local disk=100
    local k8s_version="v1.29.0"
    local talos_version="v1.9.5"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --control-planes)
                control_planes="$2"
                shift 2
                ;;
            --workers)
                workers="$2"
                shift 2
                ;;
            --cpu)
                cpu="$2"
                shift 2
                ;;
            --memory)
                memory="$2"
                shift 2
                ;;
            --disk)
                disk="$2"
                shift 2
                ;;
            --k8s-version)
                k8s_version="$2"
                shift 2
                ;;
            --talos-version)
                talos_version="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Load site metadata to get platform
    load_site_metadata "$site_code" || exit 1
    local platform="$PLATFORM"
    
    local full_cluster_name="${site_code}-${cluster_name}"
    local total_nodes=$((control_planes + workers))
    local total_cpu=$((cpu * total_nodes))
    local total_memory_gb=$((memory * total_nodes / 1024))
    local total_disk=$((disk * total_nodes))
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Talos Hybrid GitOps - New Cluster Setup            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site:${NC}            $site_code ($(get_environment "$site_code"))"
    echo -e "${BLUE}Cluster Name:${NC}    $cluster_name"
    echo -e "${BLUE}Full Name:${NC}       $full_cluster_name"
    echo -e "${BLUE}Platform:${NC}        $platform"
    echo ""
    echo -e "${BLUE}Topology:${NC}"
    echo -e "  Control Planes: $control_planes"
    echo -e "  Workers:        $workers"
    echo -e "  Total Nodes:    $total_nodes"
    echo ""
    echo -e "${BLUE}Node Resources:${NC}"
    echo -e "  CPU:            $cpu cores"
    echo -e "  Memory:         $memory MB ($((memory / 1024)) GB)"
    echo -e "  Disk:           $disk GB"
    echo ""
    echo -e "${BLUE}Total Resources:${NC}"
    echo -e "  CPU:            $total_cpu cores"
    echo -e "  Memory:         $((memory * total_nodes)) MB ($total_memory_gb GB)"
    echo -e "  Disk:           $total_disk GB"
    echo ""
    echo -e "${BLUE}Versions:${NC}"
    echo -e "  Kubernetes:     $k8s_version"
    echo -e "  Talos:          $talos_version"
    echo ""
    
    validate_site_code "$site_code"
    
    # Note: load_site_metadata is already called above to get platform
    
    validate_cluster_name "$cluster_name"
    
    # Check if cluster already exists
    local yaml_file="${PROJECT_ROOT}/clusters/omni/${site_code}/${cluster_name}.yaml"
    if [[ -f "$yaml_file" ]]; then
        error "Cluster configuration already exists: $yaml_file"
        exit 1
    fi
    
    # Create cluster configuration
    create_cluster_yaml "$site_code" "$cluster_name" "$control_planes" "$workers" \
        "$cpu" "$memory" "$disk" "$k8s_version" "$talos_version" "$platform"
    
    # Update site README
    update_site_readme "$site_code" "$cluster_name" "$control_planes" "$workers"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Cluster Configuration Created!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Cluster: $full_cluster_name"
    log "Configuration: $yaml_file"
    echo ""
    log "Next steps:"
    echo ""
    log "  1. Update Terraform configuration with node count and resources:"
    log "     ${GREEN}vim terraform/vsphere/terraform.tfvars.${site_code}${NC}"
    log ""
    log "     Set these values:"
    log "       ${YELLOW}node_count     = ${total_nodes}${NC}"
    log "       ${YELLOW}node_cpu       = ${cpu}${NC}"
    log "       ${YELLOW}node_memory    = ${memory}${NC}"
    log "       ${YELLOW}node_disk_size = ${disk}${NC}"
    echo ""
    log "  2. Review cluster configuration:"
    log "     ${GREEN}cat $yaml_file${NC}"
    echo ""
    log "  3. Deploy infrastructure and cluster:"
    log "     ${GREEN}source ~/omni.sh  # Set credentials if not in ~/.bashrc${NC}"
    log "     ${GREEN}./scripts/deploy-infrastructure.sh ${site_code} $yaml_file${NC}"
    echo ""
}

main "$@"
