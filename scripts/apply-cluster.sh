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

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <cluster-template-file> [options]

${YELLOW}Apply Omni cluster template configuration.${NC}

This script uses 'omnictl cluster template sync' to apply cluster configurations.

${GREEN}Arguments:${NC}
  cluster-template-file   Path to cluster template YAML file
                         (e.g., clusters/omni/dk1d/cluster-baseline.yaml)

${GREEN}Options:${NC}
  --dry-run              Show what would be applied without making changes
  --verbose, -v          Show detailed diff output
  --help, -h             Show this help message

${GREEN}Example:${NC}
  # Apply cluster template
  $0 clusters/omni/dk1d/cluster-baseline.yaml
  
  # Dry run to see changes
  $0 clusters/omni/dk1d/cluster-baseline.yaml --dry-run
  
  # Verbose output with diffs
  $0 clusters/omni/dk1d/cluster-baseline.yaml --verbose

${GREEN}Cluster Template Format:${NC}
  The cluster template should contain:
  - Cluster definition (kind: Cluster)
  - ControlPlane definition (kind: ControlPlane)
  - Workers definition (kind: Workers)

EOF
    exit 1
}

# Check if omnictl is installed
check_omnictl() {
    if ! command -v omnictl &> /dev/null; then
        error "omnictl not found. Please install it first:"
        error "  brew install siderolabs/tap/sidero-tools"
        error "  OR: ./scripts/install-dependencies.sh"
        exit 1
    fi
}

# Check if Omni credentials are configured
check_omni_credentials() {
    if [[ -z "${OMNI_ENDPOINT:-}" ]]; then
        error "OMNI_ENDPOINT not set. Please configure Omni credentials:"
        error "  source ~/omni.sh"
        error "  OR: export OMNI_ENDPOINT=your-endpoint"
        exit 1
    fi
}

# Main function
main() {
    local cluster_file=""
    local dry_run=""
    local verbose=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --dry-run)
                dry_run="--dry-run"
                shift
                ;;
            -v|--verbose)
                verbose="--verbose"
                shift
                ;;
            -*)
                error "Unknown option: $1"
                usage
                ;;
            *)
                if [[ -z "$cluster_file" ]]; then
                    cluster_file="$1"
                else
                    error "Multiple cluster files specified"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -z "$cluster_file" ]]; then
        error "Cluster template file not specified"
        usage
    fi
    
    if [[ ! -f "$cluster_file" ]]; then
        error "Cluster template file not found: $cluster_file"
        exit 1
    fi
    
    # Check prerequisites
    check_omnictl
    check_omni_credentials
    
    log "Applying cluster template: $cluster_file"
    
    # Validate the template first
    info "Validating cluster template..."
    if ! omnictl cluster template validate -f "$cluster_file"; then
        error "Cluster template validation failed"
        exit 1
    fi
    log "✓ Template validation passed"
    
    # Apply the template
    if [[ -n "$dry_run" ]]; then
        warn "Running in dry-run mode - no changes will be made"
    fi
    
    info "Syncing cluster template to Omni..."
    if omnictl cluster template sync -f "$cluster_file" $dry_run $verbose; then
        log "✓ Cluster template applied successfully"
        
        if [[ -z "$dry_run" ]]; then
            # Extract cluster name from the template
            local cluster_name=$(grep "^name:" "$cluster_file" | head -1 | awk '{print $2}')
            
            if [[ -n "$cluster_name" ]]; then
                info ""
                info "Cluster: $cluster_name"
                info ""
                info "Check cluster status:"
                info "  omnictl cluster template status -f $cluster_file"
                info ""
                info "Get kubeconfig:"
                info "  omnictl kubeconfig $cluster_name > kubeconfig"
                info "  export KUBECONFIG=\$PWD/kubeconfig"
                info "  kubectl get nodes"
            fi
        fi
    else
        error "Failed to apply cluster template"
        exit 1
    fi
}

main "$@"
