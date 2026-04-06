terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100"
    }
  }
}

provider "proxmox" {
  # PROXMOX_VE_ENDPOINT, PROXMOX_VE_USERNAME, PROXMOX_VE_PASSWORD
  # sourced from environment (mise profile + SOPS)
  insecure = true

  ssh {
    agent = true
    node {
      name    = var.pve_node_name
      address = var.pve_host_addr
    }
  }
}
