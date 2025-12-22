# Cluster Scaling Guide

This document explains how to scale Talos clusters up or down by adding or removing nodes.

## Overview

The workflow uses:
- `new-cluster.sh` to update cluster configuration
- `update-tfvars.sh` to recalculate Terraform variables
- Terraform to add/remove VMs
- Omni to handle cluster membership

## Scaling Up (Adding Nodes)

### Step 1: Update Cluster Configuration

```bash
# Increase control planes from 1 to 3, workers from 3 to 5
./scripts/new-cluster.sh dk1d baseline \
  --size-class 4x8 \
  --control-planes 3 \
  --workers 5 \
  --force
```

This updates `clusters/omni/dk1d/cluster-baseline.yaml` with new node counts.

### Step 2: Update Terraform Variables

```bash
./scripts/update-tfvars.sh dk1d
```

This recalculates vm_configs based on all cluster YAMLs in the site.

### Step 3: Review Changes

```bash
cat terraform/proxmox/terraform.tfvars.dk1d
```

Check that vm_configs reflects the new node counts:
```hcl
vm_configs = [
  {
    count  = 3  # Increased from 1
    cpu    = 4
    memory = 8192
    disk   = 50
    role   = "controlplane"
  },
  {
    count  = 5  # Increased from 3
    cpu    = 4
    memory = 8192
    disk   = 50
    role   = "worker"
  }
]
```

### Step 4: Apply Terraform Changes

```bash
cd terraform/proxmox
terraform plan -var-file=terraform.tfvars.dk1d
```

Review the plan - should show new VMs being created:
```
Plan: 4 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -var-file=terraform.tfvars.dk1d
```

### Step 5: Label New Machines in Omni

After VMs boot and register with Omni (2-5 minutes):

```bash
./scripts/check-machines.sh clusters/omni/dk1d/cluster-baseline.yaml
```

Label each new machine in Omni UI with:
```
dk1d, proxmox, 4x8
```

### Step 6: Update Cluster Template

Apply the updated cluster configuration:

```bash
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

Omni will automatically allocate the new machines to the cluster based on MachineClass matching.

## Scaling Down (Removing Nodes)

**⚠️ Warning:** Scaling down requires careful planning to avoid data loss or cluster instability.

### Prerequisites

- For control planes: Must maintain odd number (1, 3, 5) for etcd quorum
- For workers: Ensure workloads can be drained safely
- Never reduce control planes below 1 or below current etcd member count

### Step 1: Drain Nodes (Workers Only)

For worker nodes, drain workloads first via Omni UI or kubectl:

```bash
# Via kubectl (if accessible)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Via Omni UI
# Navigate to Cluster → Nodes → Select node → Drain
```

### Step 2: Update Cluster Configuration

```bash
# Reduce workers from 5 to 2
./scripts/new-cluster.sh dk1d baseline \
  --size-class 4x8 \
  --control-planes 3 \
  --workers 2 \
  --force
```

### Step 3: Update Terraform Variables

```bash
./scripts/update-tfvars.sh dk1d
```

### Step 4: Review Terraform Plan

```bash
cd terraform/proxmox
terraform plan -var-file=terraform.tfvars.dk1d
```

Should show VMs being destroyed:
```
Plan: 0 to add, 0 to change, 3 to destroy.
```

**Review carefully:** Terraform will destroy VMs with the highest indices first.
- Example: If reducing workers 1-5 to 1-2, it will destroy workers 3, 4, 5

### Step 5: Apply Terraform Changes

```bash
terraform apply -var-file=terraform.tfvars.dk1d
```

Terraform will:
1. Destroy the excess VMs
2. VMs disappear from Proxmox
3. Machines eventually disconnect from Omni

### Step 6: Update Cluster Template

```bash
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml
```

This updates the MachineSet to expect fewer nodes. Omni will automatically handle:
- Removing disconnected machines from cluster
- Rebalancing workloads if needed
- Updating cluster status

### Step 7: Cleanup (Optional)

Disconnected machines may linger in Omni. They will auto-cleanup after ~15-30 minutes, or manually remove via Omni UI.

## Scaling Considerations

### Control Plane Scaling

**Best Practices:**
- Always maintain odd number (1, 3, 5, 7)
- Recommended: 1 for dev, 3 for prod, 5 for large/critical
- Scale up before scaling down
- Never reduce below current etcd member count

**Etcd Quorum:**
- 1 CP: No quorum, tolerate 0 failures
- 3 CP: Quorum of 2, tolerate 1 failure
- 5 CP: Quorum of 3, tolerate 2 failures

**Scaling Up Process:**
1. Add new control planes (Terraform)
2. Label machines in Omni
3. Update cluster template (Omni adds to etcd)
4. Wait for etcd to sync (check Omni cluster health)

**Scaling Down Process:**
1. Remove from cluster template first
2. Wait for etcd member removal
3. Then destroy VMs via Terraform
4. This ensures clean etcd removal

### Worker Scaling

**Best Practices:**
- Workers can be any number (0+)
- Scale workers based on workload needs
- Always drain before removing
- Consider pod disruption budgets

**Scaling Up Process:**
1. Add new workers (Terraform)
2. Label machines in Omni
3. Update cluster template
4. Workloads can be scheduled immediately

**Scaling Down Process:**
1. Drain nodes first
2. Update cluster template (reduces MachineSet)
3. Destroy VMs via Terraform
4. Omni removes nodes from cluster

## Size Class Changes

To change VM resources (e.g., 4x8 → 8x16):

### Option 1: In-Place Update (Requires VM Downtime)

**Not supported** - Proxmox doesn't support live CPU/memory changes. Must destroy and recreate.

### Option 2: Rolling Update

1. **Increase total nodes** (e.g., 3 CPs + 5 workers → 6 CPs + 10 workers)
2. **Update half to new size:**
   ```bash
   # This requires manual Terraform editing currently
   # Add new config to vm_configs, keep old config
   ```
3. **Drain and remove old nodes**
4. **Wait for workloads to migrate**
5. **Remove old node configs**

### Option 3: New Cluster Migration

1. Create new cluster with desired size
2. Migrate workloads
3. Destroy old cluster

This is often simpler for production workloads.

## Multiple Clusters in One Site

The system supports multiple clusters with different sizes:

```bash
# Cluster 1: Small dev cluster
./scripts/new-cluster.sh dk1d dev \
  --size-class 2x4 \
  --control-planes 1 \
  --workers 2

