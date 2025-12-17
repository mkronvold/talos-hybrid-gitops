terraform {
  required_version = ">= 1.5"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.60.1"  # Specific version to avoid SSL bugs in 0.89.x
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null
  username  = var.proxmox_api_token == "" ? var.proxmox_username : null
  password  = var.proxmox_api_token == "" ? var.proxmox_password : null
  insecure  = true  # Hardcoded to bypass SSL verification issues
}

# Cloud-init user data
locals {
  cloud_init_user_data = templatefile("${path.module}/cloud-init.yaml", {
    hostname   = var.jumphost_hostname
    username   = var.jumphost_username
    ssh_keys   = var.jumphost_ssh_keys
    timezone   = var.jumphost_timezone
  })
}

# Jumphost VM
resource "proxmox_virtual_environment_vm" "jumphost" {
  name      = var.jumphost_hostname
  node_name = var.proxmox_node
  
  cpu {
    cores = var.jumphost_cpu
    type  = "host"
  }
  
  memory {
    dedicated = var.jumphost_memory
  }
  
  # Clone from Ubuntu cloud image template
  clone {
    vm_id = var.ubuntu_template_id
    full  = true
  }
  
  # Disk configuration
  disk {
    datastore_id = var.proxmox_datastore
    interface    = "scsi0"
    size         = var.jumphost_disk_size
    file_format  = "raw"
  }
  
  # Network configuration
  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }
  
  # Cloud-init configuration (basic user setup only)
  initialization {
    datastore_id = var.proxmox_datastore
    
    user_account {
      username = var.jumphost_username
      keys     = var.jumphost_ssh_keys
    }
    
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
  
  # Wait for network
  on_boot = true
  started = true
}

# Wait for cloud-init to complete
resource "null_resource" "wait_for_cloud_init" {
  depends_on = [proxmox_virtual_environment_vm.jumphost]
  
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

# Outputs
output "jumphost_ip" {
  description = "IP address of the jumphost"
  value       = try(proxmox_virtual_environment_vm.jumphost.ipv4_addresses[1][0], "pending")
}

output "jumphost_name" {
  description = "Name of the jumphost VM"
  value       = proxmox_virtual_environment_vm.jumphost.name
}

output "ssh_command" {
  description = "SSH command to connect to jumphost"
  value       = "ssh ${var.jumphost_username}@${try(proxmox_virtual_environment_vm.jumphost.ipv4_addresses[1][0], "pending")}"
}

output "setup_instructions" {
  description = "Post-deployment setup instructions"
  value       = <<-EOT
    Basic VM created. To complete jumphost setup, SSH in and run:
    
    ssh ${var.jumphost_username}@${try(proxmox_virtual_environment_vm.jumphost.ipv4_addresses[1][0], "pending")}
    
    Then run the setup scripts:
    git clone https://github.com/mkronvold/talos-hybrid-gitops.git
    cd talos-hybrid-gitops
    ./scripts/install-dependencies.sh
    ./scripts/install-node-copilot.sh
  EOT
}
