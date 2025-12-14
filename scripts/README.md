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

### deploy-infrastructure.sh

**Purpose:** Automated end-to-end deployment of infrastructure and Talos clusters using the hybrid approach.

**What it does:**
1. Validates prerequisites (Terraform, omnictl, kubectl)
2. Provisions VMs using Terraform (vSphere or Proxmox)
3. Waits for machines to register with Omni
4. Applies Omni cluster configuration
5. Retrieves and saves kubeconfig

**Features:**
- Supports both vSphere and Proxmox platforms
- Automatic prerequisite checking
- Color-coded progress output
- Error handling and rollback capability
- Saves kubeconfig to project root

**Usage:**

```bash
# Deploy vSphere cluster
./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml

# Deploy Proxmox cluster
./scripts/deploy-infrastructure.sh proxmox clusters/omni/dev-proxmox.yaml
```

**Arguments:**
- `$1` - Platform: `vsphere` or `proxmox`
- `$2` - Path to Omni cluster YAML configuration file

**Prerequisites:**
- Terraform variables configured (`terraform.tfvars`)
- Omni credentials set:
  ```bash
  export OMNI_ENDPOINT=https://omni.siderolabs.com
  export OMNI_API_KEY=<your-api-key>
  ```
- Tools installed (terraform, omnictl, kubectl)

**Example Workflow:**

```bash
# 1. Install dependencies
./scripts/install-dependencies.sh

# 2. Configure Terraform
cd terraform/vsphere
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
cd ../..

# 3. Set Omni credentials
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=your-api-key-here

# 4. Deploy cluster
./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml

# 5. Verify cluster
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

---

## Script Execution Order

For a fresh setup, run scripts in this order:

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

**Last Updated:** 2025-12-14
