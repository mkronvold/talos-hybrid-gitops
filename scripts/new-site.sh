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

# Usage information
usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <site-code> <platform> [options]

${YELLOW}Create a new site with scaffolded configuration files.${NC}

${GREEN}Arguments:${NC}
  site-code  Site identifier (e.g., ny1d, sf2p, la1s)
  platform   Infrastructure platform: vsphere or proxmox

${GREEN}Options:${NC}
  --location <name>      Full location name (e.g., "New York Zone 1")
  --datacenter <name>    vSphere datacenter name
  --cluster <name>       vSphere cluster name
  --datastore <name>     vSphere datastore name
  --network <name>       vSphere network name
  --vcenter <host>       vCenter server address
  --folder <path>        VM folder path (default: Talos/<site-code>)
  --help                 Show this help message

${GREEN}Site Code Format:${NC}
  <city><zone><env>
  
  Examples:
    ny1d - New York, Zone 1, Dev
    sf2p - San Francisco, Zone 2, Prod
    la1s - Los Angeles, Zone 1, Staging

${GREEN}Examples:${NC}
  # Create NY Zone 1 Dev site with minimal options
  $0 ny1d vsphere --location "New York Zone 1"
  
  # Create SF Zone 2 Prod site with full vSphere config
  $0 sf2p vsphere \\
    --location "San Francisco Zone 2" \\
    --datacenter "SF-DC" \\
    --cluster "SF-Cluster-2" \\
    --datastore "SF-Storage" \\
    --network "VM Network" \\
    --vcenter "vcenter-sf.example.com"

${GREEN}What gets created:${NC}
  • clusters/omni/<site-code>/.site-metadata (platform tracking)
  • terraform/<platform>/terraform.tfvars.<site-code>
  • terraform/jumphost/terraform.tfvars.<site-code> (vSphere only)
  • clusters/omni/<site-code>/README.md
  • Site documentation and examples

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

# Create directory structure
create_directories() {
    local site_code=$1
    
    log "Creating directory structure for $site_code..."
    
    mkdir -p "${PROJECT_ROOT}/clusters/omni/${site_code}"
    
    log "✓ Directories created"
}

# Create Terraform config for vSphere
create_vsphere_tfvars() {
    local site_code=$1
    local location=$2
    local datacenter=$3
    local cluster=$4
    local datastore=$5
    local network=$6
    local vcenter=$7
    local folder=$8
    
    local tfvars_file="${PROJECT_ROOT}/terraform/vsphere/terraform.tfvars.${site_code}"
    
    log "Creating vSphere Terraform configuration..."
    
    cat > "$tfvars_file" <<EOF
# Site: ${site_code} - ${location}
# Created: $(date)

# vSphere credentials
vsphere_user       = "administrator@vsphere.local"
vsphere_password   = "CHANGEME"
vsphere_server     = "${vcenter}"
vsphere_insecure   = true  # Set to false with valid SSL cert

# vSphere resources
vsphere_datacenter    = "${datacenter}"
vsphere_datastore     = "${datastore}"
vsphere_cluster       = "${cluster}"
vsphere_network       = "${network}"
vsphere_resource_pool = "${cluster}/Resources"
vsphere_folder        = "${folder}"

# Talos configuration
talos_template_name = "talos-v1.9.5"
cluster_name        = "${site_code}"

# Node configuration - Default for initial deployment
# Adjust based on cluster requirements (see new-cluster.sh)
node_count     = 6   # 3 control planes + 3 workers
node_cpu       = 4
node_memory    = 8192
node_disk_size = 100

# Site metadata
# site_code = "${site_code}"
# location  = "${location}"
EOF
    
    log "✓ Created: $tfvars_file"
}

