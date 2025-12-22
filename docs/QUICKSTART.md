# Quick Start Guide

Deploy a Talos Kubernetes cluster in 10 minutes.

## Prerequisites

### 1. Install Tools (2 minutes)

**macOS/Linux with Homebrew:**
```bash
brew install siderolabs/tap/sidero-tools terraform
```

**Or automated:**
```bash
git clone https://github.com/mkronvold/talos-hybrid-gitops.git
cd talos-hybrid-gitops
./scripts/install-dependencies.sh
```

### 2. Get Omni Credentials (3 minutes)

1. Visit your Omni instance: `https://yourorg.omni.siderolabs.io`
2. Settings → Service Accounts → Create
3. Download `omni.sh` 
4. Add to shell:
   ```bash
   echo "source ~/omni.sh" >> ~/.bashrc
   source ~/.bashrc
   ```

## Deploy a Cluster (5 minutes)

### Proxmox Example

```bash
# 1. Create site
./scripts/new-site.sh dk1d proxmox --location "Denmark Zone 1 Dev"

# 2. Configure (edit with your Proxmox details)
vim terraform/proxmox/terraform.tfvars.dk1d

# 3. Create cluster (interactive)
./scripts/new-cluster.sh dk1d baseline -i

# 4. Deploy (all-in-one)
./scripts/deploy-infrastructure.sh dk1d --prepare-iso

# 5. Apply cluster config
./scripts/apply-cluster.sh clusters/omni/dk1d/cluster-baseline.yaml

# 6. Access cluster
omnictl kubeconfig dk1d-baseline > kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

### What Just Happened?

1. **Created site structure** - Folders and configs for `dk1d`
2. **Generated cluster config** - Interactive prompts for size, topology
3. **Prepared Omni ISO** - Downloaded ISO with your Omni credentials + site labels
4. **Deployed VMs** - Terraform created VMs and booted from ISO
5. **Auto-registered** - VMs connected to Omni automatically
6. **Applied cluster** - Omni configured Kubernetes cluster
7. **Ready to use** - Cluster is running

## vSphere Example

```bash
# Same as Proxmox, just change platform:
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1 Dev"
vim terraform/vsphere/terraform.tfvars.ny1d
./scripts/new-cluster.sh ny1d web -i
./scripts/deploy-infrastructure.sh ny1d --prepare-iso
./scripts/apply-cluster.sh clusters/omni/ny1d/cluster-web.yaml
```

## Non-Interactive Mode

```bash
# Specify all options on command line
./scripts/new-cluster.sh dk1d baseline \
  --control-planes 1 \
  --workers 3 \
  --size-class small \
  --cpu 2 \
  --memory 4096 \
  --disk 50

# Two-step deploy (prepare ISO separately)
./scripts/prepare-omni-iso.sh dk1d
./scripts/deploy-infrastructure.sh dk1d
```

## Troubleshooting

**VMs not showing in Omni?**
- Wait 2-5 minutes after boot
- Check VM console for errors
- Verify network to Omni endpoint
- Check: Omni UI → Unassigned Machines

**"ISO reference file not found"?**
```bash
./scripts/prepare-omni-iso.sh dk1d
```

**Terraform provider errors?**
```bash
cd terraform/proxmox  # or vsphere
terraform init -upgrade
```

## Next Steps

- **Add more clusters**: `./scripts/new-cluster.sh dk1d web -i`
- **Different size**: Use size classes: tiny, small, medium, large, xlarge, huge
- **Multiple sites**: Repeat for different locations/environments
- **Custom extensions**: `./scripts/prepare-omni-iso.sh dk1d --extensions intel-ucode`

See [../README.md](../README.md) for complete documentation.
