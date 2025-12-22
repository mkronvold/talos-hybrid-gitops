# Talos Hybrid GitOps

Automated Talos Kubernetes cluster deployment using Terraform + Omni.

## What This Does

Deploys Talos Kubernetes clusters across vSphere or Proxmox with:
- **Omni** - Talos cluster orchestration and management
- **Terraform** - VM infrastructure provisioning  
- **Pre-configured ISOs** - Machines auto-register with Omni on boot
- **Site labels** - Automatic machine classification by site/platform

## Quick Start

### 1. Install Tools

```bash
# macOS/Linux with Homebrew
brew install siderolabs/tap/sidero-tools terraform

# Or use automated script
./scripts/install-dependencies.sh
```

### 2. Get Omni Credentials

1. Visit your Omni instance (e.g., `https://yourorg.omni.siderolabs.io`)
2. Create a service account: Settings → Service Accounts
3. Download the `omni.sh` credentials file
4. Add to your shell: `echo "source ~/omni.sh" >> ~/.bashrc`

### 3. Create a Site

```bash
# Create site structure and configuration
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"
```

This creates:
- `clusters/omni/dk1d/` - Cluster configurations
- `clusters/omni/dk1d/site-dk1d.yaml` - Site metadata
- `terraform/proxmox/terraform.tfvars.dk1d` - Infrastructure config for the entire site

### 4. Configure Terraform

Edit `terraform/proxmox/terraform.tfvars.dk1d` with your Proxmox details:

```hcl
proxmox_endpoint = "https://proxmox.example.com:8006"
proxmox_api_token = "root@pam!terraform=xxx-xxx-xxx"
proxmox_node = "pve"
proxmox_datastore = "local-lvm"
proxmox_bridge = "vmbr0"
```

### 5. Create a Cluster

```bash
# Interactive mode (recommended)
./scripts/new-cluster.sh dk1d baseline -i

# Or specify all options (using size class format CPUxMEMORY)
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 3 \
  --size-class 2x4
```

This creates: `clusters/omni/dk1d/cluster-baseline.yaml`

### 6. Prepare Omni ISOs

```bash
# Generate ISO for each Talos version needed by your clusters
./scripts/prepare-omni-iso.sh dk1d
```

**What happens:**
- Downloads Omni ISO for each Talos version used by clusters
- Includes your Omni credentials + site labels
- Includes platform-specific guest agents (qemu/vmware)
- Uploads ISO to Proxmox storage

### 7. Update Terraform Variables

```bash
# Auto-generate vm_configs from all cluster YAMLs
./scripts/update-tfvars.sh dk1d
```

This reads all cluster YAML files in the site and updates `terraform.tfvars.dk1d` with:
- Aggregated VM requirements grouped by size class and role
- ISO image URLs for each Talos version used by clusters
- Total VMs needed across all clusters in the site

### 8. Provision Nodes

```bash
# Deploy VMs with Terraform
./scripts/provision-nodes.sh dk1d
```

VMs boot from Omni ISO and auto-register with Omni (labeled: `site=dk1d`, `platform=proxmox`, `size_class=2x4`)

### 9. Apply Cluster Configurations

```bash
# Apply all clusters in the site
./scripts/apply-clusters.sh dk1d

# Or apply specific cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

This creates MachineClasses with filters matching your machine labels, then creates the cluster.

### 10. Access Your Cluster

```bash
# Get kubeconfig for all clusters in site
./scripts/get-kubeconfigs.sh dk1d

# Or manually for specific cluster
omnictl kubeconfig dk1d-baseline > kubeconfig-dk1d
export KUBECONFIG=./kubeconfig-dk1d
kubectl get nodes
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Git Repository                                      │
│  ├── terraform/        Infrastructure as Code       │
│  │   └── proxmox/                                   │
│  │       └── terraform.tfvars.{site}  (per site)   │
│  ├── clusters/omni/    Cluster definitions          │
│  │   └── {site}/      (multiple clusters per site) │
│  └── scripts/          Automation                   │
└─────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
    Terraform            omnictl
    ─────────            ───────
    Provisions           Configures
    VMs for all          Talos
    clusters in          clusters
    site
         │                    │
         ▼                    ▼
    ┌─────────┐         ┌─────────┐
    │   VMs   │ ──────▶ │ Talos   │
    │ Running │ (Omni)  │Clusters │
    └─────────┘         └─────────┘
