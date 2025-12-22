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
${GREEN}Usage:${NC} $0 <site-code> [options]

${YELLOW}Modify site metadata and configuration.${NC}

${GREEN}Arguments:${NC}
  site-code  Site identifier (e.g., ny1d, sf2p)

${GREEN}Options:${NC}
  --location <name>     Update location name
  --platform <type>     Change platform (vsphere or proxmox)
  --show                Show current site metadata
  --help                Show this help message

${GREEN}Examples:${NC}
  # Show current site metadata
  $0 ny1d --show
  
  # Update location name
  $0 ny1d --location "New York Zone 1 Primary"
  
  # Change platform (WARNING: requires infrastructure rebuild)
  $0 ny1d --platform proxmox

${GREEN}Warning:${NC}
  Changing platform requires:
  1. Destroying existing infrastructure
  2. Recreating Terraform configurations
  3. Redeploying all resources
  
  This is a destructive operation!

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

# Load site metadata
load_site_metadata() {
    local site_code=$1
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/site-${site_code}.yaml"
    
    if [[ ! -f "$metadata_file" ]]; then
        error "Site metadata not found: $metadata_file"
        error "Site does not exist. Create it first with:"
        error "  ./scripts/new-site.sh $site_code <platform>"
        return 1
    fi
    
    source "$metadata_file"
    
    log "✓ Loaded site metadata: $site_code"
}

# Show site metadata
show_site_metadata() {
    local site_code=$1
    
    load_site_metadata "$site_code" || exit 1
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Site Metadata: ${site_code}                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site Code:${NC}    $SITE_CODE"
    echo -e "${BLUE}Location:${NC}     $LOCATION"
    echo -e "${BLUE}Platform:${NC}     $PLATFORM"
    echo -e "${BLUE}Environment:${NC}  $ENVIRONMENT"
    echo -e "${BLUE}Created:${NC}      $CREATED"
    echo ""
    
    # Show related configuration files
    echo -e "${BLUE}Configuration Files:${NC}"
    echo ""
    
    if [[ "$PLATFORM" == "vsphere" ]]; then
        echo -e "  Terraform (infrastructure):"
        echo -e "    ${GREEN}terraform/vsphere/terraform.tfvars.${site_code}${NC}"
        echo -e "  Terraform (jumphost):"
        echo -e "    ${GREEN}terraform/jumphost-vsphere/terraform.tfvars.${site_code}${NC}"
    else
        echo -e "  Terraform (infrastructure):"
        echo -e "    ${GREEN}terraform/proxmox/terraform.tfvars.${site_code}${NC}"
        echo -e "  Terraform (jumphost):"
        echo -e "    ${GREEN}terraform/jumphost-proxmox/terraform.tfvars.${site_code}${NC}"
    fi
    
    echo -e "  Clusters:"
    echo -e "    ${GREEN}clusters/omni/${site_code}/${NC}"
    
    # List cluster files if they exist
    if [[ -d "${PROJECT_ROOT}/clusters/omni/${site_code}" ]]; then
        local cluster_count=$(find "${PROJECT_ROOT}/clusters/omni/${site_code}" -maxdepth 1 -name "*.yaml" -type f 2>/dev/null | wc -l)
        if [[ $cluster_count -gt 0 ]]; then
            echo -e "    ${BLUE}Found $cluster_count cluster(s):${NC}"
            find "${PROJECT_ROOT}/clusters/omni/${site_code}" -maxdepth 1 -name "*.yaml" -type f -exec basename {} \; | sed 's/^/      /'
        fi
    fi
    echo ""
}

# Update location
update_location() {
    local site_code=$1
    local new_location=$2
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/site-${site_code}.yaml"
    
    load_site_metadata "$site_code" || exit 1
    
    log "Updating location..."
    info "Old location: $LOCATION"
    info "New location: $new_location"
    
    # Backup
    cp "$metadata_file" "${metadata_file}.backup"
    
    # Update metadata file
    cat > "$metadata_file" <<EOF
# Site Metadata - DO NOT EDIT MANUALLY
# Use ./scripts/modify-site.sh to make changes
SITE_CODE="${SITE_CODE}"
LOCATION="${new_location}"
PLATFORM="${PLATFORM}"
ENVIRONMENT="${ENVIRONMENT}"
CREATED="${CREATED}"
MODIFIED="$(date -Iseconds)"
EOF
    
    log "✓ Location updated"
    rm -f "${metadata_file}.backup"
}

