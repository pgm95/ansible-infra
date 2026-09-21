resource "proxmox_virtual_environment_container" "lxc" {
  for_each = local.active_lxc

  node_name   = var.pve_node_name
  vm_id       = each.value.vm_id
  description = each.value.description
  tags        = each.value.tags

  unprivileged  = true
  start_on_boot = each.value.start_on_boot
  started       = lookup(each.value, "started", true)

  startup {
    order = each.value.startup_order
  }

  cpu {
    architecture = "amd64"
    cores        = each.value.cores
  }

  memory {
    dedicated = each.value.memory.dedicated
    swap      = each.value.memory.swap
  }

  operating_system {
    template_file_id = local.os_template[each.value.os_version]
    type             = "debian"
  }

  # Console
  console {
    enabled   = true
    type      = "shell"
    tty_count = 0
  }

  # Features
  features {
    fuse    = try(each.value.features.fuse, null)
    nesting = try(each.value.features.nesting, null)
    keyctl  = try(each.value.features.keyctl, null)
  }

  # Rootfs disk (first entry)
  disk {
    datastore_id = each.value.disk_datastore_id != "" ? each.value.disk_datastore_id : null
    size         = each.value.disks[0].size
  }

  # Additional storage mount points (disks after index 0 that have mp),
  # allocated by and owned by this container.
  dynamic "mount_point" {
    for_each = [
      for i, d in slice(each.value.disks, 1, length(each.value.disks)) : d
      if lookup(d, "mp", "") != "" && !lookup(d, "floating", false)
    ]
    content {
      volume = "${each.value.disk_datastore_id}:${mount_point.value.size}"
      path   = mount_point.value.mp
      size   = "${mount_point.value.size}G"
      backup = lookup(mount_point.value, "backup", true)
    }
  }

  # Floating storage mount points: owned by the data holder, attached by
  # volume id. Destroying or replacing this container leaves them untouched.
  dynamic "mount_point" {
    for_each = [
      for i, d in slice(each.value.disks, 1, length(each.value.disks)) : d
      if lookup(d, "mp", "") != "" && lookup(d, "floating", false)
    ]
    content {
      volume = local.lxc_holder_volumes["/${each.key}${mount_point.value.mp}"]
      path   = mount_point.value.mp
      size   = "${mount_point.value.size}G"
      backup = lookup(mount_point.value, "backup", true)
    }
  }

  # Bind mounts
  dynamic "mount_point" {
    for_each = try(each.value.bind_mounts, [])
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.path
    }
  }

  # Device passthrough
  dynamic "device_passthrough" {
    for_each = each.value.devices
    content {
      path = device_passthrough.value.path
      gid  = lookup(device_passthrough.value, "gid", null)
      uid  = lookup(device_passthrough.value, "uid", null)
    }
  }

  # UID/GID idmap - 1:1 mapping for a single uid/gid
  # Generates the standard 6-entry idmap:
  #   u 0 100000 <uid>        g 0 100000 <gid>
  #   u <uid> <uid> 1         g <gid> <gid> 1
  #   u <uid+1> 100000+<uid+1> N   g <gid+1> 100000+<gid+1> N
  dynamic "idmap" {
    for_each = lookup(each.value, "idmap_uid", null) != null ? [
      { type = "uid", container_id = 0, host_id = 100000, size = each.value.idmap_uid },
      { type = "uid", container_id = each.value.idmap_uid, host_id = each.value.idmap_uid, size = 1 },
      { type = "uid", container_id = each.value.idmap_uid + 1, host_id = 100000 + each.value.idmap_uid + 1, size = 65536 - each.value.idmap_uid - 1 },
      { type = "gid", container_id = 0, host_id = 100000, size = each.value.idmap_gid },
      { type = "gid", container_id = each.value.idmap_gid, host_id = each.value.idmap_gid, size = 1 },
      { type = "gid", container_id = each.value.idmap_gid + 1, host_id = 100000 + each.value.idmap_gid + 1, size = 65536 - each.value.idmap_gid - 1 },
    ] : []
    content {
      type         = idmap.value.type
      container_id = idmap.value.container_id
      host_id      = idmap.value.host_id
      size         = idmap.value.size
    }
  }

  # Network
  network_interface {
    name        = "eth0"
    bridge      = each.value.network.bridge
    vlan_id     = lookup(each.value.network, "vlan_id", null)
    mac_address = lookup(each.value.network, "mac_address", null)
    firewall    = false
  }

  # Initialization
  initialization {
    hostname = each.key
    # domain drives the FQDN Proxmox writes into the container's /etc/hosts.
    # Resolution itself comes from DHCP; servers stays unset unless a guest
    # explicitly overrides it.
    dns {
      domain  = local.lxc_domain[each.key]
      servers = try(each.value.dns.servers, "") != "" ? [each.value.dns.servers] : null
    }
    ip_config {
      ipv4 {
        address = each.value.network.address
      }
      # ipv6 omitted: empty values cause perpetual diff (API does not persist)
      # ipv6 {
      #   address = ""
      #   gateway = ""
      # }
    }
    user_account {
      password = each.value.password
      keys     = local.ssh_keys
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Data holder: a never-started container that owns every floating LXC volume in
# this workspace. Guests attach the volumes by id; Proxmox refuses to free a
# volume whose owner id differs from the guest being destroyed. The template
# and rootfs exist only because Proxmox cannot create a container without them,
# so they are ignored after creation: neither a template bump nor an import
# mismatch may ever replace the holder.
resource "proxmox_virtual_environment_container" "data_holder" {
  for_each = length(local.lxc_floating) > 0 ? { holder = true } : {}

  node_name   = var.pve_node_name
  vm_id       = local.data_holder_lxc_id
  description = "Floating data volumes (LXC)"
  tags        = ["terraform", "data-holder"]

  unprivileged  = true
  start_on_boot = false
  started       = false

  operating_system {
    template_file_id = local.os_template[local.data_holder_os]
    type             = "debian"
  }

  disk {
    datastore_id = local.lxc_holder_datastore
    size         = 2
  }

  # Slot order is list order: mp<slot>. Slots must therefore be contiguous
  # from 0 on the LXC holder (checked below).
  dynamic "mount_point" {
    for_each = local.lxc_floating_by_slot
    content {
      volume = "${mount_point.value.datastore_id}:${mount_point.value.size}"
      path   = mount_point.value.holder_path
      size   = "${mount_point.value.size}G"
      backup = false
    }
  }

  initialization {
    hostname = "data-holder-lxc"
  }

  lifecycle {
    ignore_changes = [operating_system, disk]

    precondition {
      condition = alltrue([
        for i in range(length(local.lxc_floating_by_slot)) : local.lxc_floating_by_slot[i].slot == i
      ])
      error_message = "LXC floating disk slots must be unique and contiguous from 0 (got: ${join(", ", [for f in local.lxc_floating_by_slot : "${f.guest}=${f.slot}"])})."
    }
  }
}
