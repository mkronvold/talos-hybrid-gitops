# Jumphost Terraform Configuration

This Terraform configuration deploys an Ubuntu jumphost VM to vSphere for managing Talos clusters.

## Overview

The jumphost is a management VM that comes pre-configured with all necessary tools for deploying and managing Talos Kubernetes clusters using the hybrid GitOps approach.

## What Gets Installed

The jumphost is automatically configured with:

### Tools
- Terraform v1.6.0
- kubectl (stable)
- Flux CD
- Omni CLI (omnictl)
- Talosctl v1.9.5
- Node.js LTS (via NVM)
- GitHub Copilot CLI
- Git, vim, tmux, jq, and other essentials

### Repository
- Talos Hybrid GitOps repository cloned to `~/talos-hybrid-gitops`
- All scripts ready to use
- Shell aliases configured (k=kubectl, tf=terraform)

## Prerequisites

### Ubuntu Cloud Image

Download and import Ubuntu cloud image to vSphere:

```bash
# Download Ubuntu 22.04 LTS cloud image
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova

# Import to vSphere as a template named "ubuntu-22.04-cloud"
```

### SSH Key

Generate an SSH key if you don't have one:

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
cat ~/.ssh/id_rsa.pub
```

## Multi-Site Architecture

This configuration supports deploying multiple jumphosts across different sites using Terraform workspaces for state isolation.

### Site Code Format

```
<city><zone><env>

Examples:
  ny1d - New York, Zone 1, Dev
  sf2p - San Francisco, Zone 2, Prod
  la1s - Los Angeles, Zone 1, Staging

Components:
  <city> - 2-letter city/location code
  <zone> - Single digit zone number (1-9)
  <env>  - d (dev), s (staging), p (prod)
```

## Configuration

### 1. Create site-specific terraform.tfvars

```bash
# For New York Zone 1 Dev
cp terraform.tfvars.example terraform.tfvars.ny1d

# For San Francisco Zone 2 Prod
cp terraform.tfvars.example terraform.tfvars.sf2p
```

### 2. Edit terraform.tfvars.\<site-code\>

```hcl
# vSphere Connection
vsphere_server     = "vcenter.example.com"
vsphere_user       = "administrator@vsphere.local"
vsphere_password   = "your-password"
vsphere_insecure   = true

# vSphere Resources
vsphere_datacenter    = "Datacenter"
vsphere_cluster       = "Cluster"
vsphere_datastore     = "datastore1"
vsphere_network       = "VM Network"
vsphere_resource_pool = "Cluster/Resources"
vsphere_folder        = "Management"

# Ubuntu Template
ubuntu_template = "ubuntu-22.04-cloud"

# Jumphost Configuration
jumphost_hostname = "jumphost-ny1d"  # Use site code in hostname
jumphost_cpu      = 2
jumphost_memory   = 4096  # MB
jumphost_disk_size = 50   # GB

# User Configuration
jumphost_username = "ubuntu"
jumphost_ssh_keys = [
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... user@host",
]

# Timezone (optional)
jumphost_timezone = "America/New_York"
```

## Deployment

### Using the deployment script (recommended):

```bash
cd ~/talos-hybrid-gitops

# Deploy New York Zone 1 Dev jumphost
./scripts/deploy-jumphost.sh ny1d

# Deploy San Francisco Zone 2 Prod jumphost
./scripts/deploy-jumphost.sh sf2p
```

### Manual deployment with workspaces:

```bash
cd terraform/jumphost

# Initialize Terraform
terraform init

# Create/select workspace for site
terraform workspace new ny1d
# or
terraform workspace select ny1d

# Plan deployment
terraform plan -var-file="terraform.tfvars.ny1d"

# Apply configuration
terraform apply -var-file="terraform.tfvars.ny1d"
```

### List and manage workspaces:

```bash
# List all workspaces (one per site)
terraform workspace list

# Switch between sites
terraform workspace select sf2p

# Show current workspace
terraform workspace show
```

## Post-Deployment

### 1. Wait for cloud-init

Cloud-init takes 5-10 minutes to complete. Check progress:

```bash
ssh ubuntu@<jumphost-ip>
tail -f /var/log/cloud-init-output.log
```

### 2. Verify installation

```bash
ssh ubuntu@<jumphost-ip>

# Check installed tools
terraform version
kubectl version --client
flux version --client
omnictl version
talosctl version --client
node -v
npm -v

# Verify repository
cd ~/talos-hybrid-gitops
ls -la
```

### 3. Configure for cluster deployment

```bash
# Configure Terraform for vSphere/Proxmox
cd ~/talos-hybrid-gitops/terraform/vsphere
cp terraform.tfvars.example terraform.tfvars
# Edit with your settings

# Set Omni credentials
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-api-key>

# Deploy a cluster
cd ~/talos-hybrid-gitops
./scripts/deploy-infrastructure.sh vsphere clusters/omni/prod-vsphere.yaml
```

## Outputs

After successful deployment:

- **jumphost_ip** - IP address of the jumphost
- **jumphost_name** - VM name in vSphere
- **ssh_command** - Full SSH command to connect

View outputs:

```bash
terraform output
```

## Cloud-Init Details

The cloud-init configuration (`cloud-init.yaml`) performs these actions:

1. Sets hostname and timezone
2. Creates user with sudo access and SSH keys
3. Updates system packages
4. Installs essential packages
5. Clones talos-hybrid-gitops repository
6. Runs install-dependencies.sh script
7. Runs install-node-copilot.sh script
8. Configures shell aliases and completions

## Customization

### Change VM specifications:

Edit in `terraform.tfvars`:
```hcl
jumphost_cpu       = 4     # More CPU
jumphost_memory    = 8192  # More RAM
jumphost_disk_size = 100   # Larger disk
```

### Add additional packages:

Edit `cloud-init.yaml` and add to the `packages` list:
```yaml
packages:
  - your-package-name
```

### Add custom runcmd scripts:

Edit `cloud-init.yaml` and add to the `runcmd` section:
```yaml
runcmd:
  - your-command-here
```

## Troubleshooting

### VM doesn't get an IP address

- Ensure the network supports DHCP
- Check vSphere network settings
- Verify template has network adapter configured

### Cloud-init fails

Check logs on the VM:
```bash
ssh ubuntu@<jumphost-ip>
cat /var/log/cloud-init.log
cat /var/log/cloud-init-output.log
```

### SSH connection refused

- Wait a few minutes for cloud-init to complete
- Verify SSH key is correct in terraform.tfvars
- Check vSphere firewall rules

### Tools not installed

Re-run installation scripts manually:
```bash
ssh ubuntu@<jumphost-ip>
cd ~/talos-hybrid-gitops
./scripts/install-dependencies.sh
./scripts/install-node-copilot.sh
```

## Cleanup

To destroy the jumphost:

```bash
cd terraform/jumphost
terraform destroy
```

## Security Considerations

1. **SSH Keys**: Only use secure SSH key pairs
2. **Passwords**: Never commit terraform.tfvars with passwords
3. **Network**: Place jumphost in a management network
4. **Access**: Restrict SSH access via firewall rules
5. **Updates**: Regularly update the VM with security patches

## Additional Resources

- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Terraform vSphere Provider](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs)
- [Main Project README](../../README.md)
