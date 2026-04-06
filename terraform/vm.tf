# Vendor data snippet (replaces roles/proxmox/vm/templates/vendor.yml.j2)
resource "proxmox_virtual_environment_file" "vendor_data" {
  for_each = {
    for name, cfg in local.active_vm :
    name => cfg
    if lookup(cfg, "vendor_data_enabled", false)
  }

  content_type = "snippets"
  datastore_id = each.value.vendor_data_storage
  node_name    = var.pve_node_name

  source_raw {
    data = templatefile("${path.module}/templates/vendor.yml.tftpl", {
      disks = each.value.disks
    })
    file_name = "vendor-${each.key}.yml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.active_vm

  node_name   = var.pve_node_name
  vm_id       = each.value.vmid
  name        = each.key
  description = each.value.description
  tags        = each.value.tags

  on_boot         = each.value.start_on_boot
  started         = true
  machine         = each.value.machine
  bios            = each.value.bios
  scsi_hardware   = each.value.scsi_hardware
  keyboard_layout = "en-us"
  tablet_device   = true
  acpi            = true
  stop_on_destroy = true

  startup {
    order = each.value.startup_order
  }

  agent {
    enabled = true
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.balloon
  }

  # Boot disk — cloud image import
  disk {
    datastore_id = each.value.storage
    import_from  = proxmox_download_file.debian_13_cloud.id
    interface    = "scsi0"
    size         = each.value.disks[0].size
    cache        = each.value.disks[0].cache
    ssd          = each.value.disks[0].ssd
    discard      = each.value.disks[0].discard
    iothread     = each.value.disks[0].iothread
    backup       = lookup(each.value.disks[0], "backup", true)
  }

  # Additional disks
  dynamic "disk" {
    for_each = slice(each.value.disks, 1, length(each.value.disks))
    content {
      datastore_id = each.value.storage
      interface    = "scsi${disk.key + 1}"
      size         = disk.value.size
      cache        = disk.value.cache
      ssd          = disk.value.ssd
      discard      = disk.value.discard
      iothread     = disk.value.iothread
      backup       = lookup(disk.value, "backup", true)
    }
  }

  network_device {
    bridge   = each.value.network.bridge
    model    = lookup(each.value.network, "model", "virtio")
    vlan_id  = lookup(each.value.network, "vlan_id", null)
    firewall = lookup(each.value.network, "firewall", false)
  }

  initialization {
    datastore_id = lookup(each.value.cloudinit, "datastore", null)

    ip_config {
      ipv4 {
        address = each.value.cloudinit.ip
      }
    }

    dns {
      servers = each.value.cloudinit.nameserver != "" ? [each.value.cloudinit.nameserver] : null
      domain  = lookup(each.value.cloudinit, "domain", null)
    }

    user_account {
      username = each.value.cloudinit.user
      password = each.value.cloudinit.password
      keys     = local.ssh_keys
    }

    vendor_data_file_id = lookup(each.value, "vendor_data_enabled", false) ? proxmox_virtual_environment_file.vendor_data[each.key].id : null
  }

  serial_device {}

  vga {
    type = each.value.vga
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = false
  }
}
