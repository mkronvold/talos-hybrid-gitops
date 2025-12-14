# Quick Start Guide

See complete deployment instructions in this file.

## Prerequisites

1. Install: terraform, omnictl, kubectl, flux
2. Get Omni API key from https://omni.siderolabs.com
3. Prepare Talos images for your platform

## Quick Deploy

```bash
# Configure
cd terraform/vsphere  # or proxmox
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# Deploy everything
cd ../..
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=your-key
./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml
```

See full documentation in repository README.
