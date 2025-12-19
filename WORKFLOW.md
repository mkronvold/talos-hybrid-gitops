# Hybrid GitOps Workflow Guide

## Complete End-to-End Example

This document shows the complete workflow from empty infrastructure to running applications.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│  Git Repository (talos-hybrid-gitops)                       │
│                                                              │
│  terraform/          clusters/omni/      kubernetes/        │
│  ├── vsphere/        ├── prod.yaml       ├── infrastructure/│
│  └── proxmox/        └── dev.yaml        └── apps/          │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    Terraform            Omni CLI              Flux CD
    ─────────            ────────              ───────
    Provisions           Configures            Deploys
    VMs on               Talos                 Kubernetes
    vSphere/Proxmox      clusters              applications
         │                    │                    │
         ▼                    ▼                    ▼
    ┌─────────┐         ┌─────────┐         ┌─────────┐
    │   VMs   │ ──────▶ │ Talos   │ ──────▶ │  Apps   │
    │ Running │         │Clusters │         │ Running │
    └─────────┘         └─────────┘         └─────────┘
```

## Real-World Workflows

### Scenario A: Deploy Production Cluster on vSphere

#### 1. Initial Setup (One-time)

```bash
# Clone repository
git clone https://github.com/mkronvold/talos-hybrid-gitops.git
cd talos-hybrid-gitops

# Install tools (macOS/Linux with Homebrew)
brew install siderolabs/tap/sidero-tools  # Installs omnictl, talosctl, kubectl
brew install terraform fluxcd/tap/flux

# OR use the automated script
./scripts/install-dependencies.sh

# Get Omni service account credentials
# Visit your Omni instance → Settings → Service Accounts → Create
# Download the omni.sh script and add to ~/.bashrc or source it
source ~/omni.sh

# Upload Talos OVA to vSphere
# Download from: https://github.com/siderolabs/talos/releases/v1.9.5/talos-amd64.ova
# Upload to vSphere as template named "talos-v1.9.5"
```

#### 2. Configure Terraform

```bash
cd terraform/vsphere
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
cat > terraform.tfvars << EOF
vsphere_server     = "vcenter.example.com"
vsphere_user       = "administrator@vsphere.local"
vsphere_password   = "YourPassword"
vsphere_datacenter = "Datacenter"
vsphere_datastore  = "datastore1"
vsphere_cluster    = "Cluster1"
vsphere_network    = "VM Network"

cluster_name    = "prod-vsphere"
node_count      = 6  # 3 control + 3 workers
node_cpu        = 4
node_memory     = 8192
node_disk_size  = 100
EOF
```

#### 3. Deploy Infrastructure (Terraform)

```bash
# Initialize and plan
terraform init
terraform plan -out=tfplan

# Review plan output - should show 6 VMs to be created
# ...
# Plan: 6 to add, 0 to change, 0 to destroy.

# Apply
terraform apply tfplan

# Output shows:
# vm_names = [
#   "prod-vsphere-node-1",
#   "prod-vsphere-node-2",
#   ...
# ]

# VMs are now booting from Talos ISO
```

#### 4. Wait for Machine Registration

```bash
# VMs boot and automatically register with Omni
# This takes 2-5 minutes

# Check registered machines
omnictl get machines

# Expected output:
# NAMESPACE   NAME                                      CONNECTED
# default     machine-abc123...                         true
# default     machine-def456...                         true
# ...

# Machines show as "Available" in Omni UI
```

#### 5. Configure Cluster (Omni)

```bash
cd ../../clusters/omni

# Review cluster configuration
cat prod-vsphere.yaml
# Shows: 3 control planes + 3 workers, k8s v1.29.0

# Apply cluster config
omnictl apply -f prod-vsphere.yaml

# Omni allocates machines and forms cluster
# This takes 5-10 minutes

# Watch progress
omnictl get cluster prod-vsphere -w

