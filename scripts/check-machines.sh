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

usage() {
    cat << EOF
${GREEN}Usage:${NC} $0 [cluster-yaml-file]

${YELLOW}Check Omni machine registration and labeling status.${NC}

Shows:
- Registered machines and connection status
- Required labels for cluster allocation
- Labeling instructions

${GREEN}Example:${NC}
  $0 clusters/omni/dk1d/cluster-baseline.yaml

${GREEN}Size Class Format:${NC}
  CPUxMEMORY where MEMORY is in GB
  
  Examples:
    2x4    - 2 CPU, 4GB RAM
    4x8    - 4 CPU, 8GB RAM
    8x16   - 8 CPU, 16GB RAM
    16x32  - 16 CPU, 32GB RAM

EOF
    exit 1
}

# Parse arguments
CLUSTER_FILE=""
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
    fi
    CLUSTER_FILE="$1"
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Omni Machine Status Checker                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check registered machines
log "Checking registered machines..."
MACHINES=$(omnictl get machines 2>&1)

if echo "$MACHINES" | grep -q "No resources found"; then
    warn "No machines registered with Omni yet"
    echo ""
    info "Machines will appear 2-5 minutes after VMs boot"
    exit 0
fi

echo "$MACHINES"
echo ""

# Count machines
MACHINE_COUNT=$(echo "$MACHINES" | grep -c "^default" || echo "0")
CONNECTED_COUNT=$(echo "$MACHINES" | grep -c "true" || echo "0")

log "Found $MACHINE_COUNT machines ($CONNECTED_COUNT connected)"
echo ""

# Check machine labels
log "Checking machine labels..."
MACHINE_IDS=$(omnictl get machines -o json 2>/dev/null | jq -r '.metadata.id' 2>/dev/null || echo "")

if [[ -z "$MACHINE_IDS" ]]; then
    warn "Could not retrieve machine IDs"
    exit 1
fi

echo ""
echo "Machine Label Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

UNLABELED_COUNT=0
LABELED_COUNT=0

for machine_id in $MACHINE_IDS; do
    echo -ne "Machine: ${machine_id:0:8}... "
    
    # Check if machine has labels
    LABELS=$(omnictl get machinelabels "$machine_id" -o yaml 2>/dev/null | grep -A 10 "labels:" || echo "")
    
    if echo "$LABELS" | grep -q "site:\|platform:\|proxmox\|vsphere"; then
        echo -e "${GREEN}✓ Labeled${NC}"
        LABELED_COUNT=$((LABELED_COUNT + 1))
        
        # Show labels
        echo "$LABELS" | grep -E "^\s+(site|platform|proxmox|vsphere|small|medium|large):" | sed 's/^/    /'
    else
        echo -e "${RED}✗ Not labeled${NC}"
        UNLABELED_COUNT=$((UNLABELED_COUNT + 1))
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show required labels if cluster file provided
if [[ -n "$CLUSTER_FILE" ]]; then
    if [[ -f "$CLUSTER_FILE" ]]; then
        log "Required labels for cluster: $(basename "$CLUSTER_FILE")"
        
        SITE=$(grep -m 1 "Site:" "$CLUSTER_FILE" | awk '{print $3}')
        PLATFORM=$(grep "platform = " "$CLUSTER_FILE" | head -1 | awk '{print $3}' || echo "unknown")
        
        echo ""
        echo "  Required labels (comma-separated in Omni UI):"
        echo "  ${YELLOW}$SITE, $PLATFORM, small${NC}"
        echo ""
        echo "  Or adjust based on your VM size:"
        echo "    small:  2 CPU, 4-8GB RAM"
        echo "    medium: 4 CPU, 8-16GB RAM"
        echo "    large:  8+ CPU, 16+GB RAM"
    else
        warn "Cluster file not found: $CLUSTER_FILE"
    fi
fi

# Summary and instructions
echo ""
if [[ $UNLABELED_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Action Required: Label Machines in Omni UI              ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    warn "$UNLABELED_COUNT machine(s) need to be labeled"
    echo ""
    echo "Steps to label machines:"
    echo ""
    echo "1. Open Omni UI: https://your-omni-instance/machines"
    echo "2. Select each machine"
    echo "3. Add labels (comma-separated):"
    echo "   - site code (e.g., dk1d)"
    echo "   - platform (proxmox or vsphere)"
    echo "   - size class (CPUxMEMORY format, e.g., 2x4, 4x8, 8x16)"
    echo ""
    echo "Example: ${GREEN}dk1d, proxmox, 2x4${NC}"
    echo ""
    echo "4. Size class must match actual VM resources exactly"
    echo "5. After labeling, machines will be automatically allocated to matching"
    echo "   MachineSets based on MachineClass requirements"
    echo ""
else
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  All Machines Are Properly Labeled!                       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "✓ All $LABELED_COUNT machines have labels"
    echo ""
    info "Machines should be allocated to MachineSets automatically"
    echo "Check status with: omnictl get clustermachines"
fi
