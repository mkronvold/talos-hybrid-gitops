#!/usr/bin/env bash
set -euo pipefail

# Get Kubeconfigs - Download kubeconfigs for all clusters in a site
# This script downloads kubeconfig files from Omni for all clusters

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

Download kubeconfig files for all clusters in a site.

Arguments:
  site-code         Site code (e.g., dk1d, ny1p)

Options:
  -c, --cluster     Download specific cluster only (default: all)
  -o, --output-dir  Output directory (default: kubeconfigs/)
  -m, --merge       Merge all kubeconfigs into single file
  -h, --help        Show this help message

Prerequisites:
  1. Clusters must be deployed and ready
  2. omnictl must be configured with credentials
  3. Clusters must be in "Ready" state

Example:
  # Download all kubeconfigs for site
  ./scripts/get-kubeconfigs.sh dk1d

  # Download specific cluster
  ./scripts/get-kubeconfigs.sh dk1d --cluster baseline

  # Merge into single file
  ./scripts/get-kubeconfigs.sh dk1d --merge

  # Custom output directory
  ./scripts/get-kubeconfigs.sh dk1d --output-dir ~/.kube/configs/

This script:
  1. Finds all clusters in site directory
  2. Checks if clusters exist in Omni
  3. Downloads kubeconfig for each ready cluster
  4. Saves to kubeconfigs/<site>-<cluster>.yaml
  5. Optionally merges all configs into single file

EOF
    exit 0
}

# Check if cluster is ready
check_cluster_ready() {
    local cluster_name=$1
    
    # Get cluster status from Omni
    if ! omnictl get cluster "$cluster_name" &>/dev/null; then
        return 1
    fi
    
    # Check if cluster is ready (this is a simplified check)
    local status=$(omnictl get cluster "$cluster_name" -o json 2>/dev/null | jq -r '.spec.phase // "Unknown"' || echo "Unknown")
    
    if [[ "$status" == "Running" || "$status" == "Ready" ]]; then
        return 0
    fi
    
    return 1
}

# Download kubeconfig for a cluster
download_kubeconfig() {
    local site_code=$1
    local cluster_name=$2
    local output_dir=$3
    
    local full_cluster_name="${site_code}-${cluster_name}"
    local output_file="${output_dir}/${full_cluster_name}.yaml"
    
    log "Downloading kubeconfig: $full_cluster_name"
    
    # Check if cluster exists and is ready
    if ! check_cluster_ready "$full_cluster_name"; then
        warn "Cluster not ready: $full_cluster_name"
        warn "  Run: omnictl cluster status $full_cluster_name"
        return 1
    fi
    
    # Download kubeconfig
    if omnictl kubeconfig "$full_cluster_name" > "$output_file" 2>/dev/null; then
        log "✓ Downloaded: $output_file"
        return 0
    else
        error "Failed to download kubeconfig for: $full_cluster_name"
        rm -f "$output_file"
        return 1
    fi
}

# Merge kubeconfigs into single file
merge_kubeconfigs() {
    local site_code=$1
    local output_dir=$2
    local merged_file="${output_dir}/kubeconfig-${site_code}.yaml"
    
    log "Merging kubeconfigs into: $merged_file"
    
    # Use kubectl to merge configs
    local kubeconfig_files=$(find "$output_dir" -name "${site_code}-*.yaml" -type f | tr '\n' ':')
    
    if [[ -z "$kubeconfig_files" ]]; then
        error "No kubeconfig files found to merge"
        return 1
    fi
    
    # Export merged config
    KUBECONFIG="$kubeconfig_files" kubectl config view --flatten > "$merged_file"
    
    log "✓ Merged kubeconfig: $merged_file"
    info "  Use with: export KUBECONFIG=$merged_file"
    
    return 0
}

# Main function
get_kubeconfigs() {
    local site_code=$1
    local specific_cluster=${2:-}
    local output_dir=${3:-}
    local merge=${4:-false}
    
    local site_dir="${PROJECT_ROOT}/clusters/omni/${site_code}"
    
    # Default output directory
    if [[ -z "$output_dir" ]]; then
        output_dir="${PROJECT_ROOT}/kubeconfigs"
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Validate site directory exists
    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
        return 1
    fi
    
    log "Downloading kubeconfigs for site: $site_code"
    log "Output directory: $output_dir"
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
        return 1
    fi
    
    info "Found ${#cluster_files[@]} cluster(s)"
    for file in "${cluster_files[@]}"; do
        info "  - $(basename "$file" .yaml | sed 's/^cluster-//')"
    done
    echo ""
    
    # Download kubeconfigs
    local success_count=0
    local failure_count=0
    local failed_clusters=()
    
    for cluster_file in "${cluster_files[@]}"; do
        local cluster_name=$(basename "$cluster_file" .yaml | sed 's/^cluster-//')
        
        if download_kubeconfig "$site_code" "$cluster_name" "$output_dir"; then
            ((success_count++))
        else
            ((failure_count++))
            failed_clusters+=("$cluster_name")
        fi
        echo ""
    done
    
    # Merge if requested and successful downloads
    if [[ "$merge" == "true" ]] && [[ $success_count -gt 0 ]]; then
        merge_kubeconfigs "$site_code" "$output_dir"
        echo ""
    fi
    
    # Summary
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            Kubeconfig Download Summary                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log "Successfully downloaded: $success_count kubeconfig(s)"
    
    if [[ $failure_count -gt 0 ]]; then
        error "Failed to download: $failure_count kubeconfig(s)"
        for cluster in "${failed_clusters[@]}"; do
            error "  - $cluster (may not be ready yet)"
        done
        echo ""
    fi
    
    if [[ $success_count -gt 0 ]]; then
        echo ""
        info "Usage:"
        if [[ "$merge" == "true" ]]; then
            info "  export KUBECONFIG=${output_dir}/kubeconfig-${site_code}.yaml"
            info "  kubectl config get-contexts"
        else
            for cluster_file in "${cluster_files[@]}"; do
                local cluster_name=$(basename "$cluster_file" .yaml | sed 's/^cluster-//')
                local kubeconfig_file="${output_dir}/${site_code}-${cluster_name}.yaml"
                if [[ -f "$kubeconfig_file" ]]; then
                    info "  export KUBECONFIG=${kubeconfig_file}"
                fi
            done
        fi
        info "  kubectl get nodes"
    fi
    
    return $(( failure_count > 0 ? 1 : 0 ))
}

# Parse arguments
SITE_CODE=""
SPECIFIC_CLUSTER=""
OUTPUT_DIR=""
MERGE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--cluster)
            SPECIFIC_CLUSTER=$2
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR=$2
            shift 2
            ;;
        -m|--merge)
            MERGE=true
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

# Run kubeconfig download
get_kubeconfigs "$SITE_CODE" "$SPECIFIC_CLUSTER" "$OUTPUT_DIR" "$MERGE"