# Cluster 2: Large prod cluster  
./scripts/new-cluster.sh dk1d prod \
  --size-class 8x16 \
  --control-planes 3 \
  --workers 10

# Update tfvars (calculates total: 1+2+3+10 = 16 VMs)
./scripts/update-tfvars.sh dk1d
```

Results in:
```hcl
vm_configs = [
  {
    count  = 1
    cpu    = 2
    memory = 4096
    disk   = 50
    role   = "controlplane"
  },
  {
    count  = 2
    cpu    = 2
    memory = 4096
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

## Automation

### GitOps Workflow

```bash
# 1. Update cluster config
./scripts/new-cluster.sh <site> <cluster> --size-class <size> --control-planes <n> --workers <n> --force

# 2. Update tfvars
./scripts/update-tfvars.sh <site>

# 3. Commit changes
git add clusters/ terraform/
git commit -m "Scale <cluster> to <n> CP, <n> workers"
git push

# 4. Apply via CI/CD or manually
cd terraform/<platform>
terraform plan -var-file=terraform.tfvars.<site>
terraform apply -var-file=terraform.tfvars.<site>

# 5. Label machines and apply cluster template
# (Manual step - label machines in Omni UI)
./scripts/apply-cluster.sh clusters/omni/<site>/cluster-<name>.yaml
```

### Automated Scaling Scripts

You can wrap these commands in scripts for common scenarios:

```bash
#!/bin/bash
# scale-workers.sh - Scale worker count for a cluster

SITE=$1
CLUSTER=$2
WORKER_COUNT=$3

./scripts/new-cluster.sh $SITE $CLUSTER \
  --workers $WORKER_COUNT \
  --force

./scripts/update-tfvars.sh $SITE

echo "Review and apply:"
echo "  cd terraform/proxmox"
echo "  terraform plan -var-file=terraform.tfvars.$SITE"
echo "  terraform apply -var-file=terraform.tfvars.$SITE"
```

## Troubleshooting

### Nodes Not Joining After Scale Up

**Check:**
1. VMs booted successfully: `terraform output vm_names`
2. Machines registered in Omni: `./scripts/check-machines.sh <cluster-yaml>`
3. Machines have correct labels: Check Omni UI
4. MachineSet has capacity: `omnictl get machinesetstatus`

### Nodes Not Removing After Scale Down

**Check:**
1. Cluster template applied: Verify MachineSet size reduced
2. Omni removed nodes: Check cluster node count
3. VMs destroyed: Check Proxmox
4. Terraform state: `terraform show`

### Etcd Issues After Control Plane Scaling

**Symptoms:**
- Cluster unavailable
- API server errors
- Etcd quorum lost

**Recovery:**
1. Check etcd member list: `omnictl cluster status <cluster>`
2. If members mismatch, may need manual etcd member removal
3. See Talos documentation for etcd recovery

### Wrong VMs Destroyed

**Prevention:**
- Always review `terraform plan` before applying
- Terraform destroys highest-indexed VMs first
- If specific VMs need removal, use targeted operations

**Recovery:**
- Recreate VMs: `terraform apply`
- Relabel machines in Omni
- Update cluster template

## Best Practices

1. **Plan before executing** - Always run terraform plan first
2. **Test in dev** - Try scaling operations in dev environment first
3. **Backup etcd** - Especially before control plane scaling
4. **Monitor cluster health** - Use Omni UI to watch cluster status
5. **Document changes** - Commit messages should explain why scaling
6. **Gradual scaling** - Scale by small increments
7. **Maintain quorum** - Never reduce CPs below quorum threshold
8. **Drain first** - Always drain workers before removal
9. **Check PDBs** - Respect pod disruption budgets
10. **Off-hours scaling** - Scale prod during maintenance windows

## Related Documentation

- [Machine Labeling Guide](MACHINE-LABELING.md)
- [Deployment Workflow](DEPLOYMENT-WORKFLOW.md)
- [Site Metadata System](SITE-METADATA.md)
