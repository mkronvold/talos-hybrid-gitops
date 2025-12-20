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

usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 <cluster-yaml-file>

${YELLOW}Apply Omni cluster configuration from a YAML file.${NC}

This script splits the multi-document YAML file and applies each resource
separately to work around omnictl apply limitations with multi-document files.

${GREEN}Arguments:${NC}
  cluster-yaml-file   Path to cluster YAML file (e.g., clusters/omni/dk1d/baseline.yaml)

${GREEN}Example:${NC}
  $0 clusters/omni/dk1d/baseline.yaml

${GREEN}Resources applied in order:${NC}
  1. MachineClasses (for machine selection)
  2. Cluster (main cluster resource)
  3. MachineSets (control plane and workers)

EOF
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Missing required argument: cluster-yaml-file"
    usage
fi

YAML_FILE="$1"

# Validate file exists
if [[ ! -f "$YAML_FILE" ]]; then
    error "File not found: $YAML_FILE"
    exit 1
fi

log "Applying cluster configuration from: $YAML_FILE"

# Create temp directory for split files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Split the YAML file by document separators
info "Splitting YAML file into individual resources..."
csplit -s -f "$TEMP_DIR/resource-" "$YAML_FILE" '/^---$/' '{*}' || {
    error "Failed to split YAML file"
    exit 1
}

# Apply each resource file
RESOURCE_COUNT=0
APPLIED_COUNT=0

for resource_file in "$TEMP_DIR"/resource-*; do
    # Skip empty files
    if [[ ! -s "$resource_file" ]]; then
        continue
    fi
    
    # Skip files that are just comments
    if ! grep -q "metadata:" "$resource_file" 2>/dev/null; then
        continue
    fi
    
    RESOURCE_COUNT=$((RESOURCE_COUNT + 1))
    
    # Extract resource type and ID for logging
    RESOURCE_TYPE=$(grep "type:" "$resource_file" | head -1 | awk '{print $2}' || echo "Unknown")
    RESOURCE_ID=$(grep "id:" "$resource_file" | head -1 | awk '{print $2}' || echo "Unknown")
    
    info "Applying resource $RESOURCE_COUNT: $RESOURCE_TYPE/$RESOURCE_ID"
    
    if omnictl apply -f "$resource_file" 2>&1; then
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
        log "✓ Applied: $RESOURCE_TYPE/$RESOURCE_ID"
    else
        error "Failed to apply: $RESOURCE_TYPE/$RESOURCE_ID"
        exit 1
    fi
    
    # Small delay between resources
    sleep 0.5
done

log "✓ Successfully applied $APPLIED_COUNT/$RESOURCE_COUNT resources"

# Show created resources
info "Verifying created resources..."
echo ""
omnictl get clusters 2>/dev/null || true
echo ""
omnictl get machineclasses 2>/dev/null || true
echo ""
omnictl get machinesets 2>/dev/null || true

log "✓ Cluster configuration applied successfully!"
