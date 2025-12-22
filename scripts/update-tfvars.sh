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

usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <site-code> [platform]

${YELLOW}Update Terraform tfvars file based on cluster configurations.${NC}

This script:
- Reads all cluster YAML files for a site
- Calculates total nodes needed across all clusters
- Determines distinct VM configurations (size classes for CP and workers)
- Updates terraform.tfvars with the appropriate configuration

${GREEN}Arguments:${NC}
  site-code    Site code (e.g., dk1d, ny1p)
  platform     Platform (proxmox or vsphere) - auto-detected from site metadata if omitted

${GREEN}Example:${NC}
  $0 dk1d
  $0 ny1p proxmox

${GREEN}Terraform Configuration:${NC}
The script updates terraform/<platform>/terraform.tfvars.<site-code> with:
  - Total node count (sum across all clusters)
  - List of distinct VM configurations needed
  - Each config specifies: count, cpu, memory, disk, role (controlplane/worker)

${GREEN}Multi-Size Support:${NC}
If you have clusters with different size classes:
  - Cluster A: CP=2x4, Workers=2x4
  - Cluster B: CP=4x8, Workers=8x16

The script will generate configs for each unique combination:
  - Config 1: CP nodes with 2x4
  - Config 2: CP nodes with 4x8
  - Config 3: Worker nodes with 2x4
  - Config 4: Worker nodes with 8x16

EOF
    exit 1
}

# Load site metadata to get platform
load_site_metadata() {
    local site_code=$1
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/site-${site_code}.yaml"
    
    if [[ ! -f "$metadata_file" ]]; then
        error "Site metadata not found: $metadata_file"
        error "Create the site first with: ./scripts/new-site.sh $site_code"
        return 1
    fi
    
    # Source the metadata file to load variables
    source "$metadata_file"
    
    if [[ -z "${PLATFORM:-}" ]]; then
        error "Could not determine platform from site metadata"
        return 1
    fi
    
    log "✓ Loaded site metadata: $site_code (platform: $PLATFORM)"
}

