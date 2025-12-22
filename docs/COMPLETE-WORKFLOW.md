# Complete Deployment Workflow

This document describes the complete end-to-end workflow for deploying Talos Kubernetes clusters using this platform.

## Overview

The deployment process consists of 8 distinct phases:

1. **Site Creation** - Define site and platform
2. **Cluster Definition** - Define cluster(s) with resources
3. **ISO Preparation** - Generate version-specific Omni ISOs
4. **Variables Update** - Calculate Terraform variables
5. **Node Provisioning** - Deploy VMs with Terraform
6. **Cluster Application** - Apply cluster configs to Omni
7. **Machine Registration** - Wait for machines to join clusters
8. **Kubeconfig Download** - Access deployed clusters

## Prerequisites

### Tools Required
```bash
# Install via Homebrew (recommended)
brew install siderolabs/tap/sidero-tools  # omnictl, talosctl, kubectl
brew install terraform jq

# OR install manually
./scripts/install-dependencies.sh
```

### Omni Credentials
```bash
# Set environment variables
export OMNI_ENDPOINT="https://yourcompany.omni.siderolabs.io"
export OMNI_SERVICE_ACCOUNT_KEY="your-service-account-key"

# Save to file for persistence
cat > ~/omni.sh << EOF
export OMNI_ENDPOINT="https://yourcompany.omni.siderolabs.io"
export OMNI_SERVICE_ACCOUNT_KEY="your-service-account-key"
EOF

source ~/omni.sh
```

### Proxmox Configuration
- Proxmox API token or username/password
- SSH access to Proxmox host
- Network bridge configured (vmbr0)
- Storage for VMs (e.g., local-lvm, zfs)
- Storage for ISOs (e.g., local)

## Complete Workflow

### Phase 1: Site Creation

Create a new site representing a physical location and platform.

```bash
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"
```

**What this does:**
- Creates `clusters/omni/dk1d/` directory
- Creates `clusters/omni/dk1d/site-dk1d.yaml` with platform metadata
- Creates `clusters/omni/dk1d/README.md` with site documentation

**Site code format:** `<location><zone><environment>`
- `dk` = Denmark
- `1` = Zone 1
- `d` = Development (or `p` = Production, `s` = Staging)

### Phase 2: Cluster Definition

Define one or more clusters for the site.

```bash
# Interactive mode (recommended for first cluster)
./scripts/new-cluster.sh dk1d baseline --interactive

# CLI mode with all parameters
./scripts/new-cluster.sh dk1d baseline \
  --size-class 4x8 \
  --control-planes 3 \
  --workers 5 \
  --talos-version 1.9.0 \
  --kubernetes-version 1.29.0

# Create additional clusters
./scripts/new-cluster.sh dk1d web --size-class 8x16 --control-planes 3 --workers 10
./scripts/new-cluster.sh dk1d data --size-class 16x32 --control-planes 3 --workers 5
```

**What this does:**
- Creates `clusters/omni/dk1d/cluster-<name>.yaml`
- Defines MachineClasses with site/platform/size-class filters
- Defines Cluster resource with versions
- Defines MachineSets for control-planes and workers

**Size class format:** `CPUxMEMORY`
- `2x4` = 2 CPU cores, 4GB RAM
- `4x8` = 4 CPU cores, 8GB RAM
- `8x16` = 8 CPU cores, 16GB RAM
- `16x32` = 16 CPU cores, 32GB RAM

### Phase 3: ISO Preparation

Generate Omni ISOs for each Talos version needed by your clusters.

```bash
# For Talos 1.9.0 (if any clusters use it)
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.9.0

# For Talos 1.8.0 (if any clusters use it)
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.8.0

# With additional extensions
./scripts/prepare-omni-iso.sh dk1d \
  --talos-version 1.9.0 \
  --extensions siderolabs/intel-ucode \
  --extensions siderolabs/iscsi-tools
```

**What this does:**
- Downloads ISO from Omni with pre-baked credentials
- Includes site labels: `site=dk1d`, `platform=proxmox`
- Includes platform-specific guest agent (qemu-guest-agent for Proxmox)
- Uploads ISO to Proxmox via SCP
- Updates `omni_iso_name` in terraform.tfvars automatically

**Note:** Run once per Talos version. If all clusters use same version, run once.

### Phase 4: Variables Update

Calculate Terraform variables from all cluster definitions.

```bash
./scripts/update-tfvars.sh dk1d
```

**What this does:**
- Scans all `cluster-*.yaml` files in site
- Groups by role (controlplane/worker) and resources
- Generates `vm_configs` in `terraform/proxmox/terraform.tfvars.dk1d`
- Creates backup of previous tfvars

**Example vm_configs generated:**
```hcl
vm_configs = [
  {
    count  = 3
    cpu    = 4
    memory = 8192
    disk   = 50
    role   = "controlplane"
  },
  {
    count  = 5
    cpu    = 4
    memory = 8192
    disk   = 50
    role   = "worker"
  },
  {
    count  = 3
    cpu    = 8
    memory = 16384
    disk   = 100
    role   = "controlplane"
  },
  {
    count  = 10
    cpu    = 8
    memory = 16384
    disk   = 100
    role   = "worker"
  }
]
```