# Expected output progresses through:
# PHASE: Provisioning → Scaling → Running
```

#### 6. Access Cluster

```bash
# Download kubeconfig
omnictl kubeconfig prod-vsphere > kubeconfig.prod
export KUBECONFIG=$(pwd)/kubeconfig.prod

# Verify cluster
kubectl get nodes
# NAME                     STATUS   ROLES           AGE
# prod-vsphere-node-1      Ready    control-plane   5m
# prod-vsphere-node-2      Ready    control-plane   5m
# prod-vsphere-node-3      Ready    control-plane   5m
# prod-vsphere-node-4      Ready    <none>          4m
# prod-vsphere-node-5      Ready    <none>          4m
# prod-vsphere-node-6      Ready    <none>          4m

kubectl get pods -A
# All system pods running
```

#### 7. Bootstrap GitOps (Flux)

```bash
# Create GitHub personal access token
# https://github.com/settings/tokens → Generate new token
# Scopes: repo (full)

export GITHUB_TOKEN=ghp_xxxxxxxxxxxxx

# Bootstrap Flux
flux bootstrap github \
  --owner=mkronvold \
  --repository=talos-hybrid-gitops \
  --branch=main \
  --path=kubernetes/clusters/prod-vsphere \
  --personal

# Flux installs itself and starts watching Git
kubectl get pods -n flux-system
# NAME                                       READY   STATUS
# source-controller-xxx                      1/1     Running
# kustomize-controller-xxx                   1/1     Running
# helm-controller-xxx                        1/1     Running
# notification-controller-xxx                1/1     Running
```

#### 8. Deploy Applications

```bash
# Applications are defined in Git
cd ../../kubernetes/infrastructure

# Flux automatically deploys what's in Git
flux get kustomizations
# NAME            READY   MESSAGE
# infrastructure  True    Applied revision: main/abc123

# Check deployed resources
kubectl get helmreleases -A
# NAMESPACE       NAME            READY   STATUS
# ingress-nginx   ingress-nginx   True    Release reconciliation succeeded

kubectl get pods -n ingress-nginx
# Ingress controller running
```

---

### Scenario B: Deploy Development Cluster on Proxmox

#### 1. Initial Setup (One-time)

```bash
# Clone repository
git clone https://github.com/mkronvold/talos-hybrid-gitops.git
cd talos-hybrid-gitops

# Install tools (same as vSphere)
brew install siderolabs/tap/sidero-tools  # Installs omnictl, talosctl, kubectl
brew install terraform fluxcd/tap/flux

# OR use the automated script
./scripts/install-dependencies.sh

# Get Omni service account credentials
# Source the omni.sh script provided by Omni
source ~/omni.sh

# Get Omni Factory Image URL
# 1. Log into your Omni web interface
# 2. Navigate to: Settings → Download Installation Media
# 3. Select: nocloud format, amd64 architecture
# 4. Copy the URL ending in .raw.gz
# Example: https://factory.talos.dev/image/YOUR-ID/v1.11.5/nocloud-amd64.raw.gz
```

#### 2. Configure Terraform

```bash
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
cat > terraform.tfvars << EOF
proxmox_api_url      = "https://proxmox.example.com:8006/api2/json"
proxmox_api_token_id = "terraform@pam!mytoken"
proxmox_api_token    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

proxmox_node     = "pve"
proxmox_datastore = "local-lvm"
proxmox_bridge    = "vmbr0"

cluster_name    = "dev-proxmox"
node_count      = 4  # 1 control + 3 workers
node_cpu        = 2
node_memory     = 4096
node_disk_size  = 50

# IMPORTANT: Use Omni Factory image for automatic registration
talos_image_url = "https://factory.talos.dev/image/YOUR-IMAGE-ID/v1.11.5/nocloud-amd64.raw.gz"
EOF
```

**Why use Omni Factory images?**
- Standard Talos ISOs boot into maintenance mode and don't know about Omni
- Omni Factory images have your Omni credentials embedded
- VMs automatically register with Omni on first boot
- No manual configuration needed

#### 3. Deploy Infrastructure (Terraform)

```bash
# Initialize providers (downloads required providers and creates lock file)
terraform init

