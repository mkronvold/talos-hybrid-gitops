terraform {
  required_version = ">= 1.5"
  
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
  
  # Recommended: Use remote state
  # backend "s3" {
  #   bucket = "terraform-state"
  #   key    = "talos/vsphere/terraform.tfstate"
  #   region = "us-east-1"
  # }
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

# Talos ISO/OVA template (pre-uploaded)
data "vsphere_virtual_machine" "talos_template" {
  name          = var.talos_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Create VMs for Talos cluster
resource "vsphere_virtual_machine" "talos_node" {
  count = var.node_count

  name             = "${var.cluster_name}-node-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = var.node_cpu
  memory   = var.node_memory
  guest_id = data.vsphere_virtual_machine.talos_template.guest_id

  # Network configuration
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.talos_template.network_interface_types[0]
  }

  # Boot disk
  disk {
    label            = "disk0"
    size             = var.node_disk_size
    thin_provisioned = true
  }

  # Clone from Talos template
  clone {
    template_uuid = data.vsphere_virtual_machine.talos_template.id
  }

  # Extra config for Talos
  extra_config = {
    "guestinfo.talos.config" = ""  # Will be configured by Omni
  }

  lifecycle {
    ignore_changes = [
      extra_config,  # Omni will manage Talos config
    ]
  }
}

# Output VM information for Omni registration
output "vm_names" {
  description = "Names of created VMs"
  value       = vsphere_virtual_machine.talos_node[*].name
}

output "vm_uuids" {
  description = "UUIDs of created VMs"
  value       = vsphere_virtual_machine.talos_node[*].uuid
}

output "vm_ips" {
  description = "IP addresses of VMs (if available)"
  value       = vsphere_virtual_machine.talos_node[*].default_ip_address
}

output "omni_registration_info" {
  description = "Information needed for Omni machine registration"
  value = {
    cluster_name = var.cluster_name
    node_count   = var.node_count
    nodes = [
      for i, vm in vsphere_virtual_machine.talos_node : {
        name = vm.name
        uuid = vm.uuid
      }
    ]
  }
}
