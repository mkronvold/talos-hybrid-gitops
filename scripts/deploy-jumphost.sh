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
${GREEN}Usage:${NC} $0 <site-code>

${YELLOW}Deploy a jumphost VM for a specific site.${NC}

${GREEN}Supported Platforms:${NC}
  • vSphere - Deploys Ubuntu VM with cloud-init
  • Proxmox - Deploys Ubuntu VM with cloud-init

${GREEN}Platform Detection:${NC}
  Platform is automatically detected from site metadata (.site-metadata).

${GREEN}Site Code Format:${NC}
  <city><zone><env>
  
  Examples:
    ny1d  - New York, Zone 1, Dev
    sf2p  - San Francisco, Zone 2, Prod
    la1s  - Los Angeles, Zone 1, Staging
    ch3p  - Chicago, Zone 3, Prod

${GREEN}Components:${NC}
  <city>  - 2-letter city/location code (e.g., ny, sf, la, ch)
  <zone>  - Single digit zone number (1-9)
  <env>   - Environment: d (dev), s (staging), p (prod)

${GREEN}Examples:${NC}
  $0 ny1d    # Deploy dev jumphost in NY zone 1
  $0 sf2p    # Deploy prod jumphost in SF zone 2

${GREEN}Configuration:${NC}
  Config file: terraform/jumphost/terraform.tfvars.<site-code>
  
  Create from template:
    cd terraform/jumphost
    cp terraform.tfvars.example terraform.tfvars.ny1d
    # Edit with site-specific settings

${GREEN}What gets deployed:${NC}
  VM name: jumphost-<site-code> (e.g., jumphost-ny1d)
  Workspace: <site-code> (Terraform workspace isolation)
  Tools: Terraform, kubectl, Flux, omnictl, talosctl, Node.js, Copilot CLI

EOF
    exit 1
}