# Plan deployment
terraform plan -out=tfplan

# Review plan output - should show 4 VMs to be created
# ...
# Plan: 4 to add, 0 to change, 0 to destroy.

# Apply
terraform apply tfplan

# Output shows:
# vm_names = [
#   "dev-proxmox-node-1",
#   "dev-proxmox-node-2",
#   ...
# ]

# VMs are now booting from Talos ISO
```

#### 4. Wait for Machine Registration

```bash
# VMs boot and automatically register with Omni
# This takes 2-5 minutes

# Check registered machines
omnictl get machines

# Expected output:
# NAMESPACE   NAME                                      CONNECTED
# default     machine-xyz789...                         true
# default     machine-uvw012...                         true
# ...

# Machines show as "Available" in Omni UI
```

#### 5. Configure Cluster (Omni)

```bash
cd ../../clusters/omni

# Review cluster configuration
cat dev-proxmox.yaml
# Shows: 1 control plane + 3 workers, k8s v1.29.0

# Apply cluster config
omnictl apply -f dev-proxmox.yaml

# Omni allocates machines and forms cluster
# This takes 5-10 minutes

# Watch progress
omnictl get cluster dev-proxmox -w

# Expected output progresses through:
# PHASE: Provisioning → Scaling → Running
```

#### 6. Access Cluster

```bash
# Download kubeconfig
omnictl kubeconfig dev-proxmox > kubeconfig.dev
export KUBECONFIG=$(pwd)/kubeconfig.dev

# Verify cluster
kubectl get nodes
# NAME                     STATUS   ROLES           AGE
# dev-proxmox-node-1       Ready    control-plane   5m
# dev-proxmox-node-2       Ready    <none>          4m
# dev-proxmox-node-3       Ready    <none>          4m
# dev-proxmox-node-4       Ready    <none>          4m

kubectl get pods -A
# All system pods running
```

#### 7. Bootstrap GitOps (Flux)

```bash
# Use same GitHub token as vSphere
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxx

# Bootstrap Flux
flux bootstrap github \
  --owner=mkronvold \
  --repository=talos-hybrid-gitops \
  --branch=main \
  --path=kubernetes/clusters/dev-proxmox \
  --personal

# Flux installs itself and starts watching Git
kubectl get pods -n flux-system
# NAME                                       READY   STATUS
# source-controller-xxx                      1/1     Running
# kustomize-controller-xxx                   1/1     Running
# helm-controller-xxx                        1/1     Running
# notification-controller-xxx                1/1     Running
```

#### 8. Deploy Applications

```bash
# Applications are defined in Git
cd ../../kubernetes/infrastructure

# Flux automatically deploys what's in Git
flux get kustomizations
# NAME            READY   MESSAGE
# infrastructure  True    Applied revision: main/abc123

# Check deployed resources
kubectl get pods -n ingress-nginx
# Ingress controller running
```

---

## Day 2 Operations

### Day 2: Add Worker Nodes (vSphere)

```bash
# 1. Update Terraform
cd terraform/vsphere
vim terraform.tfvars
# Change: node_count = 8  (was 6)

# 2. Apply
terraform plan
terraform apply
# Creates 2 new VMs

# 3. Wait for registration
omnictl get machines
# 8 machines now visible

# 4. Update cluster config
cd ../../clusters/omni
vim prod-vsphere.yaml
# Under workers machineSet:
#   machineCount: 5  (was 3)

# 5. Apply
omnictl apply -f prod-vsphere.yaml

# 6. Verify
kubectl get nodes
# Now shows 8 nodes (3 control + 5 workers)
```

### Day 2: Add Worker Nodes (Proxmox)

```bash
# 1. Update Terraform
cd terraform/proxmox
vim terraform.tfvars
# Change: node_count = 6  (was 4)

