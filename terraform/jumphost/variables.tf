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
  description = "vSphere resource pool name (format: cluster/Resources or cluster/Resources/pool-name)"
  type        = string
}

variable "vsphere_folder" {
  description = "vSphere VM folder path"
  type        = string
  default     = ""
}

variable "ubuntu_template" {
  description = "Name of Ubuntu template/OVA in vSphere (e.g., ubuntu-22.04-cloud)"
  type        = string
}

variable "jumphost_hostname" {
  description = "Hostname for the jumphost VM"
  type        = string
  default     = "talos-jumphost"
}

variable "jumphost_cpu" {
  description = "Number of CPUs for jumphost"
  type        = number
  default     = 2
}

variable "jumphost_memory" {
  description = "Memory in MB for jumphost"
  type        = number
  default     = 4096
}

variable "jumphost_disk_size" {
  description = "Disk size in GB for jumphost"
  type        = number
  default     = 50
}

variable "jumphost_username" {
  description = "Default username for jumphost"
  type        = string
  default     = "ubuntu"
}

variable "jumphost_ssh_keys" {
  description = "List of SSH public keys to add to authorized_keys"
  type        = list(string)
}

variable "jumphost_timezone" {
  description = "Timezone for jumphost"
  type        = string
  default     = "UTC"
}
