# Complete Deployment Workflow

End-to-end guide: From site creation to running Kubernetes clusters.

## Overview

```
Create Site → Configure → Create Clusters → Prepare ISO → Deploy VMs → Apply Configs → Access
    ↓             ↓            ↓               ↓             ↓              ↓           ↓
  new-site   terraform    new-cluster   prepare-omni-  deploy-infra  apply-cluster  kubeconfig
    .sh       tfvars          .sh          iso.sh          .sh            .sh
```

## Complete Example: Deploy to Proxmox

### Step 1: Create Site Structure

Create a new site with all necessary scaffolding:

```bash
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"
```

**What this creates:**
```
clusters/omni/dk1d/
  ├── .site-metadata           # Site configuration
  └── README.md                # Site documentation

terraform/proxmox/
  └── terraform.tfvars.dk1d    # Infrastructure config template
```

**Site code format:** `<location><zone><environment>`
- `dk1d` = Denmark, Zone 1, Development
- `ny2p` = New York, Zone 2, Production
- `sf1s` = San Francisco, Zone 1, Staging

### Step 2: Configure Infrastructure

Edit the Terraform configuration with your Proxmox details:

```bash
vim terraform/proxmox/terraform.tfvars.dk1d
```

**Required settings:**

```hcl
# Proxmox connection
proxmox_endpoint = "https://proxmox.example.com:8006"
proxmox_api_token = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_insecure = true  # false if you have valid SSL

# Proxmox resources
proxmox_node      = "pve"           # Your Proxmox node name
proxmox_datastore = "local-lvm"     # Storage for VM disks
proxmox_bridge    = "vmbr0"         # Network bridge

# Cluster identification
cluster_name = "dk1d"

# Omni ISO (will be set automatically)
omni_iso_name = "talos-omni-dk1d-v1.11.5.iso"

# VM defaults (overridden by cluster configs)
vm_id_start    = 8000
node_count     = 4
node_cpu       = 2
node_memory    = 4096
node_disk_size = 50
```

**Getting your Proxmox API token:**

1. Log into Proxmox UI
2. Datacenter → Permissions → API Tokens
3. Add:
   - User: `root@pam`
   - Token ID: `terraform`
   - **Uncheck** "Privilege Separation"
4. Copy the full token string

### Step 3: Create Cluster Configurations

Create one or more cluster configurations for the site.

#### Option A: Interactive Mode (Recommended)

```bash
./scripts/new-cluster.sh dk1d baseline -i
```

**Interactive prompts:**
```
Available Size Classes:
  1) tiny     - ≤1 CPU, ≤4GB - Minimal nodes
  2) small    - ≤2 CPU, ≤8GB - Light workloads
  3) medium   - ≤4 CPU, ≤16GB - Standard workloads
  4) large    - ≤8 CPU, ≤32GB - Moderate workloads
  5) xlarge   - ≤16 CPU, ≤64GB - Heavy workloads
  6) huge     - Maximum capacity

Select size class (1-6) [2]: 2

Cluster Topology:
Control plane nodes [1]: 1
Worker nodes [3]: 3

Per-Node Resources:
CPU cores [2]: 2
Memory (MB) [4096]: 4096
Disk size (GB) [50]: 50

Software Versions:
Kubernetes version [v1.30.0]: v1.30.0
Talos version [v1.11.5]: v1.11.5
```

#### Option B: Command Line

```bash
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 3 \
  --size-class small \
  --cpu 2 \
  --memory 4096 \
  --disk 50 \
  --k8s-version v1.30.0 \
  --talos-version v1.11.5
```

**Result:**
- Creates: `clusters/omni/dk1d/cluster-baseline.yaml`
- Updates: `terraform/proxmox/terraform.tfvars.dk1d` with node requirements

#### Create Multiple Clusters

```bash
# Small baseline cluster for infrastructure
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 2 \
  --size-class small

# Medium web application cluster
./scripts/new-cluster.sh dk1d web \
  --control-planes 3 \
  --workers 5 \
  --size-class medium

# Large data processing cluster
./scripts/new-cluster.sh dk1d data \
  --control-planes 3 \
  --workers 10 \
  --size-class large
```