### Phase 5: Node Provisioning

Deploy VMs using Terraform.

```bash
# Review Terraform configuration
vim terraform/proxmox/terraform.tfvars.dk1d

# Provision nodes (interactive confirmation)
./scripts/provision-nodes.sh dk1d

# Or with auto-approval
./scripts/provision-nodes.sh dk1d --auto-approve
```

**What this does:**
- Validates site and platform
- Runs `terraform init` (if needed)
- Runs `terraform plan` to show changes
- Runs `terraform apply` to create VMs
- VMs boot from Omni ISO
- VMs automatically register with Omni (2-5 minutes)

**Terraform output example:**
```
vm_names = [
  "dk1d-baseline-controlplane-1",
  "dk1d-baseline-controlplane-2",
  "dk1d-baseline-controlplane-3",
  "dk1d-baseline-worker-1",
  "dk1d-baseline-worker-2",
  ...
]
```

### Phase 6: Cluster Application

Apply cluster configurations to Omni.

```bash
# Apply all clusters in site
./scripts/apply-clusters.sh dk1d

# Or apply specific cluster
./scripts/apply-clusters.sh dk1d --cluster baseline
```

**What this does:**
- Finds all `cluster-*.yaml` files
- Splits multi-document YAML into individual resources
- Applies in order:
  1. MachineClasses (machine selection filters)
  2. Cluster (cluster definition)
  3. MachineSets (node group definitions)
- Verifies each resource created successfully

**MachineClass matching:**
- Matches machines by labels: `site=dk1d`, `platform=proxmox`, size-class (e.g., `4x8`)
- Machines must have exact matching labels to be allocated
- Labels are set in Omni UI or automatically by ISO (site/platform only)

### Phase 7: Machine Registration & Monitoring

Wait for machines to register and join clusters.

```bash
# Check registered machines
omnictl get machines

# Watch machines (updates every 2 seconds)
watch -n 2 omnictl get machines

# Check clusters
omnictl get clusters

# Check specific cluster status
omnictl cluster status dk1d-baseline

# Check cluster nodes
omnictl get machinesetstatus
```

**Timeline:**
- **0-2 min**: VMs boot and reach Talos
- **2-5 min**: Machines register with Omni (appear in `omnictl get machines`)
- **5-10 min**: Machines allocated to clusters via MachineClass matching
- **10-15 min**: Clusters form and become ready
- **15-20 min**: Kubernetes fully operational

**Machine labeling:**
Machines need labels to match MachineClasses:
```bash
# If using Omni UI (manual):
# 1. Navigate to Machines
# 2. Select machine
# 3. Add labels: dk1d, proxmox, 4x8

# Labels must match exactly what's in MachineClass
```

**Note:** ISO pre-configures `site` and `platform` labels. Size-class label must be added manually or scripted.

### Phase 8: Kubeconfig Download

Download kubeconfig files to access clusters.

```bash
# Download all kubeconfigs for site
./scripts/get-kubeconfigs.sh dk1d

# Download specific cluster
./scripts/get-kubeconfigs.sh dk1d --cluster baseline

# Merge into single kubeconfig
./scripts/get-kubeconfigs.sh dk1d --merge

# Custom output directory
./scripts/get-kubeconfigs.sh dk1d --output-dir ~/.kube/configs/
```

**What this does:**
- Checks if clusters are ready
- Downloads kubeconfig from Omni
- Saves to `kubeconfigs/<site>-<cluster>.yaml`
- Optionally merges all configs into single file

**Usage:**
```bash
# Single cluster
export KUBECONFIG=kubeconfigs/dk1d-baseline.yaml
kubectl get nodes

# Merged config
export KUBECONFIG=kubeconfigs/kubeconfig-dk1d.yaml
kubectl config get-contexts
kubectl config use-context admin@dk1d-baseline
kubectl get nodes

# All clusters at once
export KUBECONFIG=kubeconfigs/dk1d-baseline.yaml:kubeconfigs/dk1d-web.yaml
kubectl get nodes --all-namespaces
```

## Complete Example

Full deployment from start to finish:

