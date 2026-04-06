# For LXC: Verify via `pveam available` on the PVE host.

resource "proxmox_download_file" "debian_12_lxc" {
  content_type = "vztmpl"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
  overwrite    = false
}

resource "proxmox_download_file" "debian_13_lxc" {
  content_type = "vztmpl"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  overwrite    = false
}

resource "proxmox_download_file" "debian_13_cloud" {
  content_type = "import"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw"
  file_name    = "debian-13-genericcloud-amd64.raw"
  overwrite    = false
}
