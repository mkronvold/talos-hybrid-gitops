#!/bin/bash
# Generate jumphost terraform.tfvars with GitHub SSH keys

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Usage
usage() {
    cat << EOF
Usage: $0 <site-code> <github-username> [options]

Generate jumphost terraform.tfvars with SSH keys from GitHub.

Arguments:
  site-code         Site code (e.g., dk1d, ny1p)
  github-username   GitHub username to fetch SSH keys from

Options:
  --password        Proxmox root password (prompts if not provided)
  --platform        Platform (proxmox or vsphere, auto-detected from site metadata)
  --help            Show this help message

Examples:
  $0 dk1d mkronvold
  $0 ny1p mkronvold --password mypass

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

SITE_CODE=$1
GITHUB_USER=$2
shift 2

PASSWORD=""
PLATFORM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Detect platform from site metadata if not provided
if [ -z "$PLATFORM" ]; then
    SITE_METADATA_FILE="$REPO_ROOT/clusters/omni/$SITE_CODE/.site-metadata"
    if [ -f "$SITE_METADATA_FILE" ]; then
        PLATFORM=$(grep "^PLATFORM=" "$SITE_METADATA_FILE" | cut -d= -f2 | tr -d '"')
        echo "Detected platform: $PLATFORM"
    else
        echo "Error: Could not detect platform. Site metadata not found."
        echo "Use --platform to specify manually."
        exit 1
    fi
fi

# Only support Proxmox for now
if [ "$PLATFORM" != "proxmox" ]; then
    echo "Error: This script currently only supports Proxmox platform."
    echo "Platform detected: $PLATFORM"
    exit 1
fi

# Prompt for password if not provided
if [ -z "$PASSWORD" ]; then
    read -s -p "Enter Proxmox root password: " PASSWORD
    echo
fi

# Fetch SSH keys from GitHub
echo "Fetching SSH keys from GitHub for user: $GITHUB_USER"
SSH_KEYS_RAW=$(curl -s "https://github.com/${GITHUB_USER}.keys")

if [ -z "$SSH_KEYS_RAW" ]; then
    echo "Error: No SSH keys found for GitHub user: $GITHUB_USER"
    exit 1
fi

# Format SSH keys for HCL
SSH_KEYS=$(echo "$SSH_KEYS_RAW" | awk '{print "  \"" $0 "\","}' | sed '$ s/,$//')

# Get existing values if file exists
TERRAFORM_DIR="$REPO_ROOT/terraform/jumphost-$PLATFORM"
TFVARS_FILE="$TERRAFORM_DIR/terraform.tfvars.$SITE_CODE"

# Load existing values if available
if [ -f "$TFVARS_FILE" ]; then
    ENDPOINT=$(grep "^proxmox_endpoint" "$TFVARS_FILE" | cut -d= -f2- | tr -d ' "')
    NODE=$(grep "^proxmox_node" "$TFVARS_FILE" | cut -d= -f2- | tr -d ' "')
    DATASTORE=$(grep "^proxmox_datastore" "$TFVARS_FILE" | cut -d= -f2- | tr -d ' "')
    TEMPLATE_ID=$(grep "^ubuntu_template_id" "$TFVARS_FILE" | cut -d= -f2- | tr -d ' ')
else
    # Use defaults
    ENDPOINT="https://proxmox.example.com:8006"
    NODE="pve"
    DATASTORE="local-lvm"
    TEMPLATE_ID="9000"
fi

# Generate tfvars file
cat > "$TFVARS_FILE" << EOF
# Proxmox endpoint
proxmox_endpoint = "$ENDPOINT"
proxmox_insecure = true  # Set to false with valid SSL cert

# Authentication - Username/Password
proxmox_username = "root@pam"
proxmox_password = "$PASSWORD"

# Proxmox Resources
proxmox_node      = "$NODE"
proxmox_datastore = "$DATASTORE"
proxmox_bridge    = "vmbr0"

# Ubuntu Template
ubuntu_template_id = $TEMPLATE_ID

# Jumphost Configuration
jumphost_hostname = "talos-jumphost-$SITE_CODE"
jumphost_cpu      = 2
jumphost_memory   = 4096
jumphost_disk_size = 50

# User Configuration (auto-populated from GitHub)
jumphost_username = "$GITHUB_USER"
jumphost_ssh_keys = [
$SSH_KEYS
]

# Optional: Set timezone
jumphost_timezone = "UTC"
EOF

echo "✓ Generated: $TFVARS_FILE"
echo ""
echo "SSH keys loaded from GitHub user: $GITHUB_USER"
echo "Found $(echo "$SSH_KEYS_RAW" | wc -l) SSH key(s)"
echo ""
echo "Review and adjust settings as needed:"
echo "  nano $TFVARS_FILE"
echo ""
echo "Deploy with:"
echo "  ./scripts/deploy-jumphost.sh $SITE_CODE"
