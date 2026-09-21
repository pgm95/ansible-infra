# Vendor data snippet
resource "proxmox_virtual_environment_file" "vendor_data" {
  for_each = {
    for name, cfg in local.active_vm :
    name => cfg
    if lookup(cfg, "vendor_data_enabled", false)
  }

  content_type = "snippets"
  datastore_id = each.value.vendor_datastore_id
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
  vm_id       = each.value.vm_id
  name        = each.key
  description = each.value.description
  tags        = each.value.tags

  on_boot         = each.value.on_boot
  started         = lookup(each.value, "started", true)
  machine         = each.value.machine
  bios            = each.value.bios
  scsi_hardware   = each.value.scsi_hardware
  keyboard_layout = "en-us"
  tablet_device   = false
  acpi            = true
  stop_on_destroy = true
  kvm_arguments   = lookup(each.value, "kvm_arguments", null)

  startup {
    order = each.value.startup_order
  }

  agent {
    enabled = true
  }

  cpu {
    architecture = "x86_64"
    cores        = each.value.cores
    sockets      = 1
    type         = "host"
    numa         = lookup(each.value, "numa", false)
  }

  memory {
    dedicated = each.value.memory.dedicated
    floating  = each.value.memory.floating
  }

  # Boot disk - cloud image import
  disk {
    datastore_id = each.value.disk_datastore_id
    import_from  = local.vm_cloud_image[each.value.os]
    interface    = "scsi0"
    size         = each.value.disks[0].size
    cache        = each.value.disks[0].cache
    ssd          = each.value.disks[0].ssd
    discard      = each.value.disks[0].discard
    iothread     = each.value.disks[0].iothread
    backup       = lookup(each.value.disks[0], "backup", true)
  }

  # Additional disks. A floating entry attaches the data holder's disk by
  # path instead of allocating one; it keeps its own scsi index so the by-id
  # device path in the vendor data stays valid across rebuilds.
  dynamic "disk" {
    for_each = slice(each.value.disks, 1, length(each.value.disks))
    content {
      datastore_id      = lookup(disk.value, "floating", false) ? local.vm_floating["${each.key}/${disk.value.slot}"].datastore_id : each.value.disk_datastore_id
      path_in_datastore = try(local.vm_holder_disks["scsi${disk.value.slot}"].path_in_datastore, null)
      file_format       = try(local.vm_holder_disks["scsi${disk.value.slot}"].file_format, null)
      interface         = "scsi${disk.key + 1}"
      size              = disk.value.size
      cache             = disk.value.cache
      ssd               = disk.value.ssd
      discard           = disk.value.discard
      iothread          = disk.value.iothread
      backup            = lookup(disk.value, "backup", true)
    }
  }

  # Required by Proxmox when bios = ovmf
  dynamic "efi_disk" {
    for_each = each.value.bios == "ovmf" ? [1] : []
    content {
      datastore_id = each.value.disk_datastore_id
      type         = lookup(each.value, "efi_type", "4m")
    }
  }

  dynamic "hostpci" {
    for_each = lookup(each.value, "hostpci", [])
    content {
      device  = "hostpci${hostpci.key}"
      mapping = hostpci.value.mapping
      pcie    = lookup(hostpci.value, "pcie", true)
      rombar  = lookup(hostpci.value, "rombar", false)
    }
  }

  network_device {
    bridge      = each.value.network.bridge
    model       = lookup(each.value.network, "model", "virtio")
    vlan_id     = lookup(each.value.network, "vlan_id", null)
    mac_address = lookup(each.value.network, "mac_address", null)
    firewall    = false
  }

  initialization {
    datastore_id = lookup(each.value.cloudinit, "datastore_id", null)

    ip_config {
      ipv4 {
        address = each.value.cloudinit.address
      }
    }

    # Render dns only when set; an empty dns block is a perpetual diff under DHCP.
    # domain feeds the cloud-init `fqdn:` Proxmox generates, which is what lands
    # in /etc/hosts. Resolution itself comes from DHCP.
    dynamic "dns" {
      for_each = (lookup(each.value.cloudinit, "servers", "") != "" || local.vm_domain[each.key] != null) ? [1] : []
      content {
        servers = lookup(each.value.cloudinit, "servers", "") != "" ? [each.value.cloudinit.servers] : null
        domain  = local.vm_domain[each.key]
      }
    }

    user_account {
      username = each.value.cloudinit.username
      password = each.value.cloudinit.password
      keys     = local.ssh_keys
    }

    vendor_data_file_id = lookup(each.value, "vendor_data_enabled", false) ? proxmox_virtual_environment_file.vendor_data[each.key].id : null
  }

  serial_device {
    device = "socket"
  }

  # root@pam only
  dynamic "rng" {
    for_each = lookup(each.value, "rng_source", null) != null ? [each.value.rng_source] : []
    content {
      source = rng.value
    }
  }

  vga {
    type = "serial0"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = false
    # Vendor cloud-init is consumed only at first boot
    # re-rendering the template must never recreate a live VM
    ignore_changes = [initialization[0].vendor_data_file_id]
  }
}

# Data holder: a never-started VM with no OS that owns every floating VM disk in
# this workspace. Guests attach the disks by path; Proxmox refuses to free a
# disk whose owner id differs from the guest being destroyed. Disk flags mirror
# the guest entry so an imported, reassigned disk is diff-free.
resource "proxmox_virtual_environment_vm" "data_holder" {
  for_each = length(local.vm_floating) > 0 ? { holder = true } : {}

  node_name   = var.pve_node_name
  vm_id       = local.data_holder_vm_id
  name        = "data-holder-vm"
  description = "Floating data volumes (VM)"
  tags        = ["terraform", "data-holder"]

  started = false
  on_boot = false

  agent {
    enabled = false
  }

  dynamic "disk" {
    for_each = local.vm_floating_by_slot
    content {
      datastore_id = disk.value.datastore_id
      interface    = "scsi${disk.value.slot}"
      size         = disk.value.size
      cache        = disk.value.cache
      ssd          = disk.value.ssd
      discard      = disk.value.discard
      iothread     = disk.value.iothread
      backup       = false
    }
  }

  lifecycle {
    precondition {
      condition     = length(distinct([for f in local.vm_floating_by_slot : f.slot])) == length(local.vm_floating_by_slot)
      error_message = "VM floating disk slots must be unique (got: ${join(", ", [for f in local.vm_floating_by_slot : "${f.guest}=${f.slot}"])})."
    }
  }
}