**Important:** Terraform will automatically calculate total requirements:
- `node_count` = sum of all cluster nodes (3 + 8 + 13 = 24)
- `node_cpu` = max CPU across all clusters (4 for medium)
- `node_memory` = max memory across all clusters (16384 for large)

### Step 4: Prepare Omni ISO

Generate an ISO with your Omni credentials and site labels baked in.

#### Basic (Recommended)

```bash
./scripts/prepare-omni-iso.sh dk1d
```

**What happens:**
1. Contacts your Omni server
2. Generates ISO for Talos v1.11.5 (default)
3. Includes site labels: `site=dk1d`, `platform=proxmox`
4. Adds `qemu-guest-agent` automatically (for Proxmox)
5. Downloads to: `/tmp/omni-isos/talos-omni-dk1d-v1.11.5.iso`
6. Uploads to Proxmox: `/var/lib/vz/template/iso/`
7. Saves reference: `terraform/proxmox/.omni-iso-dk1d`

#### Specific Talos Version

```bash
# For Talos 1.10.0
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.10.0

# For Talos 1.12.0
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.12.0
```

**Result:** Different ISOs with version in filename:
- `talos-omni-dk1d-v1.10.0.iso`
- `talos-omni-dk1d-v1.11.5.iso`
- `talos-omni-dk1d-v1.12.0.iso`

All can coexist in Proxmox. The latest one is used by default.

#### With Additional Extensions

```bash
# Add Intel microcode updates
./scripts/prepare-omni-iso.sh dk1d --extensions intel-ucode

# Multiple extensions
./scripts/prepare-omni-iso.sh dk1d \
  --extensions intel-ucode \
  --extensions iscsi-tools

# Specific version + extensions
./scripts/prepare-omni-iso.sh dk1d \
  --talos-version 1.10.0 \
  --extensions intel-ucode
```

#### With SecureBoot

```bash
./scripts/prepare-omni-iso.sh dk1d --secureboot
```

#### ISO Options Summary

```bash
./scripts/prepare-omni-iso.sh <site-code> [options]

Options:
  --talos-version <ver>    Talos version (default: 1.11.5)
  --extensions <ext>       Add extension (repeatable)
  --secureboot             Enable SecureBoot
  --no-upload              Download only, don't upload to Proxmox
  --output-dir <dir>       Local directory (default: /tmp/omni-isos)
```

### Step 5: Deploy Infrastructure

Deploy VMs using Terraform.

#### All-in-One (Recommended)

```bash
# Prepare ISO and deploy in one command
./scripts/deploy-infrastructure.sh dk1d --prepare-iso
```

#### Two-Step

```bash
# If you already prepared the ISO
./scripts/deploy-infrastructure.sh dk1d
```

**What happens:**

1. **Updates terraform.tfvars.dk1d**
   - Calculates total nodes across all clusters
   - Sets max CPU/memory/disk from cluster configs

2. **Runs Terraform**
   ```bash
   cd terraform/proxmox
   terraform init
   terraform workspace select dk1d
   terraform plan -var-file=terraform.tfvars.dk1d
   terraform apply
   ```

3. **Creates VMs**
   - Names: `dk1d-node-1`, `dk1d-node-2`, etc.
   - Boots from Omni ISO
   - VMs start automatically

4. **Waits for Registration**
   - VMs boot (2-5 minutes)
   - Connect to Omni automatically
   - Appear with labels: `site=dk1d`, `platform=proxmox`

**Check VM status:**
```bash
# On Proxmox
qm list | grep dk1d

# In Omni
omnictl get machines --labels site=dk1d
```

### Step 6: Apply Cluster Configurations

Apply each cluster configuration to Omni.

```bash
# Apply baseline cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml

# Apply web cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-web.yaml

# Apply data cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-data.yaml
```

**What happens:**
1. Validates YAML configuration
2. Applies to Omni via `omnictl apply`
3. Omni provisions the cluster:
   - Creates machine classes
   - Creates cluster resource
   - Creates machine sets
   - Assigns machines from the pool
   - Bootstraps Kubernetes
   - Configures Talos

