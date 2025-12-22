# Machine Labeling Guide

This document explains the machine labeling system used for Omni cluster allocation.

## Overview

Machines must be labeled in Omni for automatic allocation to clusters. The labeling system uses three key labels:

1. **Site** - Identifies the physical/logical site location
2. **Platform** - Identifies the infrastructure platform
3. **Size** - Classifies machine resources

## Label Format

Labels are added in the Omni UI as comma-separated values:

```
<site-code>, <platform>, <size-class>
```

**Example:**
```
dk1d, proxmox, small
```

## Label Definitions

### Site Label

Format: `<city><zone><env>`

**Examples:**
- `dk1d` - Denmark Zone 1 Dev
- `ny1p` - New York Zone 1 Production  
- `sf2s` - San Francisco Zone 2 Staging

### Platform Label

Values: `proxmox` or `vsphere`

Identifies which infrastructure platform the machine runs on.

### Size Class Label

Defines machine resource tier for workload placement:

| Size Class | CPU Cores | Memory | Use Case |
|------------|-----------|---------|----------|
| `small` | 2 | 4-8 GB | Development, testing, CI/CD |
| `medium` | 4 | 8-16 GB | Staging, small production workloads |
| `large` | 8+ | 16+ GB | Production, databases, heavy workloads |

## How It Works

### 1. Machine Registration

When VMs boot with Talos:
- Machines automatically register with Omni (2-5 minutes)
- Appear in Omni UI without labels
- Show as "available" but not allocated

### 2. Labeling Process

**Via Omni UI:**
1. Navigate to Machines page
2. Select a machine
3. Click "Add Labels" or "Edit"
4. Enter labels: `dk1d, proxmox, small`
5. Save

**Cannot be done via CLI** - Machine labels are metadata managed by Omni UI only.

### 3. Automatic Allocation

Once labeled:
- MachineClasses match machines based on labels
- MachineSets automatically allocate matching machines
- Cluster provisions and installs Talos to disk

## MachineClass Configuration

MachineClasses define selection criteria:

```yaml
metadata:
  type: MachineClasses.omni.sidero.dev
  id: dk1d-baseline-control-plane
spec:
  matchlabels:
    - dk1d,proxmox,small
```

This matches machines with ALL three labels.

## Checking Label Status

Use the helper script:

```bash
./scripts/check-machines.sh clusters/omni/dk1d/cluster-baseline.yaml
```

Output shows:
- Registered machines
- Connection status
- Label status (labeled vs unlabeled)
- Required labels for your cluster

## Common Scenarios

### New Deployment

```bash
# 1. Create cluster config
./scripts/new-cluster.sh dk1d baseline --control-planes 1 --workers 3

# 2. Deploy infrastructure
./scripts/deploy-infrastructure.sh dk1d clusters/omni/dk1d/cluster-baseline.yaml

# 3. Wait for machines to register (2-5 minutes)
watch omnictl get machines

# 4. Check labeling status
./scripts/check-machines.sh clusters/omni/dk1d/cluster-baseline.yaml

# 5. Label machines in Omni UI with: dk1d, proxmox, small

# 6. Verify allocation
omnictl get clustermachines
```

### Multi-Site Setup

Different sites can share the same Omni instance:

```bash
# Site 1: Denmark Dev
Labels: dk1d, proxmox, small

# Site 2: NY Prod  
Labels: ny1p, vsphere, large

# Site 3: SF Staging
Labels: sf2s, vsphere, medium
```

Clusters only allocate machines matching their site code.

### Mixed Workloads

Use size classes to separate workload types:

```yaml
# Control plane - needs reliability, moderate resources
matchlabels:
  - dk1d,proxmox,medium

# Workers - high performance workloads
matchlabels:
  - dk1d,proxmox,large

# Edge workers - lightweight workloads
matchlabels:
  - dk1d,proxmox,small
```

## Troubleshooting

### Machines Not Allocating

**Problem:** Machines registered but not joining cluster

**Check:**
```bash
# 1. Verify machines have labels
./scripts/check-machines.sh clusters/omni/dk1d/cluster-baseline.yaml

# 2. Check MachineClass requirements
omnictl get machineclasses -o yaml | grep -A 2 matchlabels

# 3. Check MachineSet status
omnictl get machinesetstatus
```

**Common Causes:**
- Missing labels on machines
- Typo in label names
- Wrong format (need comma-separated, not key=value)
- MachineClass and machine labels don't match

### Wrong Size Class

**Problem:** Labeled wrong size for machine resources

**Solution:**
1. Go to Omni UI
2. Edit machine labels
3. Change size class to match actual VM resources
4. Save - MachineClass will re-evaluate

### Labels Not Saving

**Problem:** Labels disappear after saving in UI

**Causes:**
- Browser cache issues - try hard refresh
- Omni API connectivity - check network
- Permissions - ensure user can edit machines

**Solution:**
- Clear browser cache
- Try different browser
- Check Omni UI console for errors

## Best Practices

### 1. Consistent Naming

Use same label format across all sites:
- Always lowercase
- Use 4-character site codes
- Match platform to actual infrastructure

### 2. Size Class Standards

Define organization-wide standards:
```
small:  dev/test (2 CPU, 4-8 GB)
medium: staging (4 CPU, 8-16 GB)  
large:  prod (8+ CPU, 16+ GB)
```

### 3. Label Immediately

After deployment:
1. VMs boot (0-2 min)
2. Register with Omni (2-5 min)
3. Label immediately (prevent allocation delays)
4. Verify allocation (omnictl get clustermachines)

### 4. Document Site Labels

Keep site label reference:
```bash
# clusters/omni/<site-code>/README.md
Site Code: dk1d
Location: Denmark Zone 1 Dev
Platform: proxmox
Standard Labels: dk1d, proxmox, small
```

### 5. Automation

For production, consider:
- Talos machine configuration with labels (Enterprise)
- SAML-based auto-labeling (Enterprise)
- Custom webhooks to apply labels via API

## Scripts Reference

### check-machines.sh

Check machine registration and label status:

```bash
# Check all machines
./scripts/check-machines.sh

# Check for specific cluster
./scripts/check-machines.sh clusters/omni/dk1d/cluster-baseline.yaml
```

### new-cluster.sh

Generates cluster YAML with required labels documented:

```bash
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 3
```

Output includes labeling instructions.

## FAQ

**Q: Can I label machines via CLI?**  
A: No, machine labels are metadata managed only through Omni UI.

**Q: What if I label wrong?**  
A: Edit labels in UI anytime. MachineClass re-evaluates automatically.

**Q: Do labels persist after machine reboot?**  
A: Yes, labels are stored in Omni, not on the machine.

**Q: Can one machine match multiple MachineClasses?**  
A: Yes, but it will only be allocated to one MachineSet at a time.

**Q: How do I remove a label?**  
A: Edit machine in Omni UI and delete the label value.

**Q: Can I use custom label names?**  
A: Yes, but MachineClasses must match. Standard names (site, platform, size) are recommended for consistency.

## Related Documentation

- [Site Metadata System](SITE-METADATA.md)
- [Cluster Configuration](../scripts/README.md#new-clustersh)
- [Omni Documentation](https://omni.siderolabs.com/docs)