# 2. Apply
terraform plan
terraform apply
# Creates 2 new VMs

# 3. Wait for registration
omnictl get machines
# 6 machines now visible

# 4. Update cluster config
cd ../../clusters/omni
vim dev-proxmox.yaml
# Under workers machineSet:
#   machineCount: 5  (was 3)

# 5. Apply
omnictl apply -f dev-proxmox.yaml

# 6. Verify
kubectl get nodes
# Now shows 6 nodes (1 control + 5 workers)
```

### Day 2: Upgrade Kubernetes

```bash
# 1. Update cluster config
vim clusters/omni/prod-vsphere.yaml
# Change: kubernetes.version: v1.30.0  (was v1.29.0)

# 2. Commit and push
git add clusters/omni/prod-vsphere.yaml
git commit -m "Upgrade to Kubernetes v1.30.0"
git push

# 3. Apply (or let CI/CD do it)
omnictl apply -f clusters/omni/prod-vsphere.yaml

# Omni performs rolling upgrade
# 4. Watch progress
kubectl get nodes -w
# Nodes drain, upgrade, rejoin one by one
```

### Day 2: Deploy New Application

```bash
# 1. Add application manifest
mkdir -p kubernetes/apps/myapp
cat > kubernetes/apps/myapp/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 2. Commit and push
git add kubernetes/apps/
git commit -m "Add myapp deployment"
git push

# 3. Flux auto-deploys
# Wait 1-2 minutes for Flux sync interval
kubectl get deployments
# NAME    READY   UP-TO-DATE   AVAILABLE
# myapp   3/3     3            3
```

## GitOps in Action

### What Happens When You Git Push?

```
Developer commits change
         │
         ▼
    GitHub repo updated
         │
         ├─────────────┬──────────────┐
         ▼             ▼              ▼
    Terraform     Omni Config    K8s Manifests
         │             │              │
         ▼             ▼              ▼
    GitHub Actions  GitHub Actions  Flux watches
    runs terraform  runs omnictl    Git repo
         │             │              │
         ▼             ▼              ▼
    VMs created    Clusters updated  Apps deployed
```

### Example: Full Stack Update

```bash
# Single commit updates all layers
git add terraform/vsphere/terraform.tfvars      # Add 2 VMs
git add clusters/omni/prod-vsphere.yaml         # Scale workers
git add kubernetes/apps/myapp/deployment.yaml   # Update app image
git commit -m "Scale cluster and update myapp"
git push

# CI/CD pipeline:
# 1. terraform apply → Creates 2 new VMs (5 min)
# 2. omnictl apply → Adds VMs to cluster (5 min)
# 3. Flux sync → Deploys new app version (1 min)
# Total: ~11 minutes, fully automated
```

## Key Benefits of Hybrid Approach

1. **Separation of Concerns**
   - Infrastructure team manages Terraform
   - Platform team manages Omni configs
   - App teams manage Kubernetes manifests

2. **Platform Independence**
   - Same cluster config works on vSphere, Proxmox, AWS
   - Just change Terraform, Omni config stays the same

3. **Progressive Deployment**
   - Can deploy infrastructure without clusters
   - Can test cluster configs without apps
   - Incremental rollout of changes

4. **Clear Ownership**
   - Terraform state = infrastructure
   - Omni = cluster configs
   - Git = application state

5. **Disaster Recovery**
   - Infrastructure: `terraform apply`
   - Clusters: `omnictl apply`
   - Apps: Automatic via Flux

## Common Patterns

### Multi-Cluster Deployment

```bash
# Single repo manages multiple clusters across platforms
# vSphere production cluster
cd terraform/vsphere
terraform apply -auto-approve
omnictl apply -f ../../clusters/omni/prod-vsphere.yaml

