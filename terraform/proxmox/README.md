# Proxmox Infrastructure Deployment

This directory contains Terraform configuration for provisioning Talos VMs on Proxmox.

## Prerequisites

1. **Proxmox Server** - Version 7.0 or later
2. **Terraform** - Version 1.6 or later
3. **API Token** - Create a Proxmox API token for Terraform

## Creating a Proxmox API Token

### Step 1: Create API Token (Recommended)

1. Log in to Proxmox web UI
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add** to create a new token
4. Configure:
   - **User**: `root@pam` (or your user)
   - **Token ID**: `terraform` (or any name)
   - **Privilege Separation**: Uncheck this box (token will have same permissions as user)
5. Click **Add**
6. **Important**: Copy the token secret immediately - it won't be shown again!
7. Your token will look like: `root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### Step 2: Set Permissions (if needed)

If using a non-root user, ensure the user has these permissions:
- **VM.Allocate** - Create VMs
- **VM.Config.Disk** - Configure disks
- **VM.Config.CPU** - Configure CPU
- **VM.Config.Memory** - Configure memory
- **VM.Config.Network** - Configure network
- **VM.Config.Options** - Configure other options
- **Datastore.AllocateSpace** - Allocate storage
- **Datastore.Audit** - List datastores
- **SDN.Use** - Use network bridges

## Configuration

### 1. Copy Example Configuration

```bash
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit Configuration

Edit `terraform.tfvars`:

```hcl
# Proxmox endpoint
proxmox_endpoint = "https://192.168.1.10:8006"
proxmox_insecure = true  # Change to false with valid SSL cert

# API Token (recommended)
proxmox_api_token = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# OR use username/password (less secure)
# proxmox_username = "root@pam"
# proxmox_password = "your-password"

# Proxmox resources
proxmox_node      = "pve"           # Your Proxmox node name
proxmox_datastore = "local-lvm"     # Storage for VM disks
proxmox_bridge    = "vmbr0"         # Network bridge

# Talos configuration
talos_version = "1.11.5"
cluster_name  = "my-cluster"

# Talos image configuration
# Option 1: Use official Talos ISO (default - leave empty or commented out)
# talos_image_url = ""

# Option 2: Use Omni Factory image (recommended for Omni-managed clusters)
# Use {version} placeholder to automatically use the talos_version variable
# talos_image_url = "https://factory.talos.dev/image/YOUR-SCHEMATIC-ID/v{version}/nocloud-amd64.raw.gz"

# VM configuration
node_count    = 3
node_cpu      = 4
node_memory   = 8192  # MB
node_disk_size = 100  # GB
```

## Deployment

### Initialize Terraform

Initialize Terraform to download the required providers and create the dependency lock file:

```bash
terraform init
```

**Note**: If you encounter `Inconsistent dependency lock file` errors, run `terraform init` first to generate or update the `.terraform.lock.hcl` file.

### Plan Deployment

Review the planned changes before applying:

```bash
terraform plan
```

### Apply Configuration

```bash
terraform apply
```

### View Outputs

```bash
terraform output
```

## What Gets Created

- **VMs**: Number specified in `node_count`
- **Talos Image**: Downloaded to Proxmox automatically (ISO or disk image)
- **Network**: VMs connected to specified bridge
- **Storage**: Disks created on specified datastore
- **Boot**: VMs configured to boot from Talos image

## VM Details

Each VM is created with:
- **Name**: `<cluster_name>-node-<number>`
- **BIOS**: OVMF (UEFI)
- **Boot Order**: SCSI disk, then IDE CD-ROM
- **Network**: Virtio adapter on specified bridge
- **Disk**: Raw format on specified datastore
- **Status**: Started automatically

## After Deployment

### 1. Wait for VMs to Boot

VMs will boot from the Talos ISO (2-5 minutes).

### 2. Check VM Status in Proxmox

```bash
# On Proxmox host
qm list | grep <cluster_name>
```

### 3. Verify Omni Registration

VMs will automatically register with Omni if configured:

```bash
omnictl get machines
```

### 4. Apply Omni Cluster Configuration

```bash
cd ../..
omnictl apply -f clusters/omni/<cluster>.yaml
```

## Troubleshooting

### Dependency Lock File Errors

**Error**: `Inconsistent dependency lock file` or `required by this configuration but no version is selected`

**Solution**:
```bash
terraform init
```

This will download the required providers and generate/update the `.terraform.lock.hcl` file. The lock file ensures consistent provider versions across different environments.

### Authentication Errors

**Error**: `authentication failed`

