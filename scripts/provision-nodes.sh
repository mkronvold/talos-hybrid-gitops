#!/usr/bin/env bash
set -euo pipefail

# Provision Nodes - Deploy VMs using Terraform
# This script provisions VMs for a site using Terraform

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
Usage: $(basename "$0") <site-code> [options]

Provision VMs for a site using Terraform.

Arguments:
  site-code         Site code (e.g., dk1d, ny1p)

Options:
  -a, --auto-approve    Auto-approve Terraform apply (skip confirmation)
  -h, --help           Show this help message

Prerequisites:
  1. Site must exist (created with new-site.sh)
  2. Clusters defined (created with new-cluster.sh)
  3. Omni ISOs prepared (run prepare-omni-iso.sh for each version)
  4. Terraform variables updated (run update-tfvars.sh)

Example:
  # Standard workflow
  ./scripts/new-site.sh dk1d proxmox
  ./scripts/new-cluster.sh dk1d baseline --size-class 4x8
  ./scripts/prepare-omni-iso.sh dk1d --talos-version 1.9.0
  ./scripts/update-tfvars.sh dk1d
  ./scripts/provision-nodes.sh dk1d

  # With auto-approve
  ./scripts/provision-nodes.sh dk1d --auto-approve

This script:
  1. Validates site exists
  2. Detects platform from site metadata
  3. Changes to terraform/<platform> directory
  4. Runs terraform init (if needed)
  5. Runs terraform plan
  6. Runs terraform apply (with or without confirmation)

EOF
    exit 0
}

# Load site metadata
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
    
    log "Site: $site_code (Platform: $PLATFORM)"
}

# Main provisioning function
provision_nodes() {
    local site_code=$1
    local auto_approve=${2:-false}
    
    log "Provisioning nodes for site: $site_code"
    
    # Load site metadata
    load_site_metadata "$site_code" || return 1
    
    local terraform_dir="${PROJECT_ROOT}/terraform/${PLATFORM}"
    local tfvars_file="terraform.tfvars.${site_code}"
    
    # Validate terraform directory exists
    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    # Validate tfvars file exists
    if [[ ! -f "${terraform_dir}/${tfvars_file}" ]]; then
        error "Terraform variables file not found: ${terraform_dir}/${tfvars_file}"
        error "Please create this file or run: cp ${terraform_dir}/terraform.tfvars.example ${terraform_dir}/${tfvars_file}"
        return 1
    fi
    
    cd "$terraform_dir"
    
    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform.lock.hcl" ]]; then
        log "Initializing Terraform..."
        terraform init
    fi
    
    # Run terraform plan
    log "Planning infrastructure changes..."
    terraform plan -var-file="$tfvars_file"
    
    echo ""
    
    # Run terraform apply
    if [[ "$auto_approve" == "true" ]]; then
        log "Applying infrastructure changes (auto-approved)..."
        terraform apply -var-file="$tfvars_file" -auto-approve
    else
        log "Applying infrastructure changes..."
        terraform apply -var-file="$tfvars_file"
    fi
    
    echo ""
    log "✓ Nodes provisioned successfully"
    
    # Show output
    echo ""
    info "VM Information:"
    terraform output -json | jq -r '
        .vm_names.value as $names |
        .vm_ids.value as $ids |
        ($names | to_entries[] | 
            "  VM " + (.key + 1 | tostring) + ": " + .value + " (ID: " + ($ids[.key] | tostring) + ")"
        )
    ' 2>/dev/null || terraform output vm_names
    
    echo ""
    info "Next steps:"
    info "  1. Wait 2-5 minutes for VMs to boot and register with Omni"
    info "  2. Check machines: omnictl get machines"
    info "  3. Apply cluster configs: ./scripts/apply-clusters.sh ${site_code}"
    info "  4. Monitor clusters: omnictl get clusters"
}

# Parse arguments
SITE_CODE=""
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$SITE_CODE" ]]; then
                SITE_CODE=$1
            else
                error "Unexpected argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SITE_CODE" ]]; then
    error "Site code is required"
    usage
    exit 1
fi

# Run provisioning
provision_nodes "$SITE_CODE" "$AUTO_APPROVE"
