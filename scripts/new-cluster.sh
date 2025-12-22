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
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/site-${site_code}.yaml"
    
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

# Load size class definitions from CSV
load_size_classes() {
    local csv_file="${PROJECT_ROOT}/clusters/size_classes.csv"
    
    if [[ ! -f "$csv_file" ]]; then
        error "Size class definitions not found: $csv_file"
        return 1
    fi
    
    # Read CSV into associative arrays (skip header and comments)
    declare -g -A SIZE_CLASS_CPU
    declare -g -A SIZE_CLASS_MEMORY
    declare -g -A SIZE_CLASS_DESC
    declare -g -a SIZE_CLASS_ORDER
    
    while IFS=',' read -r class class_cpu class_memory desc; do
        # Skip comments and header
        [[ "$class" =~ ^#.*$ ]] && continue
        [[ "$class" == "size_class" ]] && continue
        [[ -z "$class" ]] && continue
        
        SIZE_CLASS_CPU[$class]=$class_cpu
        SIZE_CLASS_MEMORY[$class]=$class_memory
        SIZE_CLASS_DESC[$class]=$desc
        SIZE_CLASS_ORDER+=("$class")
    done < "$csv_file"
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
  --control-planes <n>     Number of control plane nodes (default: 1)
  --workers <n>            Number of worker nodes (default: 3)
  --size-class <CPUxMEM>   Size class in CPUxMEMORY format (default: 2x4)
                           Examples: 2x4, 4x8, 8x16, 16x32
  --disk <gb>              Disk size in GB per node (default: 50)
  --k8s-version <ver>      Kubernetes version (default: v1.30.0)
  --talos-version <ver>    Talos version (default: v1.9.0)
  --interactive, -i        Interactive mode with prompts (currently disabled)
  --force, -f              Overwrite existing cluster configuration
  --help                   Show this help message

${GREEN}Size Class Format:${NC}
  CPUxMEMORY where MEMORY is in GB
  
  Common sizes:
    2x4    - 2 CPU, 4GB RAM   (dev, testing)
    4x8    - 4 CPU, 8GB RAM   (staging, light workloads)
    8x16   - 8 CPU, 16GB RAM  (production)
    16x32  - 16 CPU, 32GB RAM (large workloads, databases)
  
  Custom sizes allowed: 4x16, 8x32, 12x24, etc.

${GREEN}Note:${NC}
  Platform is automatically detected from site configuration.
  Size class defines both CPU and memory using CPUxMEMORY format (e.g., 2x4 = 2 CPU, 4GB RAM).
  terraform.tfvars.{site} is automatically updated with accumulated totals:
    - node_count: sum of all cluster nodes
    - cpu/memory/disk: maximum values across all clusters

${GREEN}Examples:${NC}
  # Interactive mode (recommended for new users)
  $0 ny1d web --interactive
  $0 ny1d web -i
  
  # Create basic cluster with defaults (1 CP + 3 workers, 2x4 size class)
  $0 ny1d web
  
  # Create cluster with custom sizing using size class
  $0 sf2p data --control-planes 5 --workers 10 --size-class 8x16
  
  # Create small dev cluster
  $0 la1s dev --control-planes 1 --workers 2 --size-class 2x4
  
  # Create large production cluster
  $0 ny1p prod --control-planes 3 --workers 10 --size-class 16x32
  
  # Update existing cluster (interactive mode backs up old file)
  $0 ny1d web -i

${GREEN}Size Class Format:${NC}
  CPUxMEMORY where MEMORY is in GB
  
  Common sizes:
    2x4    - 2 CPU, 4GB RAM   (dev, testing)
    4x8    - 4 CPU, 8GB RAM   (staging, light workloads)
    8x16   - 8 CPU, 16GB RAM  (production)
    16x32  - 16 CPU, 32GB RAM (large workloads, databases)

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

# Parse size class from CPUxMEMORY format
parse_size_class() {
    local size_class=$1
    
    if [[ ! "$size_class" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        error "Invalid size class format: $size_class"
        error "Expected format: CPUxMEMORY (e.g., 2x4, 4x8, 8x16)"
        return 1
    fi
    
    local cpu="${BASH_REMATCH[1]}"
    local memory="${BASH_REMATCH[2]}"
    
    # Convert memory from GB to MB
    local memory_mb=$((memory * 1024))
    
    echo "$cpu $memory_mb"
}

# Validate and extract CPU and memory from size class
get_resources_from_size_class() {
    local size_class=$1
    
    local resources
    resources=$(parse_size_class "$size_class")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$resources"
}

# Parse existing cluster YAML to get current values
parse_existing_cluster() {
    local yaml_file=$1
    
    if [[ ! -f "$yaml_file" ]]; then
        return 1
    fi
    
    # Extract values from comments (use || true to handle missing values)
    EXISTING_CP=$(grep -A 10 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Control Planes:" | head -1 | awk '{print $5}' || true)
    EXISTING_WORKERS=$(grep -A 10 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Workers:" | head -1 | awk '{print $4}' || true)
    EXISTING_CPU=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - CPU:" | head -1 | awk '{print $4}' || true)
    EXISTING_MEMORY=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Memory:" | head -1 | awk '{print $4}' || true)
    EXISTING_DISK=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Disk:" | head -1 | awk '{print $4}' || true)
    EXISTING_SIZE=$(grep -A 10 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Size Class:" | head -1 | awk '{print $5}' || true)
    
    export EXISTING_CP EXISTING_WORKERS EXISTING_CPU EXISTING_MEMORY EXISTING_DISK EXISTING_SIZE
}

# Prompt for input with default value
prompt_with_default() {
    local prompt=$1
    local default=$2
    local varname=$3
    
    if [[ -n "$default" ]]; then
        read -r -p "${prompt} [${default}]: " value </dev/tty
        eval "$varname=\"\${value:-$default}\""
    else
        read -r -p "${prompt}: " value </dev/tty
        eval "$varname=\"$value\""
    fi
}

# Interactive mode
interactive_mode() {
    local site_code=$1
    local cluster_name=$2
    local yaml_file="${PROJECT_ROOT}/clusters/omni/${site_code}/cluster-${cluster_name}.yaml"
    
    # Initialize existing variables to empty
    EXISTING_CP=""
    EXISTING_WORKERS=""
    EXISTING_CPU=""
    EXISTING_MEMORY=""
    EXISTING_DISK=""
    EXISTING_SIZE=""
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Talos Hybrid GitOps - Interactive Cluster Setup     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check for existing cluster config
    if [[ -f "$yaml_file" ]]; then
        warn "Existing cluster configuration found: $yaml_file"
        parse_existing_cluster "$yaml_file"
        
        echo ""
        read -r -p "Use existing values as defaults? [Y/n]: " use_existing </dev/tty
        if [[ "$use_existing" =~ ^[Nn] ]]; then
            EXISTING_CP=""
            EXISTING_WORKERS=""
            EXISTING_CPU=""
            EXISTING_MEMORY=""
            EXISTING_DISK=""
            EXISTING_SIZE=""
        fi
    fi
    
    echo ""
    log "Configuring cluster: ${site_code}-${cluster_name}"
    echo ""
    
    # Load size classes
    load_size_classes || {
        error "Failed to load size class definitions"
        exit 1
    }
    
    # Prompt for size class first
    echo -e "${BLUE}Available Size Classes:${NC}"
    local i=1
    for class in "${SIZE_CLASS_ORDER[@]}"; do
        local cpu=${SIZE_CLASS_CPU[$class]}
        local mem=${SIZE_CLASS_MEMORY[$class]}
        local desc=${SIZE_CLASS_DESC[$class]}
        if [[ $cpu -eq 999 ]]; then
            printf "  %d) %-8s - %s\n" "$i" "$class" "$desc"
        else
            printf "  %d) %-8s - ≤%d CPU, ≤%dGB - %s\n" "$i" "$class" "$cpu" "$((mem / 1024))" "$desc"
        fi
        ((i++))
    done
    echo ""
    
    # Determine default size class selection
    local default_size_idx=3  # medium by default
    if [[ -n "$EXISTING_SIZE" ]]; then
        for idx in "${!SIZE_CLASS_ORDER[@]}"; do
            if [[ "${SIZE_CLASS_ORDER[$idx]}" == "$EXISTING_SIZE" ]]; then
                default_size_idx=$((idx + 1))
                break
            fi
        done
    fi
    
    prompt_with_default "Select size class (1-${#SIZE_CLASS_ORDER[@]})" "$default_size_idx" selected_idx
    
    # Validate and set size class
    if [[ $selected_idx -lt 1 || $selected_idx -gt ${#SIZE_CLASS_ORDER[@]} ]]; then
        error "Invalid selection"
        exit 1
    fi
    
    local size_class="${SIZE_CLASS_ORDER[$((selected_idx - 1))]}"
    local preset_cpu=${SIZE_CLASS_CPU[$size_class]}
    local preset_memory=${SIZE_CLASS_MEMORY[$size_class]}
    
    # Adjust preset values for xlarge/huge
    [[ $preset_cpu -eq 999 ]] && preset_cpu=16
    [[ $preset_memory -eq 999999 ]] && preset_memory=65536
    
    info "Selected size class: $size_class"
    echo ""
    
    # Prompt for cluster topology
    echo -e "${BLUE}Cluster Topology:${NC}"
    prompt_with_default "Control plane nodes" "${EXISTING_CP:-1}" control_planes
    prompt_with_default "Worker nodes" "${EXISTING_WORKERS:-3}" workers
    echo ""
    
    # Prompt for node resources
    echo -e "${BLUE}Per-Node Resources:${NC}"
    prompt_with_default "CPU cores" "${EXISTING_CPU:-$preset_cpu}" cpu
    prompt_with_default "Memory (MB)" "${EXISTING_MEMORY:-$preset_memory}" memory
    prompt_with_default "Disk size (GB)" "${EXISTING_DISK:-50}" disk
    echo ""
    
    # Prompt for versions
    echo -e "${BLUE}Software Versions:${NC}"
    prompt_with_default "Kubernetes version" "v1.30.0" k8s_version
    prompt_with_default "Talos version" "v1.11.5" talos_version
    echo ""
    
    # Export values for main function
    export INTERACTIVE_MODE=true
    export INTERACTIVE_CP="$control_planes"
    export INTERACTIVE_WORKERS="$workers"
    export INTERACTIVE_CPU="$cpu"
    export INTERACTIVE_MEMORY="$memory"
    export INTERACTIVE_DISK="$disk"
    export INTERACTIVE_SIZE="$size_class"
    export INTERACTIVE_K8S="$k8s_version"
    export INTERACTIVE_TALOS="$talos_version"
    
    # If existing file, move it out of the way
    if [[ -f "$yaml_file" ]]; then
        local backup_file="${yaml_file}.backup-$(date +%Y%m%d-%H%M%S)"
        log "Moving existing file to: $backup_file"
        mv "$yaml_file" "$backup_file"
    fi
}

# Create cluster YAML using Cluster Template format
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
    local size_class=${11}
    
    local full_cluster_name="${site_code}-${cluster_name}"
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    local yaml_file="${site_dir}/cluster-${cluster_name}.yaml"
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
    
    # Create cluster template YAML
    cat > "$yaml_file" <<EOF
---
# Cluster Template: ${full_cluster_name}
# Site: ${site_code}
# Environment: ${environment}
# Created: $(date)
#
# Apply with omnictl cluster template:
#   omnictl cluster template sync -f cluster-${cluster_name}.yaml
#
# Or use the helper script:
#   ./scripts/apply-cluster.sh cluster-${cluster_name}.yaml

kind: Cluster
name: ${full_cluster_name}
kubernetes:
  version: v${k8s_ver}
talos:
  version: v${talos_ver}
features:
  enableWorkloadProxy: true
  diskEncryption: false
  useEmbeddedDiscoveryService: true

---
kind: ControlPlane
machineClass:
  name: ${full_cluster_name}-cp
  size: ${control_planes}
  matchLabels:
    site: ${site_code}
    platform: ${platform}
    size: ${size_class}

---
kind: Workers
machineClass:
  name: ${full_cluster_name}-workers
  size: ${workers}
  matchLabels:
    site: ${site_code}
    platform: ${platform}
    size: ${size_class}

---
# Resource requirements for Terraform
# These values should match your terraform.tfvars configuration

# Node specifications:
# - Control Planes: ${control_planes}
# - Workers: ${workers}
# - Total Nodes: $((control_planes + workers))
# - Size Class: ${size_class}
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

# Update terraform/${platform}/terraform.tfvars.${site_code}:
#   node_count     = $((control_planes + workers))
#   node_cpu       = ${cpu}
#   node_memory    = ${memory}
#   node_disk_size = ${disk}

# To add machine patches, create separate patch files:
# 1. Create patches/${full_cluster_name}-patch.yaml with Talos machine config
# 2. Add to template:
#    patches:
#      - file: patches/${full_cluster_name}-patch.yaml
EOF
    
    log "✓ Created: $yaml_file"
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
            local nodes=$(grep -A 10 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Total Nodes:" | head -1 | awk '{print $5}' || true)
            local cpu=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - CPU:" | head -1 | awk '{print $4}' || true)
            local memory=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Memory:" | head -1 | awk '{print $4}' || true)
            local disk=$(grep -A 10 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Disk:" | head -1 | awk '{print $4}' || true)
            
            # Validate that values are numeric
            if [[ -n "$nodes" && "$nodes" =~ ^[0-9]+$ ]] && \
               [[ -n "$cpu" && "$cpu" =~ ^[0-9]+$ ]] && \
               [[ -n "$memory" && "$memory" =~ ^[0-9]+$ ]] && \
               [[ -n "$disk" && "$disk" =~ ^[0-9]+$ ]]; then
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
        local calc_nodes calc_cpu calc_memory calc_disk
        read -r calc_nodes calc_cpu calc_memory calc_disk <<< "$totals"
        
        if [[ $calc_nodes -eq 0 ]]; then
            warn "No cluster configurations found, using provided values"
            # Keep the provided values as-is
        else
            # Use calculated values
            total_nodes=$calc_nodes
            cpu=$calc_cpu
            memory=$calc_memory
            disk=$calc_disk
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
    local size_class="2x4"  # Default: 2 CPU, 4GB RAM
    local cpu=""
    local memory=""
    local disk=50
    local k8s_version="v1.30.0"
    local talos_version="v1.9.0"
    local interactive=false
    local force_overwrite=false
    
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
            --size-class)
                size_class="$2"
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
            --interactive|-i)
                interactive=true
                shift
                ;;
            --force|-f)
                force_overwrite=true
                shift
                ;;
            --cpu|--memory)
                error "The $1 option is deprecated. Use --size-class instead (e.g., --size-class 2x4)"
                exit 1
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
    
    # Run interactive mode if requested
    if [[ "$interactive" == true ]]; then
        interactive_mode "$site_code" "$cluster_name"
        
        # Use values from interactive mode
        control_planes="$INTERACTIVE_CP"
        workers="$INTERACTIVE_WORKERS"
        size_class="$INTERACTIVE_SIZE"
        disk="$INTERACTIVE_DISK"
        k8s_version="$INTERACTIVE_K8S"
        talos_version="$INTERACTIVE_TALOS"
    fi
    
    # Parse size class to get CPU and memory
    local resources
    resources=$(get_resources_from_size_class "$size_class")
    if [[ $? -ne 0 ]]; then
        error "Invalid size class: $size_class"
        exit 1
    fi
    
    read cpu memory <<< "$resources"
    
    # Load site metadata to get platform
    load_site_metadata "$site_code" || exit 1
    local platform="$PLATFORM"
    
    local full_cluster_name="${site_code}-${cluster_name}"
    local total_nodes=$((control_planes + workers))
    local total_cpu=$((cpu * total_nodes))
    local total_memory_gb=$((memory * total_nodes / 1024))
    local total_disk=$((disk * total_nodes))
    
    # Skip summary in interactive mode (already shown)
    if [[ "$interactive" != true ]]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║        Talos Hybrid GitOps - New Cluster Setup            ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Site:${NC}            $site_code ($(get_environment "$site_code"))"
        echo -e "${BLUE}Cluster Name:${NC}    $cluster_name"
        echo -e "${BLUE}Full Name:${NC}       $full_cluster_name"
        echo -e "${BLUE}Platform:${NC}        $platform"
        echo -e "${BLUE}Size Class:${NC}      $size_class"
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
    fi
    
    validate_site_code "$site_code"
    
    # Note: load_site_metadata is already called above to get platform
    
    validate_cluster_name "$cluster_name"
    
    # Check if cluster already exists (skip if interactive or force mode)
    local yaml_file="${PROJECT_ROOT}/clusters/omni/${site_code}/cluster-${cluster_name}.yaml"
    if [[ -f "$yaml_file" && "$interactive" != true && "$force_overwrite" != true ]]; then
        error "Cluster configuration already exists: $yaml_file"
        error "Use --force/-f to overwrite, or --interactive/-i to update"
        exit 1
    fi
    
    # Backup existing file if force overwrite
    if [[ -f "$yaml_file" && "$force_overwrite" == true ]]; then
        local backup_file="${yaml_file}.backup-$(date +%Y%m%d-%H%M%S)"
        log "Backing up existing file to: $backup_file"
        cp "$yaml_file" "$backup_file"
    fi
    
    # Create cluster configuration
    create_cluster_yaml "$site_code" "$cluster_name" "$control_planes" "$workers" \
        "$cpu" "$memory" "$disk" "$k8s_version" "$talos_version" "$platform" "$size_class"
    
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
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  IMPORTANT: Label Machines After Deployment               ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    warn "After VMs boot and register with Omni (2-5 minutes):"
    echo ""
    echo "  1. Label each machine in Omni UI with:"
    echo "     ${GREEN}${site_code}, ${platform}, ${size_class}${NC}"
    echo ""
    echo "  2. Check machine status:"
    echo "     ${GREEN}./scripts/check-machines.sh $yaml_file${NC}"
    echo ""
    echo "  Size Class Format: CPUxMEMORY (e.g., 2x4, 4x8, 8x16)"
    echo "  Must match the actual VM resources exactly"
    echo ""
}

main "$@"
