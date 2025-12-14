variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_user" {
  description = "Proxmox API user"
  type        = string
  sensitive   = true
}

variable "proxmox_api_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Allow insecure TLS connections"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_storage" {
  description = "Proxmox storage pool"
  type        = string
}

variable "proxmox_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ubuntu_template_id" {
  description = "Ubuntu cloud image template VM ID in Proxmox"
  type        = number
}

variable "jumphost_hostname" {
  description = "Hostname for the jumphost VM"
  type        = string
  default     = "talos-jumphost"
}

variable "jumphost_cpu" {
  description = "Number of CPU cores for jumphost"
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