# Validate site code format
validate_site_code() {
    local site_code=$1
    
    # Check length (should be 4 characters: 2 letters + 1 digit + 1 letter)
    if [ ${#site_code} -ne 4 ]; then
        error "Invalid site code format: $site_code"
        error "Expected format: <city><zone><env> (e.g., ny1d, sf2p)"
        usage
    fi
    
    # Check format: 2 letters + 1 digit + 1 letter (d/s/p)
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
    
    local missing=()
    
    if ! command -v terraform &> /dev/null; then
        missing+=("terraform")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
        info "Run: ./scripts/install-dependencies.sh"
        exit 1
    fi
    
    log "✓ All prerequisites met"
}

# Check if site-specific terraform.tfvars exists
check_config() {
    local site_code=$1
    local platform=$2
    local config_file="$TERRAFORM_DIR/terraform.tfvars.$site_code"
    
    log "Checking configuration for site: $site_code (platform: $platform)"
    
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        info "Create it from the example:"
        info "  cd $TERRAFORM_DIR"
        info "  cp terraform.tfvars.example terraform.tfvars.$site_code"
        info "  # Edit with site-specific settings"
        info ""
        info "Make sure to set:"
        info "  - jumphost_hostname = \"jumphost-$site_code\""
        if [[ "$platform" == "vsphere" ]]; then
            info "  - Site-specific vSphere/network settings"
        else
            info "  - Site-specific Proxmox settings"
        fi
        exit 1
    fi
    
    log "✓ Configuration file found: terraform.tfvars.$site_code"
}

# Initialize Terraform with workspace
init_terraform() {
    local site_code=$1
    
    log "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR"
    terraform init -upgrade
    
    # Create or select workspace for site isolation
    log "Setting up Terraform workspace: $site_code"
    terraform workspace select "$site_code" 2>/dev/null || terraform workspace new "$site_code"
    
    log "✓ Terraform initialized (workspace: $site_code)"
}

# Plan Terraform changes
plan_terraform() {
    local site_code=$1
    local var_file="terraform.tfvars.$site_code"
    
    log "Planning Terraform changes for $site_code..."
    
    cd "$TERRAFORM_DIR"
    terraform plan -var-file="$var_file" -out="tfplan-$site_code"
    
    log "✓ Terraform plan complete"
}

# Apply Terraform changes
apply_terraform() {
    local site_code=$1
    
    log "Deploying jumphost VM for $site_code..."
    
    cd "$TERRAFORM_DIR"
    terraform apply "tfplan-$site_code"
    rm -f "tfplan-$site_code"
    
    log "✓ Jumphost VM deployed"
}

# Get jumphost information
get_jumphost_info() {
    local site_code=$1
    
    log "Retrieving jumphost information for $site_code..."
    
    cd "$TERRAFORM_DIR"
    
    local jumphost_ip=$(terraform output -raw jumphost_ip 2>/dev/null || echo "N/A")
    local jumphost_name=$(terraform output -raw jumphost_name 2>/dev/null || echo "N/A")
    local ssh_command=$(terraform output -raw ssh_command 2>/dev/null || echo "N/A")
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Jumphost Deployment Complete!                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Site Code:${NC}     $site_code"
    echo -e "${BLUE}Jumphost Name:${NC} $jumphost_name"
    echo -e "${BLUE}Jumphost IP:${NC}   $jumphost_ip"
    echo ""
    echo -e "${YELLOW}SSH Connection:${NC}"
    echo -e "  $ssh_command"
    echo ""
    echo -e "${YELLOW}Wait a few minutes for cloud-init to complete...${NC}"
    echo ""
    echo -e "${BLUE}What's being installed automatically:${NC}"
    echo -e "  • Talos Hybrid GitOps repository (~/talos-hybrid-gitops)"
    echo -e "  • Terraform, kubectl, Flux, omnictl, talosctl"
    echo -e "  • Node.js, npm, GitHub Copilot CLI"
    echo -e "  • Essential development tools"
    echo ""
    echo -e "${BLUE}Check cloud-init progress:${NC}"
    echo -e "  $ssh_command"
    echo -e "  tail -f /var/log/cloud-init-output.log"
    echo ""
    echo -e "${BLUE}Once complete, you can:${NC}"
    echo -e "  1. SSH to the jumphost"
    echo -e "  2. Configure Terraform: cd ~/talos-hybrid-gitops/terraform/vsphere"
    echo -e "  3. Set Omni credentials"
    echo -e "  4. Deploy clusters: ./scripts/deploy-infrastructure.sh"
    echo ""
}

# Save connection info to file
save_connection_info() {
    local site_code=$1
    local info_file="$PROJECT_ROOT/jumphost-$site_code.txt"
    
    cd "$TERRAFORM_DIR"
    
    cat > "$info_file" <<EOF
Talos Hybrid GitOps - Jumphost Information
==========================================

Site Code:     $site_code
Deployed:      $(date)
Workspace:     $site_code

Jumphost Name: $(terraform output -raw jumphost_name 2>/dev/null || echo "N/A")
Jumphost IP:   $(terraform output -raw jumphost_ip 2>/dev/null || echo "N/A")

SSH Connection:
  $(terraform output -raw ssh_command 2>/dev/null || echo "N/A")

Location:
  Repository: ~/talos-hybrid-gitops
  Scripts:    ~/talos-hybrid-gitops/scripts

Next Steps:
  1. Wait for cloud-init to complete (5-10 minutes)
     Check with: tail -f /var/log/cloud-init-output.log
  
  2. Configure Terraform variables
     cd ~/talos-hybrid-gitops/terraform/vsphere
     cp terraform.tfvars.example terraform.tfvars
     # Edit with your settings
  
  3. Set Omni credentials
     export OMNI_ENDPOINT=https://omni.siderolabs.com
     export OMNI_API_KEY=<your-api-key>
  
  4. Deploy infrastructure
     cd ~/talos-hybrid-gitops
     ./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml

Documentation:
  Main README:  ~/talos-hybrid-gitops/README.md
  Workflows:    ~/talos-hybrid-gitops/WORKFLOW.md
  Quick Start:  ~/talos-hybrid-gitops/docs/QUICKSTART.md
  Scripts Help: ~/talos-hybrid-gitops/scripts/README.md
EOF
    
    log "✓ Connection info saved to: $info_file"
}

# Main function
main() {
    # Check for site code argument
    if [ $# -eq 0 ]; then
        error "Missing required argument: site-code"
        echo ""
        usage
    fi
    
    local site_code=$1
    
    # Convert to lowercase
    site_code=$(echo "$site_code" | tr '[:upper:]' '[:lower:]')
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Talos Hybrid GitOps - Jumphost Deployment            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Target Site:${NC}   $site_code"
    
    validate_site_code "$site_code"
    
    # Load site metadata to get platform
    load_site_metadata "$site_code" || exit 1
    
    local platform="$PLATFORM"
    
    # Set Terraform directory based on platform
    if [[ "$platform" == "vsphere" ]]; then
        TERRAFORM_DIR="$PROJECT_ROOT/terraform/jumphost-vsphere"
    elif [[ "$platform" == "proxmox" ]]; then
        TERRAFORM_DIR="$PROJECT_ROOT/terraform/jumphost-proxmox"
    else
        error "Unsupported platform: $platform"
        exit 1
    fi
    
    echo -e "${BLUE}Platform:${NC}      $platform"
    echo ""
    
    check_prerequisites
    check_config "$site_code" "$platform"
    init_terraform "$site_code"
    plan_terraform "$site_code"
    
    echo ""
    warn "Review the plan above carefully."
    read -p "Continue with deployment? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
        warn "Deployment cancelled"
        cd "$PROJECT_ROOT/terraform/jumphost"
        rm -f "tfplan-$site_code"
        exit 0
    fi
    
    apply_terraform "$site_code"
    get_jumphost_info "$site_code"
    save_connection_info "$site_code"
    
    echo -e "${GREEN}✓ Deployment complete!${NC}"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 130' INT TERM

# Run main function
main "$@"
