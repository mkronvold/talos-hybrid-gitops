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

1. Set up credentials in `.env` or CI/CD secrets
2. Provision VMs with Terraform
3. Apply cluster configurations with Omni
4. Bootstrap Flux for application deployment

See individual directories for detailed documentation.