```

## Key Features

### 🏷️ Site-Based Organization

Sites follow the pattern: `<location><zone><environment>`

Examples:
- `ny1d` - New York, Zone 1, Dev
- `sf2p` - San Francisco, Zone 2, Prod  
- `dk1d` - Denmark, Zone 1, Dev

### 📦 Size Classes

Clusters use `CPUxMEMORY` format for exact resource specification:

- **2x4** - 2 CPU, 4GB RAM - Light workloads
- **4x8** - 4 CPU, 8GB RAM - Standard workloads  
- **8x16** - 8 CPU, 16GB RAM - Heavy workloads
- **16x32** - 16 CPU, 32GB RAM - Very heavy workloads

Machines are labeled with their exact size class (e.g., `size_class=4x8`) for precise matching.

### 🤖 Platform-Specific Guest Agents

ISOs automatically include:
- **Proxmox**: `qemu-guest-agent` (VM monitoring and management)
- **vSphere**: `vmware-guest-agent` (VMware Tools functionality)

### 📝 Interactive Cluster Creation

```bash
./scripts/new-cluster.sh dk1d web -i
```

Prompts for:
- Size class (CPUxMEMORY format like 2x4, 4x8, 8x16)
- Number of control planes and workers
- Disk size per node
- Kubernetes and Talos versions

Detects existing configurations and offers to reuse values.

## Directory Structure

```
.
├── clusters/
│   └── omni/                   # Cluster configurations by site
│       └── dk1d/              # Site: Denmark Zone 1 Dev
│           ├── site-dk1d.yaml # Site configuration (platform metadata)
│           ├── README.md      # Site documentation
│           └── cluster-baseline.yaml  # Cluster definition
├── terraform/
│   ├── proxmox/               # Proxmox VM provisioning
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.dk1d  # Site-specific vars (all clusters)
│   └── vsphere/               # vSphere VM provisioning
│       └── terraform.tfvars.ny1p  # Each site has one tfvars file
├── scripts/
│   ├── new-site.sh            # Create new site
│   ├── new-cluster.sh         # Create cluster config
│   ├── prepare-omni-iso.sh    # Generate Omni ISOs (per Talos version)
│   ├── update-tfvars.sh       # Calculate VM requirements from clusters
│   ├── provision-nodes.sh     # Deploy VMs with Terraform
│   ├── apply-cluster.sh       # Apply single cluster config
│   ├── apply-clusters.sh      # Apply all clusters in a site
│   ├── get-kubeconfigs.sh     # Download kubeconfigs for site
│   └── check-machines.sh      # Check machine registration status
└── docs/
    ├── COMPLETE-WORKFLOW.md   # End-to-end workflow guide
    ├── SCALING-CLUSTERS.md    # Scaling operations guide
    └── MACHINE-LABELING.md    # Machine labeling system
```

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `new-site.sh` | Create site structure and configs |
| `new-cluster.sh` | Generate cluster YAML (interactive or CLI) |
| `prepare-omni-iso.sh` | Download Omni ISOs for each Talos version |
| `update-tfvars.sh` | Calculate VM requirements from all cluster YAMLs in site |
| `provision-nodes.sh` | Deploy VMs with Terraform for entire site |
| `apply-cluster.sh` | Apply single cluster config to Omni |
| `apply-clusters.sh` | Apply all clusters in a site |
| `get-kubeconfigs.sh` | Download kubeconfigs for all clusters in site |
| `check-machines.sh` | Check machine registration and labeling status |
| `install-dependencies.sh` | Install required tools |

## Common Workflows

### Create Multiple Clusters in One Site

```bash
# Create baseline cluster
./scripts/new-cluster.sh dk1d baseline --size-class 2x4 --control-planes 1 --workers 3

# Create web cluster (larger)
./scripts/new-cluster.sh dk1d web --size-class 4x8 --control-planes 3 --workers 5

# Create data cluster (even larger)  
./scripts/new-cluster.sh dk1d data --size-class 8x16 --control-planes 3 --workers 10

# Prepare ISOs for all Talos versions needed
./scripts/prepare-omni-iso.sh dk1d

# Update single tfvars file with total VM requirements for all clusters
./scripts/update-tfvars.sh dk1d

# Provision all VMs for the entire site
./scripts/provision-nodes.sh dk1d

# Apply all cluster configurations
./scripts/apply-clusters.sh dk1d