# Create Terraform config for Proxmox
create_proxmox_tfvars() {
    local site_code=$1
    local location=$2
    
    local tfvars_file="${PROJECT_ROOT}/terraform/proxmox/terraform.tfvars.${site_code}"
    
    log "Creating Proxmox Terraform configuration..."
    
    cat > "$tfvars_file" <<EOF
# Site: ${site_code} - ${location}
# Created: $(date)

# Proxmox credentials
proxmox_api_url      = "https://proxmox.example.com:8006/api2/json"
proxmox_api_user     = "root@pam"
proxmox_api_password = "CHANGEME"
proxmox_tls_insecure = true

# Proxmox resources
proxmox_node     = "pve"
proxmox_storage  = "local-lvm"
proxmox_bridge   = "vmbr0"

# Talos configuration
talos_iso_url   = "https://github.com/siderolabs/talos/releases/download/v1.9.5/talos-amd64.iso"
cluster_name    = "${site_code}"

# Node configuration - Default for initial deployment
node_count     = 6   # 3 control planes + 3 workers
node_cpu       = 4
node_memory    = 8192
node_disk_size = 100

# Site metadata
# site_code = "${site_code}"
# location  = "${location}"
EOF
    
    log "✓ Created: $tfvars_file"
}

# Create jumphost Terraform config
create_jumphost_tfvars() {
    local site_code=$1
    local location=$2
    local datacenter=$3
    local cluster=$4
    local datastore=$5
    local network=$6
    local vcenter=$7
    local folder=$8
    
    local tfvars_file="${PROJECT_ROOT}/terraform/jumphost/terraform.tfvars.${site_code}"
    
    log "Creating jumphost Terraform configuration..."
    
    cat > "$tfvars_file" <<EOF
# Jumphost for Site: ${site_code} - ${location}
# Created: $(date)

# vSphere Connection
vsphere_server     = "${vcenter}"
vsphere_user       = "administrator@vsphere.local"
vsphere_password   = "CHANGEME"
vsphere_insecure   = true

# vSphere Resources
vsphere_datacenter    = "${datacenter}"
vsphere_cluster       = "${cluster}"
vsphere_datastore     = "${datastore}"
vsphere_network       = "${network}"
vsphere_resource_pool = "${cluster}/Resources"
vsphere_folder        = "${folder}"

# Ubuntu Template
ubuntu_template = "ubuntu-22.04-cloud"

# Jumphost Configuration
jumphost_hostname = "jumphost-${site_code}"
jumphost_cpu      = 2
jumphost_memory   = 4096
jumphost_disk_size = 50

# User Configuration
jumphost_username = "ubuntu"
jumphost_ssh_keys = [
  # Add your SSH public keys here
  # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... user@host",
]

# Timezone
jumphost_timezone = "UTC"
EOF
    
    log "✓ Created: $tfvars_file"
}

# Create site metadata file
create_site_metadata() {
    local site_code=$1
    local location=$2
    local platform=$3
    local environment=$(get_environment "$site_code")
    
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/.site-metadata"
    
    log "Creating site metadata..."
    
    cat > "$metadata_file" <<EOF
# Site Metadata - DO NOT EDIT MANUALLY
SITE_CODE="${site_code}"
LOCATION="${location}"
PLATFORM="${platform}"
ENVIRONMENT="${environment}"
CREATED="$(date -Iseconds)"
EOF
    
    log "✓ Created: $metadata_file"
}

