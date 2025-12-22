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

# Download Talos/Omni image to Proxmox (skip if using pre-downloaded Omni ISO)
resource "proxmox_virtual_environment_download_file" "talos_image" {
  count = var.use_omni_iso ? 0 : 1

  content_type            = "iso"
  datastore_id            = var.proxmox_iso_storage
  node_name               = var.proxmox_node
  url                     = var.talos_image_url != "" ? replace(replace(var.talos_image_url, "{version}", var.talos_version), "{factory_id}", var.talos_factory_id) : "https://github.com/siderolabs/talos/releases/download/v${var.talos_version}/metal-amd64.iso"
  file_name               = var.talos_image_url != "" ? "talos-omni-${var.cluster_name}.img" : null
  decompression_algorithm = var.talos_image_url != "" ? "gz" : null

  # Only download if not already present
  lifecycle {
    ignore_changes = [url]
  }
}

# Create Talos VMs
resource "proxmox_virtual_environment_vm" "talos_node" {
  count = var.node_count

  name        = "${var.cluster_name}-node-${count.index + 1}"
  description = "Talos node for ${var.cluster_name}"
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_start + count.index

  # Boot from Talos image (ISO or disk image)
  dynamic "cdrom" {
    for_each = var.talos_image_url == "" ? [1] : []
    content {
      file_id   = var.use_omni_iso ? "${var.proxmox_iso_storage}:iso/${var.omni_iso_name}" : proxmox_virtual_environment_download_file.talos_image[0].id
      interface = "ide0"
    }
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
    file_id      = var.talos_image_url != "" && !var.use_omni_iso ? proxmox_virtual_environment_download_file.talos_image[0].id : null
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
