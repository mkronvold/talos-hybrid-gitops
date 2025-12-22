# Scripts Directory

This directory contains automation scripts for managing the Talos Hybrid GitOps infrastructure.

## Table of Contents

- [Installation Scripts](#installation-scripts)
  - [install-dependencies.sh](#install-dependenciessh)
  - [install-node-copilot.sh](#install-node-copilotsh)
- [Deployment Scripts](#deployment-scripts)
  - [deploy-infrastructure.sh](#deploy-infrastructuresh)
- [Maintenance](#maintenance)

---

## Site and Cluster Management Scripts

### modify-site.sh

**Purpose:** Safely modify site metadata and configuration.

**What it does:**
1. Shows current site metadata
2. Updates location name
3. Changes platform (with safety warnings)
4. Archives old configurations during platform changes
5. Provides next steps after modifications

**Features:**
- Safe metadata editing (no manual file editing)
- Platform change with destructive operation warnings
- Configuration archiving before changes
- Validation of all inputs
- Comprehensive next steps guidance

**Usage:**

```bash
# Show current site metadata
./scripts/modify-site.sh ny1d --show

# Update location name
./scripts/modify-site.sh ny1d --location "New York Zone 1 Primary"

# Change platform (destructive - requires confirmation)
./scripts/modify-site.sh ny1d --platform proxmox
```

**Options:**
- `--show` - Display current site metadata and configuration files
- `--location <name>` - Update the location name
- `--platform <type>` - Change platform (vsphere or proxmox)
- `--help` - Show help message

**Platform Change Warning:**

Changing platform is a **destructive operation** that requires:
1. Destroying existing infrastructure
2. Archiving old Terraform configurations
3. Creating new platform-specific configurations
4. Redeploying all clusters and resources

The script will:
- Prompt for confirmation (type "yes")
- Archive old configurations to `.archive-YYYYMMDD-HHMMSS/`
- Update metadata file
- Provide detailed next steps

**When to Use:**
- ✅ Fixing typos in location name
- ✅ Updating location description
- ✅ Migrating site to different platform
- ❌ Changing site code (use new-site.sh instead)
- ❌ Changing environment (recreate site with correct code)

---

### new-site.sh

**Purpose:** Creates a new site with all necessary scaffolding and configuration files.

**What it does:**
1. Validates site code format
2. Creates site directory structure
3. Generates Terraform configurations for all platforms
4. Creates site-specific documentation
5. Sets up templates for clusters

**Features:**
- Site code validation and environment detection
- Configurable vSphere/Proxmox settings
- Generates configs for vsphere, proxmox, and jumphost
- Creates site README with quickstart guide

**Usage:**

```bash
# Create site with minimal options
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"

# Create site with full vSphere configuration
./scripts/new-site.sh sf2p vsphere \
  --location "San Francisco Zone 2" \
  --datacenter "SF-DC" \
  --cluster "SF-Cluster-2" \
  --vcenter "vcenter-sf.example.com"
```

**Arguments:**
- `site-code` - Site identifier (e.g., ny1d, sf2p)
- `platform` - vsphere or proxmox

**Options:**
- `--location` - Full location name
- `--datacenter` - vSphere datacenter name
- `--cluster` - vSphere cluster name
- `--datastore` - vSphere datastore name
- `--network` - Network name
- `--vcenter` - vCenter server address
- `--folder` - VM folder path

**Generated Files:**
- `clusters/omni/<site-code>/.site-metadata` (platform tracking - committed to repo)
- `terraform/<platform>/terraform.tfvars.<site-code>` (infrastructure)
- `terraform/jumphost-vsphere/terraform.tfvars.<site-code>` (vSphere jumphost)
- `terraform/jumphost-proxmox/terraform.tfvars.<site-code>` (Proxmox jumphost)
- `clusters/omni/<site-code>/README.md`

**Platform Tracking:**
The site's platform (vsphere/proxmox) is stored in `.site-metadata` and used by all scripts to automatically select the correct platform. This eliminates the need to specify platform in deployment commands.

**Jumphost Platform Support:**
- vSphere: Uses `terraform/jumphost-vsphere/` with vSphere provider
- Proxmox: Uses `terraform/jumphost-proxmox/` with Proxmox provider
- Both use identical cloud-init for tool installation

---

### new-cluster.sh

**Purpose:** Creates an Omni cluster configuration for a specific site.

**What it does:**
1. Validates site code and cluster name
2. Creates Omni cluster YAML with specified topology
3. Configures control plane and worker machine sets
4. Calculates total resource requirements
5. Updates site README with cluster information

**Features:**
- Flexible cluster sizing (control planes + workers)
- Configurable per-node resources (CPU, memory, disk)
- Kubernetes and Talos version selection
- Automatic resource calculation
- Site and platform labeling for machine allocation

**Usage:**

```bash
# Create basic cluster with defaults (3 CP + 3 workers)
./scripts/new-cluster.sh ny1d web

# Create cluster with custom sizing
./scripts/new-cluster.sh sf2p data \
  --control-planes 5 \
  --workers 10 \
  --cpu 8 \
  --memory 16384

# Create small dev cluster
./scripts/new-cluster.sh la1s dev \
  --control-planes 1 \
  --workers 2 \
  --cpu 2 \
  --memory 4096
```

**Arguments:**
- `site-code` - Site identifier (e.g., ny1d)
- `cluster-name` - Cluster name (e.g., web, data, ml)

**Options:**
- `--control-planes <n>` - Number of control plane nodes (default: 3)
- `--workers <n>` - Number of worker nodes (default: 3)
- `--cpu <n>` - CPU cores per node (default: 4)
- `--memory <mb>` - Memory in MB per node (default: 8192)
- `--disk <gb>` - Disk size in GB (default: 100)
- `--k8s-version <ver>` - Kubernetes version (default: v1.29.0)
- `--talos-version <ver>` - Talos version (default: v1.9.5)

**Note:** Platform is automatically detected from site configuration.

**Generated Files:**
- `clusters/omni/<site-code>/<cluster-name>.yaml`

**Cluster Naming:**
Full cluster name: `<site-code>-<cluster-name>`
- Example: `ny1d-web`, `sf2p-data`

**Important:** After creating a cluster, update the Terraform config with the calculated node count and resources.

---

## Installation Scripts

### install-dependencies.sh

**Purpose:** Installs all required CLI tools for managing Talos clusters and infrastructure.

**Installs:**
- Terraform
- kubectl
- Flux CD
- Omni CLI (omnictl)
- Talosctl

**Installation Methods:**

1. **Homebrew (Recommended - macOS/Linux):**
   - Uses `brew install siderolabs/tap/sidero-tools` to install omnictl, talosctl, and kubectl in one command
   - Then installs Terraform and Flux separately
   - Fastest and most reliable method

2. **Manual (Linux without Homebrew):**
   - Downloads binaries directly from official sources
   - Installs to `/usr/local/bin` or custom directory
   - Auto-detects OS and architecture

**Features:**
- Auto-detects Homebrew and uses simplified installation
- Falls back to manual installation if Homebrew not available
- Auto-detects OS (Linux/macOS) and architecture (amd64/arm64)
- Checks for existing installations
- Supports custom installation directory (manual mode only)

**Usage:**

```bash
# Automatic install (detects Homebrew)
./scripts/install-dependencies.sh

# Custom install directory (manual mode only)
INSTALL_DIR=~/bin ./scripts/install-dependencies.sh
```

**Requirements:**
- **Homebrew mode:** Homebrew installed (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- **Manual mode:** curl, unzip (for Terraform), sudo privileges (for system-wide install)

**References:**
- Sidero Tools: https://github.com/siderolabs/homebrew-tap
- Official Docs: https://docs.siderolabs.com/omni/getting-started/getting-started

---

### install-node-copilot.sh

**Purpose:** Installs Node.js development environment and GitHub Copilot CLI.

**Installs:**
- NVM (Node Version Manager) v0.40.1
- Node.js LTS (via NVM)
- npm (bundled with Node.js)
- GitHub Copilot CLI

**Features:**
- Installs NVM and configures shell integration
- Uses NVM to manage Node.js versions
- Installs Copilot CLI globally via npm
- Checks for existing installations
- Provides post-install setup instructions

**Usage:**

```bash
./scripts/install-node-copilot.sh
```

**Post-Installation:**

After running the script, reload your shell:

```bash
# For bash
source ~/.bashrc

# For zsh
source ~/.zshrc

# Or open a new terminal
```

Then authenticate Copilot CLI:

```bash
github-copilot-cli auth
```

**Requirements:**
- curl
- bash or zsh

---

## Deployment Scripts

### deploy-jumphost.sh

**Purpose:** Deploys site-specific Ubuntu management jumphost VMs with all tools pre-installed.

**What it does:**
1. Loads site metadata to detect platform (vSphere or Proxmox)
2. Validates site code format (e.g., ny1d, sf2p)
3. Validates prerequisites (Terraform)
4. Checks for site-specific configuration
5. Creates/uses Terraform workspace for site isolation
6. Deploys Ubuntu VM to vSphere or Proxmox
7. Cloud-init automatically installs:
   - Talos Hybrid GitOps repository
   - All CLI tools (Terraform, kubectl, Flux, omnictl, talosctl)
   - Node.js, npm, and GitHub Copilot CLI
   - Essential development tools

**Features:**
- **Multi-platform support:** vSphere and Proxmox
- Platform auto-detection from site metadata
- Multi-site support with workspace isolation
- Site code validation (2-letter city + zone + environment)
- Automated VM provisioning with cloud-init
- Pre-configured with all necessary tools
- SSH key authentication
- Customizable VM specifications per site
- Saves connection information to `jumphost-<site-code>.txt`

**Site Code Format:**
```
<city><zone><env>

Examples:
  ny1d - New York, Zone 1, Dev
  sf2p - San Francisco, Zone 2, Prod
  la1s - Los Angeles, Zone 1, Staging
  ch3p - Chicago, Zone 3, Prod

Components:
  <city> - 2-letter city/location code
  <zone> - Single digit zone number (1-9)
  <env>  - Environment: d (dev), s (staging), p (prod)
```

**Usage:**

```bash
# 1. Create site-specific configuration (vSphere)
cd terraform/jumphost-vsphere
cp terraform.tfvars.example terraform.tfvars.ny1d
# Edit with site-specific settings (hostname: jumphost-ny1d)

# OR for Proxmox
cd terraform/jumphost-proxmox
cp terraform.tfvars.example terraform.tfvars.sf2p
# Edit with site-specific settings (hostname: jumphost-sf2p)

# 2. Deploy jumphost (platform auto-detected)
cd ../..
./scripts/deploy-jumphost.sh ny1d
./scripts/deploy-jumphost.sh sf2p
```

**Configuration Files:**
- vSphere sites: `terraform/jumphost-vsphere/terraform.tfvars.<site-code>`
- Proxmox sites: `terraform/jumphost-proxmox/terraform.tfvars.<site-code>`
- Example: `terraform.tfvars.ny1d`, `terraform.tfvars.sf2p`
- Terraform workspaces provide state isolation per site

**Prerequisites:**
- Terraform installed locally
- vSphere credentials configured
- Ubuntu cloud image OVA template in vSphere
- SSH public key(s) for access

**Ubuntu Cloud Image Setup:**

Download Ubuntu cloud image:
```bash
# Ubuntu 22.04 LTS
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova

# Import to vSphere as template named "ubuntu-22.04-cloud"
```

**Configuration Options:**
- `jumphost_hostname` - VM hostname (default: talos-jumphost)
- `jumphost_cpu` - Number of CPUs (default: 2)
- `jumphost_memory` - Memory in MB (default: 4096)
- `jumphost_disk_size` - Disk size in GB (default: 50)
- `jumphost_ssh_keys` - List of SSH public keys

**Platform-Specific Setup:**

vSphere:
```bash
# Download Ubuntu cloud image OVA
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova
# Import to vSphere as template named "ubuntu-22.04-cloud"
```

Proxmox:
```bash
# Create Ubuntu cloud image template in Proxmox
# See: https://pve.proxmox.com/wiki/Cloud-Init_Support
# Default template ID: 9000
```

**Post-Deployment:**

Wait 5-10 minutes for cloud-init to complete, then SSH:
```bash
ssh ubuntu@<jumphost-ip>

# Check cloud-init progress
tail -f /var/log/cloud-init-output.log

# Verify tools installed
cd ~/talos-hybrid-gitops
terraform version
kubectl version --client
omnictl version
```

---

### deploy-infrastructure.sh

**Purpose:** Automated end-to-end deployment of site-specific infrastructure and Talos clusters using the hybrid approach.

**What it does:**
1. Validates site code format and prerequisites
2. Provisions VMs using Terraform with workspace isolation per site
3. Waits for machines to register with Omni
4. Applies site-specific Omni cluster configuration
5. Retrieves and saves kubeconfig as `kubeconfig-<site-code>`

**Features:**
- Multi-site support with workspace isolation
- Site code validation (2-letter city + zone + environment)
- Supports both vSphere and Proxmox platforms
- Automatic prerequisite checking
- Color-coded progress output
- Error handling and recovery
- Per-site kubeconfig files

**Usage:**

```bash
# Deploy NY Zone 1 Dev cluster (platform auto-detected)
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/web.yaml

# Deploy SF Zone 2 Prod cluster (platform auto-detected)
./scripts/deploy-infrastructure.sh sf2p clusters/omni/sf2p/data.yaml

# Deploy infrastructure only (configure cluster later)
./scripts/deploy-infrastructure.sh la1s
```

**Arguments:**
- `$1` - Site code: e.g., `ny1d`, `sf2p`, `la1s`
- `$2` - (Optional) Path to Omni cluster YAML configuration file

**Note:** Platform is automatically detected from site configuration.

**Prerequisites:**
- Site-specific Terraform variables configured (`terraform.tfvars.<site-code>`)
- Omni credentials set:
  ```bash
  source ~/omni.sh
  ```
- Tools installed (terraform, omnictl, kubectl)

**Configuration Files:**
- Terraform: `terraform/<platform>/terraform.tfvars.<site-code>`
- Cluster: `clusters/omni/<site-code>-cluster.yaml`

**Example Workflow:**

```bash
# 1. Install dependencies (or use jumphost)
./scripts/install-dependencies.sh

# 2. Configure Terraform for site
cd terraform/vsphere
cp terraform.tfvars.example terraform.tfvars.ny1d
# Edit terraform.tfvars.ny1d with NY zone 1 dev settings
cd ../..

# 3. Create cluster configuration
mkdir -p clusters/omni
cat > clusters/omni/ny1d-cluster.yaml <<EOF
# Your Omni cluster configuration for NY Zone 1 Dev
EOF

# 4. Set Omni credentials
source ~/omni.sh

# 5. Deploy site infrastructure and cluster
./scripts/deploy-infrastructure.sh ny1d vsphere clusters/omni/ny1d-cluster.yaml

# 6. Verify cluster
export KUBECONFIG=./kubeconfig-ny1d
kubectl get nodes
```

---

## Script Execution Order

### Complete Multi-Site Workflow

#### 1. Create a New Site
```bash
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"
```

#### 2. Create Cluster(s) for the Site
```bash
# Create web cluster
./scripts/new-cluster.sh ny1d web --control-planes 3 --workers 5

# Create data cluster
./scripts/new-cluster.sh ny1d data --control-planes 5 --workers 10 --cpu 8 --memory 16384
```

#### 3. Deploy Jumphost (Optional but Recommended)
```bash
./scripts/deploy-jumphost.sh ny1d
```

#### 4. Deploy Infrastructure and Clusters
```bash
# Set Omni credentials
source ~/omni.sh

# Deploy (platform auto-detected from site)
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/web.yaml
```

### Option B: Local Installation

1. **install-dependencies.sh** - Install infrastructure management tools
2. **install-node-copilot.sh** - (Optional) Install Node.js and Copilot CLI for development
3. **deploy-infrastructure.sh** - Deploy your infrastructure and clusters

---

## Maintenance

This README is maintained whenever scripts are created or updated. When making changes:

1. **Adding a new script:**
   - Add a new section describing the script
   - Include purpose, features, usage, and requirements
   - Update the Table of Contents

2. **Updating an existing script:**
   - Update the corresponding section with new features or changes
   - Update version numbers if applicable
   - Update usage examples if syntax changes

3. **Removing a script:**
   - Remove the corresponding section
   - Update the Table of Contents
   - Add a note in the removal commit message

---

## Troubleshooting

### Script fails with "Permission denied"

Make scripts executable:
```bash
chmod +x scripts/*.sh
```

### "Command not found" after installing tools

For system-wide installs, ensure `/usr/local/bin` is in your PATH:
```bash
echo $PATH | grep -q "/usr/local/bin" || echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For NVM/Node installations, reload your shell:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

### Terraform apply fails

1. Verify `terraform.tfvars` is configured correctly
2. Check connectivity to vSphere/Proxmox
3. Verify credentials have appropriate permissions
4. Check Terraform state: `cd terraform/<platform> && terraform state list`

### Omni cluster creation fails

1. Verify Omni credentials are set:
   ```bash
   echo $OMNI_ENDPOINT
   echo $OMNI_SERVICE_ACCOUNT_KEY
   ```
2. Check machines are registered: `omnictl get machines`
3. Verify cluster YAML syntax: `omnictl validate -f <cluster-yaml>`
4. Check Omni dashboard: https://omni.siderolabs.com

---

## Additional Resources

- [Main README](../README.md) - Project overview and architecture
- [DEPLOYMENT-WORKFLOW.md](../docs/DEPLOYMENT-WORKFLOW.md) - Complete deployment workflow
- [QUICKSTART.md](../docs/QUICKSTART.md) - Quick start guide
- [Terraform Examples](../terraform/) - Infrastructure as Code examples
- [Omni Cluster Configs](../clusters/omni/) - Cluster configuration examples

---

**Last Updated:** 2025-12-14T03:22:41.859Z