**Check cluster status:**
```bash
# List clusters
omnictl get clusters

# Check specific cluster
omnictl get cluster dk1d-baseline -o yaml

# Watch cluster bootstrap
omnictl get machines --cluster dk1d-baseline
```

### Step 7: Access Clusters

Get kubeconfig and access your clusters.

```bash
# Get kubeconfig for baseline cluster
omnictl kubeconfig dk1d-baseline > kubeconfig-baseline

# Use it
export KUBECONFIG=$PWD/kubeconfig-baseline
kubectl get nodes
kubectl get pods -A

# Get kubeconfigs for other clusters
omnictl kubeconfig dk1d-web > kubeconfig-web
omnictl kubeconfig dk1d-data > kubeconfig-data
```

**Verify cluster health:**
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl cluster-info
```

## Version Selection Strategy

### Matching Versions

For best results, match versions across:
1. **Omni ISO** (Talos version)
2. **Cluster YAML** (Kubernetes + Talos version)

#### Example: Deploy with Talos 1.10.0

```bash
# 1. Create cluster config with specific version
./scripts/new-cluster.sh dk1d test \
  --talos-version v1.10.0 \
  --k8s-version v1.29.0

# 2. Prepare ISO with matching version
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.10.0

# 3. Deploy
./scripts/deploy-infrastructure.sh dk1d
./scripts/apply-cluster.sh clusters/omni/dk1d/test.yaml
```

### Multiple Versions in Same Site

You can have different clusters running different versions:

```bash
# Baseline on latest stable
./scripts/new-cluster.sh dk1d baseline --talos-version v1.11.5
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.11.5

# Test on newer version
./scripts/new-cluster.sh dk1d test --talos-version v1.12.0
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.12.0
```

**Deploy with specific ISO:**
```bash
# Deploy with default (latest prepared)
./scripts/deploy-infrastructure.sh dk1d

# Or manually specify ISO version in Terraform
cd terraform/proxmox
terraform apply \
  -var-file=terraform.tfvars.dk1d \
  -var="omni_iso_name=talos-omni-dk1d-v1.12.0.iso"
```

## Common Workflows

### Workflow 1: Quick Single Cluster

```bash
# Complete deployment in 5 commands
./scripts/new-site.sh dk1d proxmox --location "Denmark Dev"
vim terraform/proxmox/terraform.tfvars.dk1d
./scripts/new-cluster.sh dk1d baseline -i
./scripts/deploy-infrastructure.sh dk1d --prepare-iso
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

### Workflow 2: Multiple Clusters, Different Sizes

```bash
# Create site
./scripts/new-site.sh ny1p proxmox --location "New York Prod"
vim terraform/proxmox/terraform.tfvars.ny1p

# Create clusters
./scripts/new-cluster.sh ny1p infra --size-class small
./scripts/new-cluster.sh ny1p web --size-class medium  
./scripts/new-cluster.sh ny1p db --size-class large

# Deploy once (all VMs)
./scripts/deploy-infrastructure.sh ny1p --prepare-iso

# Apply each cluster
./scripts/apply-cluster.sh clusters/omni/ny1p/infra.yaml
./scripts/apply-cluster.sh clusters/omni/ny1p/cluster-web.yaml
./scripts/apply-cluster.sh clusters/omni/ny1p/db.yaml
```

### Workflow 3: Testing New Version

```bash
# Create test cluster with new version
./scripts/new-cluster.sh dk1d test \
  --talos-version v1.12.0 \
  --k8s-version v1.31.0 \
  --size-class small

# Prepare ISO for new version
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.12.0

# Deploy VMs (if needed) or reuse existing
./scripts/deploy-infrastructure.sh dk1d

# Apply test cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/test.yaml

# Test...

# If good, update other clusters
vim clusters/omni/dk1d/cluster-baseline.yaml  # Update versions
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

### Workflow 4: Add Capacity to Existing Site

```bash
# Create new cluster
./scripts/new-cluster.sh dk1d additional \
  --control-planes 3 \
  --workers 10 \
  --size-class large

# This updates terraform.tfvars.dk1d with new totals

