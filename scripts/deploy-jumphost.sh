#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/jumphost"

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

# Check if terraform.tfvars exists
check_config() {
    log "Checking configuration..."
    
    if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        error "Configuration file not found: $TERRAFORM_DIR/terraform.tfvars"
        info "Create it from the example:"
        info "  cd $TERRAFORM_DIR"
        info "  cp terraform.tfvars.example terraform.tfvars"
        info "  # Edit with your settings"
        exit 1
    fi
    
    log "✓ Configuration file found"
}

# Initialize Terraform
init_terraform() {
    log "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR"
    terraform init -upgrade
    
    log "✓ Terraform initialized"
}

# Plan Terraform changes
plan_terraform() {
    log "Planning Terraform changes..."
    
    cd "$TERRAFORM_DIR"
    terraform plan -out=tfplan
    
    log "✓ Terraform plan complete"
}

# Apply Terraform changes
apply_terraform() {
    log "Deploying jumphost VM..."
    
    cd "$TERRAFORM_DIR"
    terraform apply tfplan
    rm -f tfplan
    
    log "✓ Jumphost VM deployed"
}

# Get jumphost information
get_jumphost_info() {
    log "Retrieving jumphost information..."
    
    cd "$TERRAFORM_DIR"
    
    local jumphost_ip=$(terraform output -raw jumphost_ip 2>/dev/null || echo "N/A")
    local jumphost_name=$(terraform output -raw jumphost_name 2>/dev/null || echo "N/A")
    local ssh_command=$(terraform output -raw ssh_command 2>/dev/null || echo "N/A")
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Jumphost Deployment Complete!                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
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
    local info_file="$PROJECT_ROOT/jumphost-info.txt"
    
    cd "$TERRAFORM_DIR"
    
    cat > "$info_file" <<EOF
Talos Hybrid GitOps - Jumphost Information
==========================================

Deployed: $(date)

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
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Talos Hybrid GitOps - Jumphost Deployment            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    check_config
    init_terraform
    plan_terraform
    
    echo ""
    warn "Review the plan above carefully."
    read -p "Continue with deployment? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
        warn "Deployment cancelled"
        cd "$TERRAFORM_DIR"
        rm -f tfplan
        exit 0
    fi
    
    apply_terraform
    get_jumphost_info
    save_connection_info
    
    echo -e "${GREEN}✓ Deployment complete!${NC}"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 130' INT TERM

# Run main function
main "$@"
