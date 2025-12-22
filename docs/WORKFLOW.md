# Deployment Workflow

End-to-end workflow for deploying Talos Kubernetes clusters.

## Workflow Steps

### 1. Create Site
```bash
./scripts/new-site.sh <site-code> <platform> [--location "Description"]
```
Creates site directory structure and `site-<site>.yaml` metadata file.

### 2. Define Cluster(s)
```bash
./scripts/new-cluster.sh <site> <cluster-name> \
  --size-class <CPUxMEM> \
  --control-planes <count> \
  --workers <count> \
  --talos-version <version> \
  --kubernetes-version <version>
```
Creates `cluster-<name>.yaml` with MachineClasses, Cluster, and MachineSets.

### 3. Prepare ISOs
```bash
./scripts/prepare-omni-iso.sh <site>
```
Scans all clusters, downloads Omni ISOs for each Talos version, uploads to platform.

### 4. Update Terraform Variables
```bash
./scripts/update-tfvars.sh <site>
```
Aggregates all clusters into site tfvars with VM configs and ISO URLs.

### 5. Provision VMs
```bash
./scripts/provision-nodes.sh <site> [--auto-approve]
```
Deploys all VMs for all clusters in the site using Terraform.

### 6. Apply Clusters
```bash
./scripts/apply-clusters.sh <site> [--cluster <name>]
```
Applies cluster configurations to Omni (MachineClasses, Clusters, MachineSets).

### 7. Monitor Registration
```bash
watch -n 2 omnictl get machines
omnictl get clusters
omnictl cluster status <cluster-name>
```
Wait for machines to register (2-5 min) and clusters to become ready (15-20 min).

### 8. Download Kubeconfigs
```bash
./scripts/get-kubeconfigs.sh <site> [--cluster <name>] [--merge]
```
Downloads kubeconfig files for cluster access.

## Prerequisites

**Tools:** omnictl, terraform, jq, scp  
**Credentials:** OMNI_ENDPOINT, OMNI_SERVICE_ACCOUNT_KEY  
**Platform:** Proxmox API access and SSH for ISO upload

## Quick Example

```bash
# 1. Create site
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"

# 2. Edit Proxmox credentials
vim terraform/proxmox/terraform.tfvars.dk1d

# 3. Create cluster
./scripts/new-cluster.sh dk1d baseline --size-class 4x8 --control-planes 3 --workers 5

# 4. Prepare ISOs
./scripts/prepare-omni-iso.sh dk1d

# 5. Update variables
./scripts/update-tfvars.sh dk1d

# 6. Provision VMs
./scripts/provision-nodes.sh dk1d

# 7. Wait for registration (2-5 min)
watch -n 2 omnictl get machines

# 8. Apply cluster
./scripts/apply-clusters.sh dk1d

# 9. Wait for ready (15-20 min)
watch -n 5 omnictl get clusters

# 10. Download kubeconfig
./scripts/get-kubeconfigs.sh dk1d
export KUBECONFIG=kubeconfigs/dk1d-baseline.yaml
kubectl get nodes
```

## Key Concepts

**Per-Site Strategy:**
- One tfvars file per site aggregates all clusters
- ISOs versioned by Talos version (e.g., talos-omni-dk1d-1.9.0.iso)
- VMs grouped by role, size class, and Talos version

**Size Classes:**
Format: `CPUxMEMORY` (e.g., 4x8 = 4 cores, 8GB RAM)

**Machine Matching:**
MachineClasses filter by labels: `site`, `platform`, and size class

**Multiple Clusters:**
- Different sizes between clusters
- Different Talos versions between clusters
- Single site provisions all cluster VMs together

## Day 2 Operations

### Scale Cluster
```bash
./scripts/new-cluster.sh <site> <cluster> --control-planes <new> --workers <new> --force
./scripts/update-tfvars.sh <site>
./scripts/provision-nodes.sh <site>
./scripts/apply-clusters.sh <site> --cluster <cluster>
```

### Add Cluster
```bash
./scripts/new-cluster.sh <site> <new-cluster> <options>
./scripts/prepare-omni-iso.sh <site>  # if new version
./scripts/update-tfvars.sh <site>
./scripts/provision-nodes.sh <site>
./scripts/apply-clusters.sh <site> --cluster <new-cluster>
```

### Remove Cluster
```bash
omnictl delete cluster <cluster-name>
rm clusters/omni/<site>/cluster-<name>.yaml
./scripts/update-tfvars.sh <site>
cd terraform/proxmox && terraform apply -var-file=terraform.tfvars.<site>
```

## Troubleshooting

**Machines not registering:**
- Check VMs running: `ssh root@proxmox "qm list"`
- Verify Omni credentials: `omnictl get machines`
- Check ISO uploaded: `ssh root@proxmox "ls /var/lib/vz/template/iso/"`

**Machines not joining:**
- Check labels match MachineClass: `omnictl get machines -o json | jq '.[].metadata.labels'`
- Add missing labels in Omni UI

**Cluster not ready:**
- Check status: `omnictl cluster status <cluster>`
- Wait 15-20 minutes for full initialization

## Related Documentation

- [README.md](../README.md) - Overview and architecture
- [QUICKSTART.md](QUICKSTART.md) - 10-minute setup
- [SCALING-CLUSTERS.md](SCALING-CLUSTERS.md) - Scaling guide
- [MACHINE-LABELING.md](MACHINE-LABELING.md) - Labeling system
