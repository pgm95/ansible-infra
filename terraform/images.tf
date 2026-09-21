# For LXC: Verify via `pveam available` on the PVE host.
#
# Each download is gated on `local.used_lxc_os` / `local.used_vm_os`, which are
# derived from the workspace-filtered guest definitions. A node only stores the
# images its own guests reference; adding the first guest of a new OS pulls the
# image in, removing the last one drops it.

resource "proxmox_download_file" "debian_13_lxc" {
  count        = contains(local.used_lxc_os, "debian-13") ? 1 : 0
  content_type = "vztmpl"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  overwrite    = false
}

resource "proxmox_download_file" "debian_13_cloud" {
  count        = contains(local.used_vm_os, "debian-13") ? 1 : 0
  content_type = "import"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "https://cdimage.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw"
  file_name    = "debian-13-genericcloud-amd64.raw"
  overwrite    = false
}

resource "proxmox_download_file" "ubuntu_26_cloud" {
  count        = contains(local.used_vm_os, "ubuntu-26") ? 1 : 0
  content_type = "import"
  datastore_id = var.pve_download_storage
  node_name    = var.pve_node_name
  url          = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
  # Ubuntu ships QCOW2 with a .img name; Proxmox `import` rejects .img, so store it as .qcow2.
  file_name = "ubuntu-26-server-cloudimg-amd64.qcow2"
  overwrite = false
}