```bash
# 1. Create site
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"

# 2. Configure Proxmox credentials
vim terraform/proxmox/terraform.tfvars.dk1d
# Set: proxmox_endpoint, proxmox_api_token, proxmox_node, etc.

# 3. Create clusters
./scripts/new-cluster.sh dk1d baseline --size-class 4x8 --control-planes 3 --workers 5
./scripts/new-cluster.sh dk1d web --size-class 8x16 --control-planes 3 --workers 10

# 4. Prepare ISOs (one per version)
./scripts/prepare-omni-iso.sh dk1d --talos-version 1.9.0

# 5. Update Terraform variables
./scripts/update-tfvars.sh dk1d

# 6. Provision nodes
./scripts/provision-nodes.sh dk1d

# 7. Wait for machines to register (2-5 min)
watch -n 2 omnictl get machines

# 8. Label machines in Omni UI
# Add labels: dk1d, proxmox, 4x8 (or 8x16 for web cluster nodes)

# 9. Apply clusters
./scripts/apply-clusters.sh dk1d

# 10. Wait for clusters to become ready (10-15 min)
watch -n 5 omnictl get clusters

# 11. Download kubeconfigs
./scripts/get-kubeconfigs.sh dk1d --merge

# 12. Access clusters
export KUBECONFIG=kubeconfigs/kubeconfig-dk1d.yaml
kubectl config get-contexts
kubectl get nodes --all-namespaces
```

## Troubleshooting

### Machines Not Registering

**Check VMs are running:**
```bash
# Proxmox
ssh root@proxmox1 "qm list | grep dk1d"

# Terraform output
cd terraform/proxmox
terraform output vm_names
```

**Check Omni credentials:**
```bash
echo $OMNI_ENDPOINT
echo $OMNI_SERVICE_ACCOUNT_KEY

# Test connection
omnictl get machines
```

**Check ISO configuration:**
```bash
# Verify ISO name in tfvars
grep omni_iso_name terraform/proxmox/terraform.tfvars.dk1d

# Check ISO exists on Proxmox
ssh root@proxmox1 "ls -lh /var/lib/vz/template/iso/talos-omni-*.iso"
```

### Machines Not Joining Clusters

**Check MachineClass matching:**
```bash
# Get MachineClasses
omnictl get machineclasses

# Check machine labels
omnictl get machines -o json | jq '.[] | {name: .metadata.id, labels: .metadata.labels}'
```

**Required labels:**
- `site=<site-code>` (from ISO)
- `platform=<platform>` (from ISO)
- Size-class label like `4x8` (manual or scripted)

**Add missing labels:**
Via Omni UI:
1. Navigate to Machines
2. Select machine
3. Edit labels
4. Add size-class: `4x8`, `8x16`, etc.

### Clusters Not Becoming Ready

**Check cluster status:**
```bash
omnictl cluster status dk1d-baseline
omnictl get machinesetstatus
```

**Common issues:**
- Not enough machines with matching labels
- Machines not healthy
- Etcd not forming quorum (need odd number of CPs: 1, 3, 5)
- Network connectivity issues

### Kubeconfig Download Fails

**Check cluster is ready:**
```bash
omnictl get clusters
# Status should be "Running" or "Ready"

omnictl cluster status dk1d-baseline
# Should show "Healthy" status
```

**Wait longer:**
Clusters can take 15-20 minutes to fully initialize.

## Day 2 Operations

### Scaling Clusters

See [SCALING-CLUSTERS.md](SCALING-CLUSTERS.md) for detailed scaling guide.

**Quick example:**
```bash
# Update cluster node counts
./scripts/new-cluster.sh dk1d baseline \
  --size-class 4x8 \
  --control-planes 5 \
  --workers 10 \
  --force

# Recalculate and provision
./scripts/update-tfvars.sh dk1d
./scripts/provision-nodes.sh dk1d

# Apply updated cluster config
./scripts/apply-clusters.sh dk1d --cluster baseline
```

### Adding New Clusters

```bash
# Create new cluster definition
./scripts/new-cluster.sh dk1d data --size-class 16x32 --control-planes 3 --workers 5

# Update variables and provision
./scripts/update-tfvars.sh dk1d
./scripts/provision-nodes.sh dk1d

# Apply new cluster
./scripts/apply-clusters.sh dk1d --cluster data
```

### Destroying Clusters

```bash
# Delete cluster from Omni
omnictl delete cluster dk1d-baseline

# Destroy VMs
cd terraform/proxmox
terraform destroy -var-file=terraform.tfvars.dk1d
```

## Best Practices

1. **Version Control** - Commit all cluster YAMLs and tfvars to git
2. **Backups** - Scripts create backups before modifying files
3. **Testing** - Test in dev sites before prod
4. **Documentation** - Update site READMEs with cluster purposes
5. **Monitoring** - Watch cluster health in Omni dashboard
6. **Labels** - Use consistent labeling for machine allocation
7. **Naming** - Follow site code conventions consistently
8. **Credentials** - Store Omni/Proxmox credentials securely
9. **ISOs** - Keep ISOs for multiple Talos versions available
10. **Planning** - Plan cluster resources before provisioning

## Related Documentation

- [README.md](../README.md) - Main documentation
- [QUICKSTART.md](QUICKSTART.md) - 10-minute quick start
- [SCALING-CLUSTERS.md](SCALING-CLUSTERS.md) - Cluster scaling guide
- [SITE-METADATA.md](SITE-METADATA.md) - Site metadata system
- [scripts/README.md](../scripts/README.md) - Script documentation