# Get all kubeconfigs
./scripts/get-kubeconfigs.sh dk1d
```

### Update Existing Cluster (Scale Up/Down)

```bash
# Modify cluster YAML with new node counts
./scripts/new-cluster.sh dk1d baseline --workers 5 --force

# Recalculate VM requirements for entire site
./scripts/update-tfvars.sh dk1d

# Apply Terraform changes (provisions additional VMs or removes excess)
./scripts/provision-nodes.sh dk1d

# Machines automatically register and join
# No need to reapply cluster config unless changing resources
```

### Change Cluster Node Resources

```bash
# Create new cluster config with different size class
./scripts/new-cluster.sh dk1d baseline --size-class 8x16 --force

# This requires recreating VMs:
./scripts/update-tfvars.sh dk1d
./scripts/provision-nodes.sh dk1d

# Machines re-register with new labels
# Apply cluster config to update MachineClass filters
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

## Advanced Configuration

### Custom ISO Extensions

```bash
# Add Intel microcode updates
./scripts/prepare-omni-iso.sh dk1d --extensions intel-ucode

# Multiple extensions
./scripts/prepare-omni-iso.sh dk1d \
  --extensions intel-ucode \
  --extensions iscsi-tools
```

### Different Talos Versions Per Cluster

```bash
# Create cluster with specific Talos version
./scripts/new-cluster.sh dk1d test --talos-version 1.8.3

# Prepare ISO will automatically download all versions needed
./scripts/prepare-omni-iso.sh dk1d

# Update tfvars to include all version-specific ISOs and VM configs
./scripts/update-tfvars.sh dk1d
```

Note: Each site has one tfvars file that includes ISO URLs for all Talos versions used by clusters in that site.

### SecureBoot Support

```bash
./scripts/prepare-omni-iso.sh dk1d --secureboot
```

### Check Machine Registration Status

```bash
# View all machines and their registration status
./scripts/check-machines.sh dk1d

# Shows: UUID, labels, registration state, cluster assignment
```

## Troubleshooting

**VMs not registering with Omni?**
- Wait 2-5 minutes after boot
- Check VM console for boot errors
- Verify network connectivity to Omni endpoint
- Check Omni UI: Unassigned Machines
- Run `./scripts/check-machines.sh <site-code>` to see registration status

**Machines not joining cluster?**
- Verify machine labels match MachineClass filters
- Check labels: `site=<site-code>`, `platform=<platform>`, `size_class=<CPUxMEMORY>`
- Run `omnictl get machines` to see machine labels
- Run `omnictl get machineclasses` to see filter requirements

**Terraform errors about missing ISO?**
```bash
# Ensure ISOs are prepared first
./scripts/prepare-omni-iso.sh <site-code>

# Verify ISO references in tfvars
grep omni_iso terraform/<platform>/terraform.tfvars.<site-code>
```

**Need to change node count?**
```bash
# Use --force to update existing cluster
./scripts/new-cluster.sh <site> <cluster> --workers <new-count> --force

# Recalculate VM requirements
./scripts/update-tfvars.sh <site>

# Apply Terraform changes
./scripts/provision-nodes.sh <site>
```

**Talos version mismatch errors?**
- All nodes in a cluster must use the same Talos version
- The cluster's Talos version must match the ISO version
- Regenerate ISOs if Talos version changed: `./scripts/prepare-omni-iso.sh <site>`
- Update tfvars: `./scripts/update-tfvars.sh <site>`

## Documentation

- [docs/WORKFLOW.md](docs/WORKFLOW.md) - Complete end-to-end deployment workflow
- [docs/SCALING-CLUSTERS.md](docs/SCALING-CLUSTERS.md) - Scaling operations and best practices
- [docs/MACHINE-LABELING.md](docs/MACHINE-LABELING.md) - Machine labeling system details
- [docs/QUICKSTART.md](docs/QUICKSTART.md) - Quick start guide
- [docs/SITE-METADATA.md](docs/SITE-METADATA.md) - Site metadata details
- [scripts/README.md](scripts/README.md) - Script documentation

## Requirements

- **omnictl** - Omni CLI (>= 0.30.0)
- **terraform** - Infrastructure as Code (>= 1.5)
- **kubectl** - Kubernetes CLI
- **Proxmox** or **vSphere** - Hypervisor platform
- **Omni account** - With service account credentials

## License

MIT