# Change platform
change_platform() {
    local site_code=$1
    local new_platform=$2
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/site-${site_code}.yaml"
    
    if [[ "$new_platform" != "vsphere" && "$new_platform" != "proxmox" ]]; then
        error "Invalid platform: $new_platform"
        error "Must be: vsphere or proxmox"
        exit 1
    fi
    
    load_site_metadata "$site_code" || exit 1
    
    if [[ "$PLATFORM" == "$new_platform" ]]; then
        warn "Site is already using platform: $new_platform"
        exit 0
    fi
    
    echo ""
    warn "═══════════════════════════════════════════════════════════"
    warn "                    ⚠️  WARNING  ⚠️"
    warn "═══════════════════════════════════════════════════════════"
    echo ""
    warn "You are about to change the platform from '$PLATFORM' to '$new_platform'"
    echo ""
    warn "This is a DESTRUCTIVE operation that requires:"
    echo ""
    echo "  1. Destroying all existing infrastructure"
    echo "  2. Removing old Terraform configurations"
    echo "  3. Creating new platform-specific configurations"
    echo "  4. Redeploying all clusters and resources"
    echo ""
    warn "Data loss is possible if not backed up properly!"
    echo ""
    warn "═══════════════════════════════════════════════════════════"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to proceed: " -r
    echo
    
    if [[ "$REPLY" != "yes" ]]; then
        warn "Platform change cancelled"
        exit 0
    fi
    
    log "Changing platform from $PLATFORM to $new_platform..."
    
    # Backup current metadata
    cp "$metadata_file" "${metadata_file}.backup"
    
    # Update metadata file
    cat > "$metadata_file" <<EOF
# Site Metadata - DO NOT EDIT MANUALLY
# Use ./scripts/modify-site.sh to make changes
SITE_CODE="${SITE_CODE}"
LOCATION="${LOCATION}"
PLATFORM="${new_platform}"
ENVIRONMENT="${ENVIRONMENT}"
CREATED="${CREATED}"
MODIFIED="$(date -Iseconds)"
EOF
    
    log "✓ Platform metadata updated"
    
    # Check for existing Terraform configs to remove
    local old_infra_config=""
    local old_jumphost_config=""
    local new_infra_needed=false
    local new_jumphost_needed=false
    
    if [[ "$PLATFORM" == "vsphere" ]]; then
        old_infra_config="${PROJECT_ROOT}/terraform/vsphere/terraform.tfvars.${site_code}"
        old_jumphost_config="${PROJECT_ROOT}/terraform/jumphost-vsphere/terraform.tfvars.${site_code}"
    else
        old_infra_config="${PROJECT_ROOT}/terraform/proxmox/terraform.tfvars.${site_code}"
        old_jumphost_config="${PROJECT_ROOT}/terraform/jumphost-proxmox/terraform.tfvars.${site_code}"
    fi
    
    # Archive old configs if they exist
    if [[ -f "$old_infra_config" ]] || [[ -f "$old_jumphost_config" ]]; then
        local archive_dir="${PROJECT_ROOT}/clusters/omni/${site_code}/.archive-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$archive_dir"
        
        if [[ -f "$old_infra_config" ]]; then
            cp "$old_infra_config" "$archive_dir/"
            log "Archived: $(basename "$old_infra_config") to $archive_dir/"
        fi
        
        if [[ -f "$old_jumphost_config" ]]; then
            cp "$old_jumphost_config" "$archive_dir/"
            log "Archived: $(basename "$old_jumphost_config") to $archive_dir/"
        fi
        
        info "Old configurations archived to: $archive_dir/"
    fi
    
    echo ""
    log "✓ Platform change complete"
    echo ""
    warn "Next steps:"
    echo ""
    warn "  1. Review and update cluster configurations:"
    warn "     cd clusters/omni/${site_code}/"
    warn "     # Update cluster YAML files with new platform label"
    echo ""
    warn "  2. Create new Terraform configurations:"
    if [[ "$new_platform" == "vsphere" ]]; then
        warn "     cd terraform/vsphere"
        warn "     cp terraform.tfvars.example terraform.tfvars.${site_code}"
        warn "     cd ../jumphost-vsphere"
        warn "     cp terraform.tfvars.example terraform.tfvars.${site_code}"
    else
        warn "     cd terraform/proxmox"
        warn "     cp terraform.tfvars.example terraform.tfvars.${site_code}"
        warn "     cd ../jumphost-proxmox"
        warn "     cp terraform.tfvars.example terraform.tfvars.${site_code}"
    fi
    warn "     # Edit with your $new_platform settings"
    echo ""
    warn "  3. Destroy old infrastructure (if still running):"
    warn "     # Use old platform's Terraform to destroy"
    echo ""
    warn "  4. Deploy new infrastructure:"
    warn "     ./scripts/deploy-jumphost.sh ${site_code}"
    warn "     ./scripts/deploy-infrastructure.sh ${site_code} clusters/omni/${site_code}/<cluster>.yaml"
    echo ""
    
    rm -f "${metadata_file}.backup"
}

# Main function
main() {
    # Check for help first
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        usage
    fi
    
    local site_code=$1
    shift
    
    # Convert to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    validate_site_code "$site_code"
    
    # Parse options
    local show_only=false
    local new_location=""
    local new_platform=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --show)
                show_only=true
                shift
                ;;
            --location)
                new_location="$2"
                shift 2
                ;;
            --platform)
                new_platform="$2"
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
    
    # Show metadata if requested
    if [[ "$show_only" == true ]]; then
        show_site_metadata "$site_code"
        exit 0
    fi
    
    # Check if any modifications requested
    if [[ -z "$new_location" && -z "$new_platform" ]]; then
        error "No modifications specified"
        info "Use --location or --platform to modify site"
        info "Use --show to view current metadata"
        echo ""
        usage
    fi
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Talos Hybrid GitOps - Modify Site               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site Code:${NC} $site_code"
    echo ""
    
    # Apply modifications
    if [[ -n "$new_location" ]]; then
        update_location "$site_code" "$new_location"
    fi
    
    if [[ -n "$new_platform" ]]; then
        change_platform "$site_code" "$new_platform"
    fi
    
    echo ""
    log "Modifications complete"
    echo ""
    info "View updated metadata with:"
    info "  ${GREEN}./scripts/modify-site.sh $site_code --show${NC}"
    echo ""
}

main "$@"
