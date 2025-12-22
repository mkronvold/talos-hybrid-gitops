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
  
  # Flatten vm_configs into individual VM specifications
  # Each VM gets: unique name, vm_id, cpu, memory, disk, role
  vms = flatten([
    for config_idx, config in var.vm_configs : [
      for vm_idx in range(config.count) : {
        # Calculate cumulative VM index across all configs
        global_idx = sum([for i in range(config_idx) : var.vm_configs[i].count]) + vm_idx
        # VM naming: cluster-role-number (e.g., dk1d-controlplane-1, dk1d-worker-1)
        name       = "${var.cluster_name}-${config.role}-${vm_idx + 1}"
        vm_id      = var.vm_id_start + sum([for i in range(config_idx) : var.vm_configs[i].count]) + vm_idx
        cpu        = config.cpu
        memory     = config.memory
        disk       = config.disk
        role       = config.role
      }
    ]
  ])
  
  # Create a map for easier lookup
  vms_map = { for vm in local.vms : vm.global_idx => vm }
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

# Create Talos VMs using Omni ISO with multi-size configuration support
# ISO must be prepared first using: ./scripts/prepare-omni-iso.sh <site-code>
resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = local.vms_map

  name        = each.value.name
  description = "Talos ${each.value.role} node for ${var.cluster_name} (Omni-managed)"
  node_name   = var.proxmox_node
  vm_id       = each.value.vm_id

  # Boot from Omni ISO
  cdrom {
    file_id   = "${var.proxmox_iso_storage}:iso/${var.omni_iso_name}"
    interface = "ide0"
  }

  # CPU configuration (per-VM)
  cpu {
    cores   = each.value.cpu
    sockets = 1
    type    = "host"
  }

  # Memory configuration (per-VM)
  memory {
    dedicated = each.value.memory
  }

  # Network configuration
  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }

  # Disk configuration (per-VM)
  disk {
    datastore_id = var.proxmox_datastore
    interface    = "scsi0"
    size         = each.value.disk
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
  value       = [for vm in proxmox_virtual_environment_vm.talos_node : vm.name]
}

output "vm_ids" {
  description = "Proxmox VM IDs"
  value       = [for vm in proxmox_virtual_environment_vm.talos_node : vm.vm_id]
}

output "vm_ips" {
  description = "IP addresses of VMs (if available via agent)"
  value       = [for vm in proxmox_virtual_environment_vm.talos_node : vm.ipv4_addresses]
}

output "vm_configs_summary" {
  description = "Summary of VM configurations"
  value = {
    total_vms = length(local.vms)
    configs = [
      for config in var.vm_configs : {
        role   = config.role
        count  = config.count
        cpu    = config.cpu
        memory = "${config.memory}MB"
        disk   = "${config.disk}GB"
      }
    ]
  }
}

output "omni_registration_info" {
  description = "Information needed for Omni machine registration"
  value = {
    cluster_name = var.cluster_name
    total_vms    = length(local.vms)
    vms = [
      for vm in proxmox_virtual_environment_vm.talos_node : {
        name = vm.name
        id   = vm.vm_id
      }
    ]
  }
}
