# Talos Hybrid GitOps Architecture

This repository demonstrates a hybrid approach to managing Talos clusters using:
- **Terraform** for infrastructure provisioning (VMs on vSphere/Proxmox)
- **Omni CLI** for cluster orchestration and configuration
- **Flux CD** for Kubernetes application deployment

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Git Repository                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Terraform   │  │  Omni YAML   │  │ Kubernetes   │      │
│  │   (VMs)      │  │  (Clusters)  │  │   (Apps)     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
         ↓                    ↓                    ↓
    ┌─────────┐         ┌─────────┐         ┌─────────┐
    │vSphere/ │         │  Omni   │         │  Flux   │
    │Proxmox  │ →→→→→→→ │ Control │ →→→→→→→ │   CD    │
    │   VMs   │         │  Plane  │         │         │
    └─────────┘         └─────────┘         └─────────┘
```

## Directory Structure

```
.
├── terraform/                 # Infrastructure layer
│   ├── vsphere/              # vSphere VM provisioning
│   ├── proxmox/              # Proxmox VM provisioning
│   └── modules/              # Reusable Terraform modules
├── clusters/                  # Cluster orchestration layer
│   └── omni/                 # Omni cluster definitions
│       ├── prod-vsphere.yaml
│       ├── dev-proxmox.yaml
│       └── patches/          # Talos machine patches
├── kubernetes/               # Application layer
│   ├── infrastructure/       # Core infrastructure (ingress, storage, etc)
│   └── apps/                # Applications
├── scripts/                  # Automation scripts
└── .github/workflows/        # CI/CD pipelines
```

## Workflow

### 1. Provision Infrastructure (Terraform)
```bash
cd terraform/vsphere
terraform init
terraform plan
terraform apply
```

### 2. Configure Clusters (Omni CLI)
```bash
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-api-key>
omnictl apply -f clusters/omni/prod-vsphere.yaml
```

### 3. Bootstrap GitOps (Flux)
```bash
flux bootstrap github \
  --owner=mkronvold \
  --repository=talos-hybrid-gitops \
  --path=kubernetes/clusters/prod
```

## Getting Started

### Quick Install

**With Homebrew (macOS/Linux):**
```bash
# Install all Talos/Omni tools with one command
brew install siderolabs/tap/sidero-tools  # Installs omnictl, talosctl, kubectl

# Additional tools
brew install terraform fluxcd/tap/flux
```

**Or use the automated script:**
```bash
./scripts/install-dependencies.sh
```

### Deployment Steps

1. **Create a site:**
   ```bash
   ./scripts/new-site.sh <site-code> <platform> --location "<location>"
   ```

2. **Configure Terraform variables:**
   ```bash
   vim terraform/<platform>/terraform.tfvars.<site-code>
   ```

3. **Set Omni credentials:**
   ```bash
   export OMNI_ENDPOINT=https://omni.siderolabs.com
   export OMNI_API_KEY=<your-api-key>
   ```

4. **Deploy infrastructure:**
   ```bash
   ./scripts/deploy-infrastructure.sh <site-code> clusters/omni/<site-code>/<cluster>.yaml
   ```

See [WORKFLOW.md](WORKFLOW.md) for complete examples and [scripts/README.md](scripts/README.md) for detailed script documentation.
