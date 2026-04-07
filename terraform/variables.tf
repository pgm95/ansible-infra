variable "pve_download_storage" {
  description = "Proxmox datastore for templates and images"
  type        = string
}

variable "pve_node_name" {
  description = "Proxmox cluster node name"
  type        = string
}

variable "pve_host_addr" {
  description = "Proxmox host address for SSH"
  type        = string
}

variable "universal_pass" {
  description = "Universal password for root accounts"
  type        = string
  sensitive   = true
}

variable "ssh_authorized_keys" {
  description = "SSH public keys (newline-delimited string)"
  type        = string
  sensitive   = true
}
