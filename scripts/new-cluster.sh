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
  --control-planes <n>   Number of control plane nodes (default: 1)
  --workers <n>          Number of worker nodes (default: 3)
  --cpu <n>              CPU cores per node (default: 4)
  --memory <mb>          Memory in MB per node (default: 8192)
  --disk <gb>            Disk size in GB per node (default: 50)
  --k8s-version <ver>    Kubernetes version (default: v1.32.0)
  --talos-version <ver>  Talos version (default: v1.11.5)
  --help                 Show this help message

${GREEN}Note:${NC}
  Platform is automatically detected from site configuration.
  terraform.tfvars.{site} is automatically updated with accumulated totals:
    - node_count: sum of all cluster nodes
    - cpu/memory/disk: maximum values across all clusters

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
    
    # Strip 'v' prefix from versions if present
    local k8s_ver="${k8s_version#v}"
    local talos_ver="${talos_version#v}"
    
    cat > "$yaml_file" <<EOF
---
# Cluster: ${full_cluster_name}
# Site: ${site_code}
# Environment: ${environment}
# Created: $(date)
#
# Apply instructions:
#   ./scripts/apply-cluster.sh ${cluster_name}.yaml
#
# This will create all resources: MachineClasses, Cluster, and MachineSets

---
# Control plane machine class
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: ${full_cluster_name}-control-plane
spec:
  matchlabels:
    - site = ${site_code}
    - platform = ${platform}

---
# Worker machine class
metadata:
  namespace: default
  type: MachineClasses.omni.sidero.dev
  id: ${full_cluster_name}-worker
spec:
  matchlabels:
    - site = ${site_code}
    - platform = ${platform}

---
# Cluster resource
metadata:
  namespace: default
  type: Clusters.omni.sidero.dev
  id: ${full_cluster_name}
spec:
  kubernetesversion: ${k8s_ver}
  talosversion: ${talos_ver}
  features:
    enableworkloadproxy: true
    diskencryption: false
    useembeddeddiscoveryservice: true

---
# Control plane machine set
metadata:
  namespace: default
  type: MachineSets.omni.sidero.dev
  id: ${full_cluster_name}-control-planes
  labels:
    omni.sidero.dev/cluster: ${full_cluster_name}
    omni.sidero.dev/role-controlplane: ""
spec:
  cluster: ${full_cluster_name}
  machineclass:
    name: ${full_cluster_name}-control-plane
    machinecount: ${control_planes}
    allocationstrategy:
      type: static
    requirements:
      - key: site
        operator: In
        values:
          - ${site_code}
      - key: platform
        operator: In
        values:
          - ${platform}
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
metadata:
  namespace: default
  type: MachineSets.omni.sidero.dev
  id: ${full_cluster_name}-workers
  labels:
    omni.sidero.dev/cluster: ${full_cluster_name}
    omni.sidero.dev/role-worker: ""
spec:
  cluster: ${full_cluster_name}
  machineclass:
    name: ${full_cluster_name}-worker
    machinecount: ${workers}
    allocationstrategy:
      type: static
    requirements:
      - key: site
        operator: In
        values:
          - ${site_code}
      - key: platform
        operator: In
        values:
          - ${platform}
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

# Update terraform.tfvars with node configuration
update_terraform_tfvars() {
    local site_code=$1
    local platform=$2
    local total_nodes=$3
    local cpu=$4
    local memory=$5
    local disk=$6
    local accumulate=${7:-false}
    
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
    local control_planes=1
    local workers=3
    local cpu=4
    local memory=8192
    local disk=50
    local k8s_version="v1.32.0"
    local talos_version="v1.11.5"
    
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
    
    # Always update terraform.tfvars with accumulated totals
    echo ""
    log "Updating Terraform configuration..."
    update_terraform_tfvars "$site_code" "$platform" "$total_nodes" "$cpu" "$memory" "$disk" "true"
    
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
    log "  1. Review terraform configuration:"
    log "     ${GREEN}cat terraform/${platform}/terraform.tfvars.${site_code}${NC}"
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
