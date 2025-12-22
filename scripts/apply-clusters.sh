#!/usr/bin/env bash
set -euo pipefail

# Apply Clusters - Apply all cluster configurations for a site
# This script applies all cluster YAML files in a site directory

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

Apply all cluster configurations for a site to Omni.

Arguments:
  site-code         Site code (e.g., dk1d, ny1p)

Options:
  -c, --cluster     Apply specific cluster only (default: all)
  -h, --help        Show this help message

Prerequisites:
  1. Site must exist
  2. Clusters defined (cluster-*.yaml files)
  3. VMs provisioned (run provision-nodes.sh)
  4. Machines registered in Omni (wait 2-5 min after provisioning)

Example:
  # Apply all clusters in site
  ./scripts/apply-clusters.sh dk1d

  # Apply specific cluster
  ./scripts/apply-clusters.sh dk1d --cluster baseline

This script:
  1. Finds all cluster-*.yaml files in site directory
  2. Validates YAML format
  3. Splits multi-document YAML into individual resources
  4. Applies each resource in order:
     - MachineClasses (define machine selection criteria)
     - Cluster (define cluster configuration)
     - MachineSets (define node groups)
  5. Verifies resources were created
  6. Shows cluster status

EOF
    exit 0
}

# Apply a single cluster file
apply_cluster_file() {
    local cluster_file=$1
    local cluster_name=$(basename "$cluster_file" .yaml | sed 's/^cluster-//')
    
    log "Applying cluster: $cluster_name"
    log "  File: $cluster_file"
    
    # Validate file exists
    if [[ ! -f "$cluster_file" ]]; then
        error "Cluster file not found: $cluster_file"
        return 1
    fi
    
    # Use apply-cluster.sh for the actual application
    "${SCRIPT_DIR}/apply-cluster.sh" "$cluster_file"
    
    return $?
}

# Main function
apply_clusters() {
    local site_code=$1
    local specific_cluster=${2:-}
    
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    
    # Validate site directory exists
    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
        error "Site may not exist or was not created with new-site.sh"
        return 1
    fi
    
    log "Applying clusters for site: $site_code"
    echo ""
    
    # Find cluster files
    local cluster_files=()
    if [[ -n "$specific_cluster" ]]; then
        local cluster_file="${site_dir}/cluster-${specific_cluster}.yaml"
        if [[ ! -f "$cluster_file" ]]; then
            error "Cluster file not found: $cluster_file"
            return 1
        fi
        cluster_files=("$cluster_file")
    else
        mapfile -t cluster_files < <(find "$site_dir" -maxdepth 1 -name "cluster-*.yaml" -type f | sort)
    fi
    
    if [[ ${#cluster_files[@]} -eq 0 ]]; then
        error "No cluster files found in: $site_dir"
        error "Create clusters with: ./scripts/new-cluster.sh $site_code <cluster-name>"
        return 1
    fi
    
    info "Found ${#cluster_files[@]} cluster(s) to apply"
    for file in "${cluster_files[@]}"; do
        info "  - $(basename "$file" .yaml | sed 's/^cluster-//')"
    done
    echo ""
    
    # Apply each cluster
    local success_count=0
    local failure_count=0
    local failed_clusters=()
    
    for cluster_file in "${cluster_files[@]}"; do
        local cluster_name=$(basename "$cluster_file" .yaml | sed 's/^cluster-//')
        
        if apply_cluster_file "$cluster_file"; then
            ((success_count++))
            echo ""
        else
            ((failure_count++))
            failed_clusters+=("$cluster_name")
            warn "Failed to apply cluster: $cluster_name"
            echo ""
        fi
    done
    
    # Summary
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Cluster Application Summary                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log "Successfully applied: $success_count cluster(s)"
    
    if [[ $failure_count -gt 0 ]]; then
        error "Failed to apply: $failure_count cluster(s)"
        for cluster in "${failed_clusters[@]}"; do
            error "  - $cluster"
        done
        echo ""
        return 1
    fi
    
    echo ""
    info "Next steps:"
    info "  1. Monitor cluster creation: omnictl get clusters"
    info "  2. Wait for clusters to become ready (5-15 minutes)"
    info "  3. Check cluster status: omnictl cluster status <cluster-name>"
    info "  4. Download kubeconfigs: ./scripts/get-kubeconfigs.sh ${site_code}"
    
    return 0
}

# Parse arguments
SITE_CODE=""
SPECIFIC_CLUSTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--cluster)
            SPECIFIC_CLUSTER=$2
            shift 2
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

# Run application
apply_clusters "$SITE_CODE" "$SPECIFIC_CLUSTER"