# Deploy additional VMs
cd terraform/proxmox
terraform plan -var-file=terraform.tfvars.dk1d
terraform apply -var-file=terraform.tfvars.dk1d

# Wait for new VMs to register with Omni
omnictl get machines --labels site=dk1d

# Apply new cluster
./scripts/apply-cluster.sh clusters/omni/dk1d/additional.yaml
```

## Troubleshooting

### Issue: VMs Not Registering with Omni

**Symptoms:**
```bash
omnictl get machines --labels site=dk1d
# No machines shown after 5+ minutes
```

**Debug:**
1. Check VM console in Proxmox
2. Look for "Connected to Omni" or error messages
3. Verify network connectivity to Omni endpoint
4. Check ISO was prepared correctly

**Solutions:**
```bash
# Re-prepare ISO
./scripts/prepare-omni-iso.sh dk1d

# Check Omni endpoint
echo $OMNI_ENDPOINT

# Manually check machine status
omnictl get machines -o wide
```

### Issue: Terraform Can't Find ISO

**Error:**
```
Error: Omni ISO reference file not found
```

**Solution:**
```bash
# Prepare the ISO first
./scripts/prepare-omni-iso.sh dk1d

# Verify reference file exists
cat terraform/proxmox/.omni-iso-dk1d
```

### Issue: Wrong Number of Nodes

**Symptoms:**
Terraform creates wrong number of VMs.

**Cause:**
Multiple clusters, terraform.tfvars not updated.

**Solution:**
```bash
# The scripts do this automatically, but if needed:
./scripts/new-cluster.sh dk1d cluster-name ...
# This updates terraform.tfvars.dk1d automatically

# Or manually recalculate
cd terraform/proxmox
grep -r "machinecount" ../../clusters/omni/dk1d/*.yaml
```

### Issue: Version Mismatch

**Symptoms:**
Cluster config specifies v1.11.5 but ISO is v1.10.0.

**Solution:**
```bash
# Prepare ISO matching cluster version
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.11.5

# Or update cluster config
vim clusters/omni/dk1d/cluster-baseline.yaml
# Change talosversion: 1.10.5
```

## Tips and Best Practices

### 1. Version Management

- **Match versions**: Keep Talos version in ISO and cluster YAML aligned
- **Test first**: Create small test cluster with new versions before upgrading production
- **Document versions**: Note which ISO version each cluster uses

### 2. Site Organization

- **One site per location/environment**: `ny1p`, `ny1d`, `ny1s`
- **Multiple clusters per site**: Different workload sizes/purposes
- **Consistent naming**: `<location><zone><env>-<purpose>`

### 3. Resource Planning

- **Over-provision slightly**: Add 10-20% more VMs than minimum needed
- **Use size classes**: Start small, scale up as needed
- **Plan for growth**: Leave VM ID ranges available

### 4. Deployment Order

1. Create all cluster configs first
2. Prepare ISO once
3. Deploy infrastructure once (gets all VMs needed)
4. Apply cluster configs one by one

### 5. Change Management

- **Git workflow**: Commit cluster YAML changes
- **Test changes**: Use test clusters for validation
- **Incremental updates**: Change one thing at a time

## Quick Reference

```bash
# Create site
./scripts/new-site.sh <site> <platform> --location "<name>"

# Create cluster (interactive)
./scripts/new-cluster.sh <site> <cluster> -i

# Create cluster (CLI)
./scripts/new-cluster.sh <site> <cluster> \
  --control-planes N --workers M --size-class <class>

# Prepare ISO
./scripts/prepare-omni-iso.sh <site> [--talos-version X.Y.Z]

# Deploy infrastructure
./scripts/deploy-infrastructure.sh <site> [--prepare-iso]

# Apply cluster
./scripts/apply-cluster.sh clusters/omni/<site>/<cluster>.yaml

# Get kubeconfig
omnictl kubeconfig <site>-<cluster> > kubeconfig
```

## Next Steps

- [Main README](../README.md) - Overview and features
- [Quick Start](QUICKSTART.md) - 10-minute deployment
- [Proxmox README](../terraform/proxmox/README.md) - Proxmox specifics
- [Scripts README](../scripts/README.md) - Script documentation
