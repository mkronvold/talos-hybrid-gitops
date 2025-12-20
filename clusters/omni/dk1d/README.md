# Site: dk1d

**Location:** dk1d  
**Environment:** development  
**Platform:** proxmox  
**Created:** Tue Dec 16 15:13:37 CST 2025

## Overview

This directory contains cluster configurations for the **dk1d** site.

## Site Information

- **Site Code:** dk1d
- **Location:** dk1d
- **Environment:** development
- **Platform:** proxmox

## Configuration Files

### Terraform
- vSphere: `terraform/vsphere/terraform.tfvars.dk1d`
- Proxmox: `terraform/proxmox/terraform.tfvars.dk1d`
- Jumphost: `terraform/jumphost/terraform.tfvars.dk1d`

### Clusters
Cluster configurations are stored in this directory:
- `<cluster-name>.yaml` - Omni cluster definitions

## Quick Start

### 1. Deploy Jumphost

```bash
# Review and edit jumphost configuration
vim terraform/jumphost/terraform.tfvars.dk1d

# Deploy jumphost
./scripts/deploy-jumphost.sh dk1d
```

### 2. Create a Cluster

```bash
# Create cluster configuration
./scripts/new-cluster.sh dk1d <cluster-name> \
  --control-planes 3 \
  --workers 3 \
  --cpu 4 \
  --memory 8192

# Review cluster configuration
cat clusters/omni/dk1d/<cluster-name>.yaml
```

### 3. Deploy Infrastructure and Cluster

```bash
# Set Omni credentials (if not already in ~/.bashrc)
source ~/omni.sh

# Deploy
./scripts/deploy-infrastructure.sh dk1d \
  clusters/omni/dk1d/<cluster-name>.yaml
```

## Clusters

| Cluster Name | Control Planes | Workers | Status | Created |
|--------------|----------------|---------|--------|---------|
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-17 |

| dk1d-baseline | 1 | 3 | not deployed | 2025-12-19 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-19 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-19 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-19 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-20 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-20 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-20 |
| dk1d-baseline | 1 | 3 | not deployed | 2025-12-20 |
## Notes

<!-- Add site-specific notes here -->

## Maintenance Log

| Date | Action | Details |
|------|--------|---------|
| 2025-12-16 | Site created | Initial setup for dk1d |

