terraform {
  required_version = ">= 1.5"
  
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_insecure
}

# Data sources to locate vSphere resources
data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.vsphere_resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Ubuntu template/OVA
data "vsphere_virtual_machine" "ubuntu_template" {
  name          = var.ubuntu_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Cloud-init user data
locals {
  cloud_init_user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    hostname   = var.jumphost_hostname
    username   = var.jumphost_username
    ssh_keys   = var.jumphost_ssh_keys
    timezone   = var.jumphost_timezone
  }))
}

# Jumphost VM
resource "vsphere_virtual_machine" "jumphost" {
  name             = var.jumphost_hostname
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder
  
  num_cpus = var.jumphost_cpu
  memory   = var.jumphost_memory
  guest_id = data.vsphere_virtual_machine.ubuntu_template.guest_id
  
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.ubuntu_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = var.jumphost_disk_size
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.ubuntu_template.id
  }
  
  vapp {
    properties = {
      "user-data" = local.cloud_init_user_data
    }
  }
  
  lifecycle {
    ignore_changes = [
      vapp[0].properties,
    ]
  }
}

# Output jumphost IP
output "jumphost_ip" {
  description = "IP address of the jumphost"
  value       = vsphere_virtual_machine.jumphost.default_ip_address
}

output "jumphost_name" {
  description = "Name of the jumphost VM"
  value       = vsphere_virtual_machine.jumphost.name
}

output "ssh_command" {
  description = "SSH command to connect to jumphost"
  value       = "ssh ${var.jumphost_username}@${vsphere_virtual_machine.jumphost.default_ip_address}"
}