**Solution**: 
- Verify API token is correct and includes the full string: `USER@REALM!TOKENID=SECRET`
- Check "Privilege Separation" is disabled on the token
- Ensure user has required permissions

### Connection Errors

**Error**: `connection refused` or `timeout`

**Solution**:
- Verify Proxmox endpoint is accessible: `curl -k https://proxmox-ip:8006`
- Check firewall rules allow connection from Terraform host
- Verify Proxmox web UI is running

### SSL Certificate Errors

**Error**: `x509: certificate signed by unknown authority`

**Solution**:
- Set `proxmox_insecure = true` in terraform.tfvars
- Or install proper SSL certificate on Proxmox

### Storage Errors

**Error**: `datastore not found`

**Solution**:
- List available datastores in Proxmox: **Datacenter → Storage**
- Update `proxmox_datastore` in terraform.tfvars
- Ensure datastore has enough free space

### ISO Download Errors

**Error**: `failed to download ISO`

**Solution**:
- Proxmox node needs internet access to download Talos ISO
- Or manually download and upload ISO to Proxmox
- Check Proxmox logs: `/var/log/pveproxy/access.log`

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all VMs and their data!

## Advanced Configuration

### Multiple Clusters

Use Terraform workspaces for multiple clusters:

```bash
# Create workspace for site
terraform workspace new ny1d
terraform workspace select ny1d

# Apply with site-specific tfvars
terraform apply -var-file=terraform.tfvars.ny1d
```

### Custom VM IDs

Edit `vm_id_start` in terraform.tfvars to change starting VM ID:

```hcl
vm_id_start = 8000  # VMs will be 8000, 8001, 8002, etc.
```

### Different Resource Sizes

Adjust resources per VM:

```hcl
node_cpu       = 2      # CPU cores
node_memory    = 4096   # 4GB RAM
node_disk_size = 50     # 50GB disk
```

### Using Omni Factory Images

**Important**: For automatic Omni registration, use an Omni Factory image instead of the standard Talos ISO.

#### What is an Omni Factory Image?

Omni Factory images are custom Talos images built with Omni registration credentials embedded. When VMs boot from these images, they automatically connect to your Omni instance without manual configuration.

**Key differences**:
- **Standard Talos ISO**: Generic Talos that boots into maintenance mode - requires manual configuration
- **Omni Factory Image**: Pre-configured with Omni endpoint and credentials - auto-registers with Omni

#### Getting Your Omni Factory Image URL

1. **Log into your Omni web interface** (e.g., `https://damocles.na-west-1.omni.siderolabs.io`)
2. **Navigate to Download Installation Media**:
   - Settings → Download Installation Media
   - Or Cluster Setup → Add Machines
3. **Select the nocloud format**:
   - Architecture: `amd64`
   - Platform: `nocloud` (for virtualization)
   - Format: Look for `.raw.gz` (gzip compressed)
   - **Extensions**: Add `qemu-guest-agent` for better Proxmox integration (optional but recommended)
4. **Copy the URL** - it will look like:
   ```
   https://factory.talos.dev/image/073e2259a32ece62abb86b02e24925e3d280da6300e9353c412a27be33658d38/v1.11.5/nocloud-amd64.raw.gz
   ```

#### Configure Terraform to Use Omni Image

Add the `talos_image_url` to your `terraform.tfvars`:

```hcl
# Use Omni Factory image for automatic registration
# Use {version} placeholder to automatically substitute talos_version
talos_image_url = "https://factory.talos.dev/image/YOUR-SCHEMATIC-ID/v{version}/nocloud-amd64.raw.gz"
```

**Notes**:
- The image URL is unique to your Omni account and contains embedded credentials
- Use `{version}` placeholder which will be replaced with the `talos_version` variable value
- The `.gz` format is supported (automatically decompressed by Proxmox)
- VMs will use this image as their boot disk instead of an ISO
- Machines will appear in Omni within 2-5 minutes of boot
- The schematic ID in the URL is specific to your Omni configuration

#### Behavior Differences

**With Standard ISO** (`talos_image_url = ""`):
1. VM boots from Talos ISO in CD-ROM drive
2. Talos runs in maintenance mode
3. Requires manual `talosctl` configuration or Omni manual registration
4. Boot order: scsi0 (empty disk), then ide0 (ISO)

**With Omni Factory Image** (`talos_image_url` set):
1. VM boots directly from pre-installed disk image
2. Talos auto-connects to Omni endpoint
3. Machine appears in Omni automatically
4. Ready for cluster assignment
5. Boot order: scsi0 (Omni image disk)

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Talos Documentation](https://www.talos.dev/)
- [Omni Documentation](https://omni.siderolabs.com/docs)
