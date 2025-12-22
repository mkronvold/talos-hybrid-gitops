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

# Load site metadata
load_site_metadata() {
    local site_code=$1
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/.site-metadata"
    
    if [[ ! -f "$metadata_file" ]]; then
        error "Site metadata not found: $metadata_file"
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
${GREEN}Usage:${NC} $0 <site-code> [options]

${YELLOW}Download Omni ISO with pre-baked site labels and upload to Proxmox.${NC}

${GREEN}Arguments:${NC}
  site-code                Site identifier (e.g., ny1d, dk1d)

${GREEN}Options:${NC}
  --talos-version <ver>    Talos version (default: 1.11.5)
  --extensions <ext>       Add extension (can be repeated)
  --secureboot             Enable SecureBoot
  --output-dir <dir>       Local output directory (default: /tmp/omni-isos)
  --no-upload              Download only, don't upload to Proxmox
  --help                   Show this help message

${GREEN}Examples:${NC}
  # Download and upload ISO for dk1d site
  $0 dk1d
  
  # Download with QEMU guest agent extension
  $0 dk1d --extensions qemu-guest-agent
  
  # Download with multiple extensions
  $0 dk1d --extensions qemu-guest-agent --extensions intel-ucode
  
  # Just download, don't upload
  $0 dk1d --no-upload

${GREEN}Note:${NC}
  - Requires omnictl configured with valid credentials
  - For Proxmox: requires SSH access configured in terraform.tfvars
  - ISO will be uploaded to proxmox_iso_storage (typically 'local')

EOF
    exit 1
}

# Main function
main() {
    if [[ $# -lt 1 ]]; then
        error "Missing required site-code argument"
        usage
    fi
    
    local site_code=$1
    shift
    
    # Convert to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    # Default values
    local talos_version="1.11.5"
    local extensions=()
    local secureboot=false
    local output_dir="/tmp/omni-isos"
    local no_upload=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --talos-version)
                talos_version="$2"
                shift 2
                ;;
            --extensions)
                extensions+=("$2")
                shift 2
                ;;
            --secureboot)
                secureboot=true
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --no-upload)
                no_upload=true
                shift
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
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Omni ISO Preparation for Site: ${site_code}             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Site:           $site_code"
    log "Platform:       $platform"
    log "Talos Version:  $talos_version"
    if [[ ${#extensions[@]} -gt 0 ]]; then
        log "Extensions:     ${extensions[*]}"
    fi
    if [[ "$secureboot" == true ]]; then
        log "SecureBoot:     enabled"
    fi
    echo ""
    
    # Check prerequisites
    if ! command -v omnictl &> /dev/null; then
        error "omnictl not found. Please install omnictl first."
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Build ISO filename
    local iso_name="talos-omni-${site_code}-v${talos_version}.iso"
    local iso_path="${output_dir}/${iso_name}"
    
    # Build omnictl command
    local omnictl_cmd="omnictl download iso"
    omnictl_cmd+=" --arch amd64"
    omnictl_cmd+=" --talos-version ${talos_version}"
    omnictl_cmd+=" --initial-labels site=${site_code}"
    omnictl_cmd+=" --initial-labels platform=${platform}"
    omnictl_cmd+=" --output ${iso_path}"
    
    # Add extensions
    for ext in "${extensions[@]}"; do
        omnictl_cmd+=" --extensions ${ext}"
    done
    
    # Add secureboot flag
    if [[ "$secureboot" == true ]]; then
        omnictl_cmd+=" --secureboot"
    fi
    
    # Download ISO
    log "Downloading Omni ISO with pre-baked labels..."
    info "Command: $omnictl_cmd"
    echo ""
    
    if eval "$omnictl_cmd"; then
        log "✓ ISO downloaded successfully: $iso_path"
        
        # Show ISO details
        local iso_size=$(du -h "$iso_path" | cut -f1)
        log "  Size: $iso_size"
        log "  Labels: site=${site_code}, platform=${platform}"
    else
        error "Failed to download ISO"
        exit 1
    fi
    
    # Upload to Proxmox if not disabled
    if [[ "$no_upload" == false && "$platform" == "proxmox" ]]; then
        echo ""
        log "Uploading ISO to Proxmox..."
        
        # Load Proxmox configuration from terraform.tfvars
        local tfvars_file="${PROJECT_ROOT}/terraform/proxmox/terraform.tfvars.${site_code}"
        if [[ ! -f "$tfvars_file" ]]; then
            error "Terraform tfvars not found: $tfvars_file"
            error "Cannot determine Proxmox connection details"
            exit 1
        fi
        
        # Parse Proxmox details from tfvars
        local proxmox_endpoint=$(grep "^proxmox_endpoint" "$tfvars_file" | cut -d'"' -f2)
        local proxmox_node=$(grep "^proxmox_node" "$tfvars_file" | cut -d'"' -f2)
        local proxmox_ssh_user=$(grep "^proxmox_ssh_username" "$tfvars_file" | cut -d'"' -f2 || echo "root")
        
        if [[ -z "$proxmox_endpoint" || -z "$proxmox_node" ]]; then
            error "Could not parse Proxmox endpoint or node from tfvars"
            exit 1
        fi
        
        # Extract hostname from endpoint
        local proxmox_host=$(echo "$proxmox_endpoint" | sed -E 's|https?://([^:/]+).*|\1|')
        
        log "Proxmox host: $proxmox_host"
        log "Proxmox node: $proxmox_node"
        log "SSH user: $proxmox_ssh_user"
        
        # ISO storage path on Proxmox
        local proxmox_iso_path="/var/lib/vz/template/iso/${iso_name}"
        
        # Upload via SCP
        info "Uploading to ${proxmox_ssh_user}@${proxmox_host}:${proxmox_iso_path}"
        if scp "$iso_path" "${proxmox_ssh_user}@${proxmox_host}:${proxmox_iso_path}"; then
            log "✓ ISO uploaded successfully to Proxmox"
            
            # Store ISO name for terraform reference
            local iso_ref_file="${PROJECT_ROOT}/terraform/proxmox/.omni-iso-${site_code}"
            echo "$iso_name" > "$iso_ref_file"
            log "✓ Saved ISO reference: $iso_ref_file"
        else
            error "Failed to upload ISO to Proxmox"
            warn "You may need to configure SSH key authentication"
            exit 1
        fi
    elif [[ "$platform" != "proxmox" ]]; then
        warn "Platform is not Proxmox. ISO upload skipped."
        info "Manual upload required for platform: $platform"
    fi
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                ISO Preparation Complete!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "ISO Location: $iso_path"
    if [[ "$no_upload" == false && "$platform" == "proxmox" ]]; then
        log "Proxmox Path: $proxmox_iso_path"
        log "ISO Name: $iso_name"
        echo ""
        log "Next steps:"
        log "  1. Update terraform to use this ISO"
        log "  2. Run: ./scripts/deploy-infrastructure.sh $site_code --use-omni-iso"
    else
        log "Upload skipped. To upload manually:"
        log "  scp $iso_path root@<proxmox-host>:/var/lib/vz/template/iso/"
    fi
    echo ""
}

main "$@"
