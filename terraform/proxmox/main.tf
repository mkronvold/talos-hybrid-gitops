terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

locals {
  # Workaround for Terraform v1.6.0 bug with sensitive values in conditionals
  ssh_private_key = var.proxmox_ssh_private_key_file != "" ? file(var.proxmox_ssh_private_key_file) : nonsensitive(var.proxmox_ssh_private_key)
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  username  = var.proxmox_username
  password  = var.proxmox_password
  insecure  = var.proxmox_insecure

  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = local.ssh_private_key
  }
}

# Create Talos VMs using Omni ISO
# ISO must be prepared first using: ./scripts/prepare-omni-iso.sh <site-code>
resource "proxmox_virtual_environment_vm" "talos_node" {
  count = var.node_count

  name        = "${var.cluster_name}-node-${count.index + 1}"
  description = "Talos node for ${var.cluster_name} (Omni-managed)"
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_start + count.index

  # Boot from Omni ISO
  cdrom {
    file_id   = "${var.proxmox_iso_storage}:iso/${var.omni_iso_name}"
    interface = "ide0"
  }

  # CPU configuration
  cpu {
    cores   = var.node_cpu
    sockets = 1
    type    = "host"
  }

  # Memory configuration
  memory {
    dedicated = var.node_memory
  }

  # Network configuration
  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }

  # Disk configuration
  disk {
    datastore_id = var.proxmox_datastore
    interface    = "scsi0"
    size         = var.node_disk_size
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  # BIOS and boot configuration
  bios = "ovmf"

  efi_disk {
    datastore_id = var.proxmox_datastore
    file_format  = "raw"
    type         = "4m"
  }

  boot_order = ["scsi0", "ide0"]

  # Agent configuration
  agent {
    enabled = false # Talos doesn't use QEMU agent
  }

  # Start VM after creation
  started = true

  # Prevent Proxmox from managing some settings
  lifecycle {
    ignore_changes = [
      network_device, # Omni will manage network config
    ]
  }
}

# Output VM information for Omni registration
output "vm_names" {
  description = "Names of created VMs"
  value       = proxmox_virtual_environment_vm.talos_node[*].name
}

output "vm_ids" {
  description = "Proxmox VM IDs"
  value       = proxmox_virtual_environment_vm.talos_node[*].vm_id
}

output "vm_ips" {
  description = "IP addresses of VMs (if available via agent)"
  value       = proxmox_virtual_environment_vm.talos_node[*].ipv4_addresses
}

output "omni_registration_info" {
  description = "Information needed for Omni machine registration"
  value = {
    cluster_name = var.cluster_name
    node_count   = var.node_count
    nodes = [
      for i, vm in proxmox_virtual_environment_vm.talos_node : {
        name = vm.name
        id   = vm.vm_id
      }
    ]
  }
}