# Proxmox development cluster
cd ../proxmox
terraform apply -auto-approve
omnictl apply -f ../../clusters/omni/dev-proxmox.yaml
```

### Cross-Platform Environment Promotion

```bash
# Test in dev (Proxmox), promote to prod (vSphere)
# 1. Compare configurations
git diff clusters/omni/dev-proxmox.yaml clusters/omni/prod-vsphere.yaml

# 2. Test application in dev
export KUBECONFIG=kubeconfig.dev
kubectl apply -f kubernetes/apps/myapp/

# 3. After validation, deploy to prod
export KUBECONFIG=kubeconfig.prod
kubectl apply -f kubernetes/apps/myapp/

# 4. Or let Flux handle it via Git
git add kubernetes/apps/
git commit -m "Deploy myapp to prod"
git push
```

### Platform Migration (Proxmox to vSphere)

```bash
# Scenario: Move workload from Proxmox dev to vSphere prod

# 1. Backup application state from Proxmox
export KUBECONFIG=kubeconfig.dev
kubectl get all -n myapp -o yaml > myapp-backup.yaml

# 2. Create vSphere cluster (if not exists)
cd terraform/vsphere
terraform apply
omnictl apply -f ../../clusters/omni/prod-vsphere.yaml

# 3. Restore to vSphere cluster
export KUBECONFIG=kubeconfig.prod
kubectl apply -f myapp-backup.yaml

# 4. Verify migration
kubectl get pods -n myapp
# All pods running on vSphere
```

### Cluster Templates

```bash
# Create new cluster from template
cp clusters/omni/prod-vsphere.yaml clusters/omni/prod-aws.yaml
# Edit: name, region, platform labels
omnictl apply -f clusters/omni/prod-aws.yaml
```

## Platform Comparison

### vSphere vs Proxmox Deployment

| Aspect | vSphere | Proxmox |
|--------|---------|---------|
| **Template** | Upload Talos OVA (one-time) | Boot from ISO URL (automatic) |
| **Terraform Provider** | `hashicorp/vsphere` | `bpg/proxmox` |
| **API Authentication** | Username + Password | API Token |
| **Typical Use Case** | Production, Enterprise | Development, Home Lab |
| **VM Provisioning Time** | ~3-5 minutes | ~2-4 minutes |
| **Storage** | Datastore names | local-lvm, NFS shares |
| **Networking** | Port Groups | Linux Bridges (vmbr0) |
| **Cost** | Licensed | Open Source |

### When to Use Each Platform

**Use vSphere when:**
- Production workloads requiring enterprise support
- High availability and vMotion needed
- Already invested in VMware ecosystem
- Compliance requirements for certified platforms

**Use Proxmox when:**
- Development and testing environments
- Cost-sensitive deployments
- Home lab or small business
- Open-source preference
- Learning and experimentation

### Hybrid Approach Example

```bash
# Development on Proxmox (cheap, fast iteration)
./scripts/new-site.sh la1d proxmox --location "LA Dev Lab"
./scripts/new-cluster.sh la1d api-test --control-planes 1 --workers 2
./scripts/deploy-infrastructure.sh la1d clusters/omni/la1d/api-test.yaml

# Production on vSphere (reliable, supported)
./scripts/new-site.sh ny1p vsphere --location "NY Prod DC"
./scripts/new-cluster.sh ny1p api --control-planes 3 --workers 5
./scripts/deploy-infrastructure.sh ny1p clusters/omni/ny1p/api.yaml

# Same application manifests work on both!
kubectl --context=dev apply -f kubernetes/apps/api/
kubectl --context=prod apply -f kubernetes/apps/api/
```

## Next Steps

1. Set up CI/CD pipelines (see `.github/workflows/`)
2. Add monitoring (Prometheus, Grafana)
3. Configure backups (Velero)
4. Set up disaster recovery procedures
5. Document runbooks for common operations
6. Test cross-platform disaster recovery
7. Implement cost tracking per platform
