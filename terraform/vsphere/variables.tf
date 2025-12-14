variable "vsphere_user" {
  description = "vSphere username"
  type        = string
  sensitive   = true
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "vSphere server address"
  type        = string
}

variable "vsphere_insecure" {
  description = "Allow insecure SSL connections"
  type        = bool
  default     = false
}

variable "vsphere_datacenter" {
  description = "vSphere datacenter name"
  type        = string
}

variable "vsphere_datastore" {
  description = "vSphere datastore name"
  type        = string
}

variable "vsphere_cluster" {
  description = "vSphere cluster name"
  type        = string
}

variable "vsphere_network" {
  description = "vSphere network name"
  type        = string
}

variable "vsphere_resource_pool" {
  description = "vSphere resource pool"
  type        = string
  default     = ""
}

variable "vsphere_folder" {
  description = "vSphere folder for VMs"
  type        = string
  default     = ""
}

variable "talos_template_name" {
  description = "Name of the Talos OVA template in vSphere"
  type        = string
  default     = "talos-v1.9.5"
}

variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "node_count" {
  description = "Number of nodes to create"
  type        = number
  default     = 3
}

variable "node_cpu" {
  description = "Number of CPUs per node"
  type        = number
  default     = 4
}

variable "node_memory" {
  description = "Memory per node in MB"
  type        = number
  default     = 8192
}

variable "node_disk_size" {
  description = "Disk size per node in GB"
  type        = number
  default     = 100
}