# Parse a cluster YAML file and extract configuration
parse_cluster_yaml() {
    local yaml_file=$1
    
    # Extract from comments in specific sections
    local cp_count=$(grep -A 5 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Control Planes:" | awk '{print $5}' || echo "0")
    local worker_count=$(grep -A 5 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Workers:" | awk '{print $4}' || echo "0")
    local size_class=$(grep -A 5 "^# Node specifications:" "$yaml_file" 2>/dev/null | grep "^# - Size Class:" | awk '{print $5}' || echo "")
    local cpu=$(grep -A 5 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - CPU:" | head -1 | awk '{print $4}' || echo "0")
    local memory=$(grep -A 5 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Memory:" | head -1 | awk '{print $4}' || echo "0")
    local disk=$(grep -A 5 "^# Per-node resources:" "$yaml_file" 2>/dev/null | grep "^# - Disk:" | head -1 | awk '{print $4}' || echo "50")
    
    # Validate that we got required values
    if [[ ! "$cp_count" =~ ^[0-9]+$ ]] || [[ ! "$worker_count" =~ ^[0-9]+$ ]] || \
       [[ ! "$cpu" =~ ^[0-9]+$ ]] || [[ ! "$memory" =~ ^[0-9]+$ ]] || [[ -z "$size_class" ]]; then
        return 1
    fi
    
    echo "$cp_count $worker_count $size_class $cpu $memory $disk"
}

# Calculate VM configurations needed
calculate_vm_configs() {
    local site_code=$1
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    
    # Associative arrays to track unique configurations
    # Key format: "CPUxMEMORY-role"
    declare -A cp_configs
    declare -A worker_configs
    
    # Parse all cluster YAML files
    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
        return 1
    fi
    
    while IFS= read -r yaml_file; do
        [[ -f "$yaml_file" ]] || continue
        
        local cluster_name=$(basename "$yaml_file" .yaml)
        info "Processing cluster: $cluster_name" >&2
        
        local config
        config=$(parse_cluster_yaml "$yaml_file") || {
            warn "Could not parse $yaml_file, skipping" >&2
            continue
        }
        
        read cp_count worker_count size_class cpu memory disk <<< "$config"
        
        if [[ -z "$size_class" ]] || [[ "$size_class" == "0" ]]; then
            warn "No size class found in $cluster_name, skipping" >&2
            continue
        fi
        
        # Track control plane configs
        if [[ $cp_count -gt 0 ]]; then
            local cp_key="${cpu}x$((memory / 1024))-cp"
            if [[ -z "${cp_configs[$cp_key]:-}" ]]; then
                cp_configs[$cp_key]="$cp_count:$cpu:$memory:$disk"
            else
                # Add to existing count
                local existing_count=$(echo "${cp_configs[$cp_key]}" | cut -d: -f1)
                local new_count=$((existing_count + cp_count))
                cp_configs[$cp_key]="$new_count:$cpu:$memory:$disk"
            fi
        fi
        
        # Track worker configs
        if [[ $worker_count -gt 0 ]]; then
            local worker_key="${cpu}x$((memory / 1024))-worker"
            if [[ -z "${worker_configs[$worker_key]:-}" ]]; then
                worker_configs[$worker_key]="$worker_count:$cpu:$memory:$disk"
            else
                # Add to existing count
                local existing_count=$(echo "${worker_configs[$worker_key]}" | cut -d: -f1)
                local new_count=$((existing_count + worker_count))
                worker_configs[$worker_key]="$new_count:$cpu:$memory:$disk"
            fi
        fi
    done < <(find "$site_dir" -maxdepth 1 -name "*.yaml" -type f ! -name "site-*.yaml" ! -name ".*")
    
    # Output configurations
    # Format: count:cpu:memory:disk:role
    local total_nodes=0
    
    for key in "${!cp_configs[@]}"; do
        local config="${cp_configs[$key]}"
        IFS=: read count cpu memory disk <<< "$config"
        echo "$count:$cpu:$memory:$disk:controlplane"
        total_nodes=$((total_nodes + count))
    done
    
    for key in "${!worker_configs[@]}"; do
        local config="${worker_configs[$key]}"
        IFS=: read count cpu memory disk <<< "$config"
        echo "$count:$cpu:$memory:$disk:worker"
        total_nodes=$((total_nodes + count))
    done
    
    # Return total as last line
    echo "TOTAL:$total_nodes"
}

# Update terraform.tfvars file
update_tfvars() {
    local site_code=$1
    local platform=$2
    local configs=$3
    
    local terraform_dir="${PROJECT_ROOT}/terraform/${platform}"
    local tfvars_file="${terraform_dir}/terraform.tfvars.${site_code}"
    
    if [[ ! -f "$tfvars_file" ]]; then
        error "Terraform tfvars file not found: $tfvars_file"
        return 1
    fi
    
    log "Updating Terraform configuration: $tfvars_file"
    
    # Create backup
    local backup_file="${tfvars_file}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$tfvars_file" "$backup_file"
    log "✓ Created backup: $backup_file"
    
    # Parse configs and build vm_configs
    local vm_configs_json="["
    local first=true
    local total_vms=0
    
    info "VM Configurations:"
    while IFS= read -r line; do
        if [[ "$line" == TOTAL:* ]]; then
            total_vms=$(echo "$line" | cut -d: -f2)
            continue
        fi
        
        [[ -z "$line" ]] && continue
        
        IFS=: read count cpu memory disk role <<< "$line"
        [[ -z "$count" ]] && continue
        
        local mem_gb=$((memory / 1024))
        info "  - ${count}x ${role}: ${cpu} CPU, ${mem_gb}GB RAM, ${disk}GB disk"
        
        # Build JSON object for this config
        if [[ "$first" != true ]]; then
            vm_configs_json+=","
        fi
        first=false
        
        vm_configs_json+="
  {
    count  = ${count}
    cpu    = ${cpu}
    memory = ${memory}
    disk   = ${disk}
    role   = \"${role}\"
  }"
    done <<< "$configs"
    
    vm_configs_json+="
]"
    
    echo ""
    
    # Remove old single-config variables if they exist
    sed -i '/^node_count[[:space:]]*=/d' "$tfvars_file"
    sed -i '/^node_cpu[[:space:]]*=/d' "$tfvars_file"
    sed -i '/^node_memory[[:space:]]*=/d' "$tfvars_file"
    sed -i '/^node_disk_size[[:space:]]*=/d' "$tfvars_file"
    
    # Remove existing vm_configs if present
    # This is tricky - need to handle multi-line removal
    sed -i '/^vm_configs[[:space:]]*=/,/^\]/d' "$tfvars_file"
    
    # Append new vm_configs
    echo "" >> "$tfvars_file"
    echo "# VM Configurations - Multi-size support" >> "$tfvars_file"
    echo "# Generated by update-tfvars.sh on $(date)" >> "$tfvars_file"
    echo "vm_configs = ${vm_configs_json}" >> "$tfvars_file"
    
    log "✓ Updated vm_configs with ${total_vms} total VMs"
    
    return 0
}

# Main function
main() {
    if [[ $# -lt 1 ]]; then
        error "Missing required argument: site-code"
        echo ""
        usage
    fi
    
    local site_code=$1
    local platform="${2:-}"
    
    # Convert to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Update Terraform tfvars from Cluster Configs       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Site: $site_code"
    echo ""
    
    # Load site metadata if platform not provided
    if [[ -z "$platform" ]]; then
        load_site_metadata "$site_code" || exit 1
        platform="$PLATFORM"
    fi
    
    log "Platform: $platform"
    echo ""
    
    # Calculate VM configurations
    log "Analyzing cluster configurations..."
    local configs
    configs=$(calculate_vm_configs "$site_code")
    
    if [[ -z "$configs" ]] || [[ "$configs" == "TOTAL:0" ]]; then
        error "No valid cluster configurations found for site $site_code"
        exit 1
    fi
    
    echo ""
    
    # Update tfvars
    update_tfvars "$site_code" "$platform" "$configs" || exit 1
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Terraform Configuration Updated Successfully       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Next steps:"
    echo ""
    log "  1. Review the updated tfvars:"
    log "     ${GREEN}cat terraform/${platform}/terraform.tfvars.${site_code}${NC}"
    echo ""
    log "  2. Apply Terraform changes:"
    log "     ${GREEN}cd terraform/${platform}${NC}"
    log "     ${GREEN}terraform plan -var-file=terraform.tfvars.${site_code}${NC}"
    log "     ${GREEN}terraform apply -var-file=terraform.tfvars.${site_code}${NC}"
    echo ""
}

main "$@"
