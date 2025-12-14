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
- `terraform/vsphere/terraform.tfvars.<site-code>`
- `terraform/proxmox/terraform.tfvars.<site-code>`
- `terraform/jumphost/terraform.tfvars.<site-code>`
- `clusters/omni/<site-code>/README.md`

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
- `--platform <name>` - Platform label (default: vsphere)

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
- Terraform v1.6.0
- kubectl (stable)
- Flux CD
- Omni CLI (omnictl)
- Talosctl v1.9.5

**Features:**
- Auto-detects OS (Linux/macOS) and architecture (amd64/arm64)
- Checks for existing installations
- Prompts for reinstallation if tools already exist
- Supports custom installation directory

**Usage:**

```bash
# System-wide install (requires sudo)
./scripts/install-dependencies.sh

# Custom install directory
INSTALL_DIR=~/bin ./scripts/install-dependencies.sh
```

**Requirements:**
- curl
- unzip (for Terraform)
- sudo privileges (for system-wide install)

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
1. Validates site code format (e.g., ny1d, sf2p)
2. Validates prerequisites (Terraform)
3. Checks for site-specific configuration
4. Creates/uses Terraform workspace for site isolation
5. Deploys Ubuntu VM to vSphere
6. Cloud-init automatically installs:
   - Talos Hybrid GitOps repository
   - All CLI tools (Terraform, kubectl, Flux, omnictl, talosctl)
   - Node.js, npm, and GitHub Copilot CLI
   - Essential development tools

**Features:**
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
# 1. Create site-specific configuration
cd terraform/jumphost
cp terraform.tfvars.example terraform.tfvars.ny1d
# Edit with site-specific settings (hostname: jumphost-ny1d)

# 2. Deploy jumphost for New York Zone 1 Dev
cd ../..
./scripts/deploy-jumphost.sh ny1d

# 3. Deploy jumphost for San Francisco Zone 2 Prod
./scripts/deploy-jumphost.sh sf2p
```

**Configuration Files:**
- Each site requires: `terraform/jumphost/terraform.tfvars.<site-code>`
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
# Deploy NY Zone 1 Dev cluster on vSphere
./scripts/deploy-infrastructure.sh ny1d vsphere clusters/omni/ny1d-cluster.yaml

# Deploy SF Zone 2 Prod cluster on Proxmox
./scripts/deploy-infrastructure.sh sf2p proxmox clusters/omni/sf2p-cluster.yaml

# Deploy infrastructure only (configure cluster later)
./scripts/deploy-infrastructure.sh la1s vsphere
```

**Arguments:**
- `$1` - Site code: e.g., `ny1d`, `sf2p`, `la1s`
- `$2` - Platform: `vsphere` or `proxmox`
- `$3` - (Optional) Path to Omni cluster YAML configuration file

**Prerequisites:**
- Site-specific Terraform variables configured (`terraform.tfvars.<site-code>`)
- Omni credentials set:
  ```bash
  export OMNI_ENDPOINT=https://omni.siderolabs.com
  export OMNI_API_KEY=<your-api-key>
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
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=your-api-key-here

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
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-key>

# Deploy
./scripts/deploy-infrastructure.sh ny1d vsphere clusters/omni/ny1d/web.yaml
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
   echo $OMNI_API_KEY
   ```
2. Check machines are registered: `omnictl get machines`
3. Verify cluster YAML syntax: `omnictl validate -f <cluster-yaml>`
4. Check Omni dashboard: https://omni.siderolabs.com

---

## Additional Resources

- [Main README](../README.md) - Project overview and architecture
- [WORKFLOW.md](../WORKFLOW.md) - Complete workflow examples and day-2 operations
- [QUICKSTART.md](../docs/QUICKSTART.md) - Quick start guide
- [Terraform Examples](../terraform/) - Infrastructure as Code examples
- [Omni Cluster Configs](../clusters/omni/) - Cluster configuration examples

---

**Last Updated:** 2025-12-14T01:41:29.156Z
