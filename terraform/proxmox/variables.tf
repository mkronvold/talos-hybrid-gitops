variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username (e.g., root@pam) - used with password auth"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox password - used with username/password auth"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_api_token" {
  description = "Proxmox API token (recommended) - format: USER@REALM!TOKENID=UUID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Allow insecure SSL connections"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_datastore" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_iso_storage" {
  description = "Proxmox storage for ISO files (must be file-based, e.g., local)"
  type        = string
  default     = "local"
}

variable "proxmox_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "talos_version" {
  description = "Talos version to download"
  type        = string
  default     = "1.9.5"
}

variable "talos_image_url" {
  description = "URL to Talos/Omni Factory image (raw.gz format). Use {version} placeholder to auto-substitute talos_version."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "vm_id_start" {
  description = "Starting VM ID for Proxmox"
  type        = number
  default     = 8000
}

variable "node_count" {
  description = "Number of nodes to create"
  type        = number
  default     = 3
}

variable "node_cpu" {
  description = "Number of CPU cores per node"
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