# Create site README
create_site_readme() {
    local site_code=$1
    local location=$2
    local platform=$3
    local environment=$(get_environment "$site_code")
    
    local readme_file="${PROJECT_ROOT}/clusters/omni/${site_code}/README.md"
    
    log "Creating site README..."
    
    cat > "$readme_file" <<EOF
# Site: ${site_code}

**Location:** ${location}  
**Environment:** ${environment}  
**Platform:** ${platform}  
**Created:** $(date)

## Overview

This directory contains cluster configurations for the **${site_code}** site.

## Site Information

- **Site Code:** ${site_code}
- **Location:** ${location}
- **Environment:** ${environment}
- **Platform:** ${platform}

## Configuration Files

### Terraform
- vSphere: \`terraform/vsphere/terraform.tfvars.${site_code}\`
- Proxmox: \`terraform/proxmox/terraform.tfvars.${site_code}\`
- Jumphost: \`terraform/jumphost/terraform.tfvars.${site_code}\`

### Clusters
Cluster configurations are stored in this directory:
- \`<cluster-name>.yaml\` - Omni cluster definitions

## Quick Start

### 1. Deploy Jumphost

\`\`\`bash
# Review and edit jumphost configuration
vim terraform/jumphost/terraform.tfvars.${site_code}

# Deploy jumphost
./scripts/deploy-jumphost.sh ${site_code}
\`\`\`

### 2. Create a Cluster

\`\`\`bash
# Create cluster configuration
./scripts/new-cluster.sh ${site_code} <cluster-name> \\
  --control-planes 3 \\
  --workers 3 \\
  --cpu 4 \\
  --memory 8192

# Review cluster configuration
cat clusters/omni/${site_code}/<cluster-name>.yaml
\`\`\`

### 3. Deploy Infrastructure and Cluster

\`\`\`bash
# Set Omni credentials
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-key>

# Deploy
./scripts/deploy-infrastructure.sh ${site_code} ${platform} \\
  clusters/omni/${site_code}/<cluster-name>.yaml
\`\`\`

## Clusters

| Cluster Name | Control Planes | Workers | Status | Created |
|--------------|----------------|---------|--------|---------|
| (none yet)   | -              | -       | -      | -       |

## Notes

<!-- Add site-specific notes here -->

## Maintenance Log

| Date | Action | Details |
|------|--------|---------|
| $(date +%Y-%m-%d) | Site created | Initial setup for ${site_code} |

EOF
    
    log "✓ Created: $readme_file"
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
    local platform=$2
    shift 2
    
    # Convert site code to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    # Validate platform
    if [[ "$platform" != "vsphere" && "$platform" != "proxmox" ]]; then
        error "Invalid platform: $platform"
        error "Must be: vsphere or proxmox"
        usage
    fi
    
    # Default values
    local location="${site_code}"
    local datacenter="Datacenter"
    local cluster="Cluster"
    local datastore="datastore1"
    local network="VM Network"
    local vcenter="vcenter.example.com"
    local folder="Talos/${site_code}"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --location)
                location="$2"
                shift 2
                ;;
            --datacenter)
                datacenter="$2"
                shift 2
                ;;
            --cluster)
                cluster="$2"
                shift 2
                ;;
            --datastore)
                datastore="$2"
                shift 2
                ;;
            --network)
                network="$2"
                shift 2
                ;;
            --vcenter)
                vcenter="$2"
                shift 2
                ;;
            --folder)
                folder="$2"
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
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Talos Hybrid GitOps - New Site Setup            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site Code:${NC}    $site_code"
    echo -e "${BLUE}Location:${NC}     $location"
    echo -e "${BLUE}Environment:${NC}  $(get_environment "$site_code")"
    echo -e "${BLUE}Platform:${NC}     $platform"
    echo ""
    
    validate_site_code "$site_code"
    
    # Check if site already exists
    if [[ -d "${PROJECT_ROOT}/clusters/omni/${site_code}" ]]; then
        error "Site already exists: $site_code"
        error "Directory: ${PROJECT_ROOT}/clusters/omni/${site_code}"
        exit 1
    fi
    
    # Create site structure
    create_directories "$site_code"
    create_site_metadata "$site_code" "$location" "$platform"
    
    # Create platform-specific Terraform configs
    if [[ "$platform" == "vsphere" ]]; then
        create_vsphere_tfvars "$site_code" "$location" "$datacenter" "$cluster" "$datastore" "$network" "$vcenter" "$folder"
        create_jumphost_tfvars "$site_code" "$location" "$datacenter" "$cluster" "$datastore" "$network" "$vcenter" "$folder"
    else
        create_proxmox_tfvars "$site_code" "$location"
    fi
    
    create_site_readme "$site_code" "$location" "$platform"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Site Created Successfully!                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Site: $site_code ($location)"
    echo ""
    log "Next steps:"
    echo ""
    log "  1. Review and edit Terraform configurations:"
    log "     ${GREEN}vim terraform/vsphere/terraform.tfvars.${site_code}${NC}"
    log "     ${GREEN}vim terraform/jumphost/terraform.tfvars.${site_code}${NC}"
    echo ""
    log "  2. Deploy jumphost:"
    log "     ${GREEN}./scripts/deploy-jumphost.sh ${site_code}${NC}"
    echo ""
    log "  3. Create clusters:"
    log "     ${GREEN}./scripts/new-cluster.sh ${site_code} <cluster-name>${NC}"
    echo ""
    log "  4. Deploy infrastructure (platform auto-detected from site):"
    log "     ${GREEN}./scripts/deploy-infrastructure.sh ${site_code} clusters/omni/${site_code}/<cluster>.yaml${NC}"
    echo ""
    log "Documentation: ${GREEN}clusters/omni/${site_code}/README.md${NC}"
    echo ""
}

main "$@"
