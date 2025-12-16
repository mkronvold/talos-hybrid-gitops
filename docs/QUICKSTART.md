# Quick Start Guide

Get a Talos Kubernetes cluster running in minutes!

## Prerequisites

### 1. Install Tools

**With Homebrew (Recommended - macOS/Linux):**
```bash
# Install all Talos/Omni tools with one command
brew install siderolabs/tap/sidero-tools  # Installs omnictl, talosctl, kubectl

# Additional tools
brew install terraform fluxcd/tap/flux
```

**Or use the automated script:**
```bash
git clone https://github.com/mkronvold/talos-hybrid-gitops.git
cd talos-hybrid-gitops
./scripts/install-dependencies.sh
```

### 2. Get Omni API Key

1. Visit https://omni.siderolabs.com
2. Sign up (free tier: 10 machines, 1 cluster)
3. Go to Settings → API Keys → Create new key
4. Save the key securely

### 3. Set Credentials

```bash
export OMNI_ENDPOINT=https://omni.siderolabs.com
export OMNI_API_KEY=<your-api-key>
```

## Quick Deploy

### Option A: Automated Deployment

```bash
# 1. Create a site
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1 Dev"

# 2. Configure Terraform
vim terraform/vsphere/terraform.tfvars.ny1d
# Add your vSphere credentials and settings

# 3. Deploy everything
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/<cluster>.yaml
```

### Option B: Manual Deployment

```bash
# 1. Configure site
cd terraform/vsphere  # or proxmox
cp terraform.tfvars.example terraform.tfvars.mysite
# Edit terraform.tfvars.mysite

# 2. Create site metadata
./scripts/new-site.sh mysite vsphere --location "My Site"

# 3. Deploy infrastructure
terraform init  # Download providers and create lock file
terraform workspace select -or-create mysite
terraform apply -var-file=terraform.tfvars.mysite

# 4. Deploy cluster
cd ../..
./scripts/new-cluster.sh mysite web --control-planes 3 --workers 5
omnictl apply -f clusters/omni/mysite/web.yaml

# 5. Access cluster
omnictl kubeconfig mysite-web > kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

## Next Steps

1. **Bootstrap GitOps:**
   ```bash
   flux bootstrap github \
     --owner=<your-github-username> \
     --repository=talos-hybrid-gitops \
     --branch=main \
     --path=kubernetes/clusters/<cluster-name> \
     --personal
   ```

2. **Deploy Applications:**
   ```bash
   kubectl apply -f kubernetes/apps/
   ```

3. **Explore More:**
   - See [WORKFLOW.md](../WORKFLOW.md) for complete examples
   - See [scripts/README.md](../scripts/README.md) for all automation scripts
   - See [SITE-METADATA.md](SITE-METADATA.md) for multi-site architecture

## Troubleshooting

**Tools not found after installation?**
```bash
# Ensure Homebrew is in your PATH
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
source ~/.zprofile

# Verify installations
omnictl version
talosctl version --client
kubectl version --client
```

**Machines not registering with Omni?**
- Wait 2-5 minutes for VMs to boot
- Check Omni UI for machine visibility
- Verify network connectivity from VMs to Omni

**Terraform errors?**
- Run `terraform init` first to download providers and create lock file
- If you see "Inconsistent dependency lock file" errors, run `terraform init` again
- Verify credentials in terraform.tfvars
- Ensure vSphere template or Proxmox ISO is available
- Check resource limits (CPU, memory, storage)
