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
- `terraform/proxmox/terraform.tfvars.dk1d` - Infrastructure config

### 4. Configure Terraform

Edit `terraform/proxmox/terraform.tfvars.dk1d` with your Proxmox details:

```hcl
proxmox_endpoint = "https://proxmox.example.com:8006"
proxmox_api_token = "root@pam!terraform=xxx-xxx-xxx"
proxmox_node = "pve"
cluster_name = "dk1d"
```

### 5. Create a Cluster

```bash
# Interactive mode (recommended)
./scripts/new-cluster.sh dk1d baseline -i

# Or specify all options
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 3 \
  --cpu 2 \
  --memory 4096 \
  --size-class small
```

### 6. Deploy

```bash
# All-in-one: prepare ISO and deploy infrastructure
./scripts/deploy-infrastructure.sh dk1d --prepare-iso

# Or two-step:
./scripts/prepare-omni-iso.sh dk1d
./scripts/deploy-infrastructure.sh dk1d
```

**What happens:**
1. ISO is generated with your Omni credentials + site labels
2. ISO uploaded to Proxmox storage  
3. VMs created and booted from ISO
4. Machines auto-register with Omni (labeled: `site=dk1d`, `platform=proxmox`)
5. Cluster configuration applied via Omni

### 7. Apply Cluster Config

```bash
./scripts/apply-cluster.sh clusters/omni/dk1d/baseline.yaml
```

### 8. Access Your Cluster

```bash
omnictl kubeconfig dk1d-baseline > kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Git Repository                                      │
│  ├── terraform/        Infrastructure as Code       │
│  ├── clusters/omni/    Cluster definitions          │
│  └── scripts/          Automation                   │
└─────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
    Terraform            omnictl
    ─────────            ───────
    Provisions           Configures
    VMs with             Talos
    Omni ISOs            clusters
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

Clusters support predefined size classes for easy node sizing:

- **tiny** - 1 CPU, 4GB - Testing/edge
- **small** - 2 CPU, 8GB - Light workloads
- **medium** - 4 CPU, 16GB - Standard workloads
- **large** - 8 CPU, 32GB - Heavy workloads
- **xlarge** - 16 CPU, 64GB - Very heavy workloads
- **huge** - >16 CPU or >64GB - Maximum capacity

### 🤖 Platform-Specific Guest Agents

ISOs automatically include:
- **Proxmox**: `qemu-guest-agent` (VM monitoring and management)
- **vSphere**: `vmware-guest-agent` (VMware Tools functionality)

### 📝 Interactive Cluster Creation

```bash
./scripts/new-cluster.sh dk1d web -i
```

Prompts for:
- Size class selection (with descriptions)
- Number of control planes and workers
- CPU, memory, and disk per node
- Kubernetes and Talos versions

Detects existing configurations and offers to reuse values.

## Directory Structure

```
.
├── clusters/
│   ├── omni/                   # Cluster configurations by site
│   │   └── dk1d/              # Site: Denmark Zone 1 Dev
│   │       ├── .site-metadata # Site configuration
│   │       ├── README.md      # Site documentation
│   │       └── baseline.yaml  # Cluster definition
│   └── size_classes.csv       # Node size class definitions
├── terraform/
│   ├── proxmox/               # Proxmox VM provisioning
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.dk1d
│   └── vsphere/               # vSphere VM provisioning
│       └── ...
├── scripts/
│   ├── new-site.sh            # Create new site
│   ├── new-cluster.sh         # Create cluster config
│   ├── prepare-omni-iso.sh    # Generate Omni ISO
│   ├── deploy-infrastructure.sh # Deploy VMs
│   └── apply-cluster.sh       # Apply cluster config
└── docs/
    └── ...
```

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `new-site.sh` | Create site structure and configs |
| `new-cluster.sh` | Generate cluster YAML (interactive or CLI) |
| `prepare-omni-iso.sh` | Download Omni ISO with site labels |
| `deploy-infrastructure.sh` | Deploy VMs with Terraform |
| `apply-cluster.sh` | Apply cluster config to Omni |
| `install-dependencies.sh` | Install required tools |

## Common Workflows

### Create Multiple Clusters in One Site

```bash
# Create baseline cluster (small)
./scripts/new-cluster.sh dk1d baseline -i

# Create web cluster (medium)
./scripts/new-cluster.sh dk1d web --size-class medium

# Create data cluster (large)  
./scripts/new-cluster.sh dk1d data --size-class large

# Deploy infrastructure (once for all clusters)
./scripts/deploy-infrastructure.sh dk1d --prepare-iso

# Apply each cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/baseline.yaml
./scripts/apply-cluster.sh clusters/omni/dk1d/web.yaml
./scripts/apply-cluster.sh clusters/omni/dk1d/data.yaml
```

### Update Existing Cluster

```bash
# Edit cluster YAML
vim clusters/omni/dk1d/baseline.yaml

# Apply changes
./scripts/apply-cluster.sh clusters/omni/dk1d/baseline.yaml
```

### Recreate Cluster with Different Settings

```bash
# Interactive mode automatically backs up existing config
./scripts/new-cluster.sh dk1d baseline -i

# Redeploy
./scripts/apply-cluster.sh clusters/omni/dk1d/baseline.yaml
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

### Different Talos Versions

```bash
# Download specific version
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.10.0

# Use in cluster
./scripts/new-cluster.sh dk1d test --talos-version 1.10.0
```

### SecureBoot Support

```bash
./scripts/prepare-omni-iso.sh dk1d --secureboot
```

## Troubleshooting

**VMs not registering with Omni?**
- Wait 2-5 minutes after boot
- Check VM console for boot errors
- Verify network connectivity to Omni endpoint
- Check Omni UI: Unassigned Machines

**Terraform errors about missing ISO?**
```bash
# Ensure ISO is prepared first
./scripts/prepare-omni-iso.sh <site-code>

# Verify ISO reference file exists
cat terraform/proxmox/.omni-iso-<site-code>
```

**Interactive mode not prompting?**
- Ensure running in an actual terminal (not piped)
- Try with explicit bash: `bash scripts/new-cluster.sh dk1d test -i`

## Documentation

- [docs/DEPLOYMENT-WORKFLOW.md](docs/DEPLOYMENT-WORKFLOW.md) - Complete deployment workflow
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
