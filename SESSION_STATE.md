# Session State - 2025-12-14

## What Was Accomplished

Created a complete **Hybrid GitOps approach** for Talos Kubernetes cluster management supporting both vSphere 8 and Proxmox hypervisors.

## Repository Details

- **Location**: `~/src/talos-hybrid-gitops`
- **GitHub**: https://github.com/mkronvold/talos-hybrid-gitops
- **Branch**: main
- **Commits**: 2 commits pushed successfully

## Architecture Overview

The hybrid approach uses three distinct layers:

1. **Terraform** - Provisions VMs on vSphere/Proxmox
2. **Omni CLI** - Configures Talos clusters from available machines
3. **Flux CD** - Deploys Kubernetes applications

## Repository Structure

```
~/src/talos-hybrid-gitops/
├── terraform/
│   ├── vsphere/              # vSphere VM provisioning
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.example
│   └── proxmox/              # Proxmox VM provisioning
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars.example
├── clusters/omni/
│   ├── prod-vsphere.yaml     # Production cluster (6 nodes)
│   └── dev-proxmox.yaml      # Development cluster (3 nodes)
├── kubernetes/
│   └── infrastructure/
│       ├── kustomization.yaml
│       └── ingress-nginx.yaml
├── scripts/
│   └── deploy-infrastructure.sh  # Automated deployment script
├── .github/workflows/
│   ├── terraform-apply.yaml  # CI/CD for Terraform
│   └── omni-apply.yaml       # CI/CD for Omni configs
├── docs/
│   └── QUICKSTART.md
├── README.md                 # Main documentation
└── WORKFLOW.md               # Complete workflow examples
```

## Git Status

```bash
Current branch: main
Remote: git@github.com:mkronvold/talos-hybrid-gitops.git
All changes committed and pushed
```

## Next Steps to Continue Work

### From Another Host

1. **Clone the repository**:
   ```bash
   git clone git@github.com:mkronvold/talos-hybrid-gitops.git
   cd talos-hybrid-gitops
   ```

2. **Install required tools**:
   ```bash
   # Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # Omni CLI
   curl -Lo omnictl https://github.com/siderolabs/omni/releases/latest/download/omnictl-linux-amd64
   chmod +x omnictl
   sudo mv omnictl /usr/local/bin/
   
   # kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   
   # Flux
   curl -s https://fluxcd.io/install.sh | sudo bash
   ```

3. **Set up credentials**:
   ```bash
   # Omni credentials
   export OMNI_ENDPOINT=https://omni.siderolabs.com
   export OMNI_API_KEY=<your-api-key>
   
   # vSphere credentials (for Terraform)
   cd terraform/vsphere
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your vSphere details
   
   # Proxmox credentials (for Terraform)
   cd ../proxmox
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your Proxmox details
   ```

## Configuration Requirements

### Before Deploying

#### For vSphere:
- Upload Talos OVA template (v1.9.5) from https://github.com/siderolabs/talos/releases
- Name the template: `talos-v1.9.5`
- Configure `terraform/vsphere/terraform.tfvars` with:
  - vSphere server, credentials
  - Datacenter, cluster, datastore, network names
  - Node specifications (CPU, memory, disk)

#### For Proxmox:
- Ensure Proxmox API is accessible
- Configure `terraform/proxmox/terraform.tfvars` with:
  - Proxmox endpoint, credentials
  - Node name, datastore, bridge
  - Node specifications

#### For Omni:
- Sign up at https://omni.siderolabs.com
- Create API key in Settings → API Keys
- Free tier: 10 machines, 1 cluster
- Paid: $10/machine/month

## Deployment Workflow

### Quick Deploy (Automated)
```bash
cd ~/src/talos-hybrid-gitops
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-key>

# Deploy vSphere cluster
./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml

# OR deploy Proxmox cluster
./scripts/deploy-infrastructure.sh proxmox clusters/omni/dev-proxmox.yaml
```

### Manual Deploy (Step-by-step)
```bash
# 1. Provision VMs
cd terraform/vsphere  # or proxmox
terraform init
terraform plan
terraform apply

# 2. Wait for machines to register with Omni (2-5 minutes)
omnictl get machines

# 3. Apply cluster configuration
cd ../../
omnictl apply -f clusters/omni/prod-vsphere.yaml

# 4. Get kubeconfig
omnictl kubeconfig prod-vsphere > kubeconfig
export KUBECONFIG=./kubeconfig

# 5. Bootstrap Flux
flux bootstrap github \
  --owner=mkronvold \
  --repository=talos-hybrid-gitops \
  --branch=main \
  --path=kubernetes/clusters/prod-vsphere \
  --personal
```

## Key Features Implemented

- ✅ Multi-platform support (vSphere + Proxmox)
- ✅ Infrastructure as Code (Terraform)
- ✅ Declarative cluster management (Omni)
- ✅ GitOps-ready (Flux CD)
- ✅ CI/CD workflows (GitHub Actions)
- ✅ Automated deployment scripts
- ✅ Complete documentation
- ✅ Example configurations for prod and dev

## Important Files

- **README.md** - Overview and architecture
- **WORKFLOW.md** - Complete end-to-end examples with day-2 operations
- **docs/QUICKSTART.md** - Quick start guide
- **scripts/deploy-infrastructure.sh** - Automated deployment
- **terraform/*/terraform.tfvars.example** - Configuration templates

## Resources & Links

- Talos Documentation: https://www.talos.dev/
- Omni Platform: https://omni.siderolabs.com
- Omni Documentation: https://omni.siderolabs.com/docs
- Flux CD: https://fluxcd.io/
- Terraform vSphere Provider: https://registry.terraform.io/providers/hashicorp/vsphere/latest
- Terraform Proxmox Provider: https://registry.terraform.io/providers/bpg/proxmox/latest

## Environment Information

- **Host**: Linux
- **Working Directory**: /home/mkronvold/src/talos-hybrid-gitops
- **Git Remote**: SSH (git@github.com:mkronvold/talos-hybrid-gitops.git)
- **SSH Key**: ~/.ssh/id_rsa

## Notes

- All sensitive files are in .gitignore (*.tfvars, kubeconfig, secrets)
- CI/CD workflows need secrets configured in GitHub:
  - VSPHERE_USER, VSPHERE_PASSWORD
  - PROXMOX_USERNAME, PROXMOX_PASSWORD
  - OMNI_ENDPOINT, OMNI_API_KEY
- Repository is public by default
- Talos version: v1.9.5
- Kubernetes version: v1.29.0 (configurable in Omni YAML)

## Session Completed

Date: 2025-12-14T01:11:10.156Z
Status: All changes committed and pushed to GitHub
Ready to continue from any host with Git access
