resource "proxmox_virtual_environment_container" "lxc" {
  for_each = local.active_lxc

  node_name   = var.pve_node_name
  vm_id       = each.value.vmid
  description = each.value.description
  tags        = each.value.tags

  unprivileged  = true
  start_on_boot = each.value.start_on_boot
  started       = true

  startup {
    order = each.value.startup_order
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  operating_system {
    template_file_id = local.os_template[each.value.os_version]
    type             = "debian"
  }

  # Console
  console {
    type      = "shell"
    tty_count = 0
  }

  # Features
  features {
    fuse    = each.value.features.fuse
    nesting = each.value.features.nesting
    keyctl  = each.value.features.keyctl
  }

  # Rootfs disk (first entry)
  disk {
    datastore_id = each.value.storage != "" ? each.value.storage : null
    size         = each.value.disks[0].size
  }

  # Additional storage mount points (disks after index 0 that have mp)
  dynamic "mount_point" {
    for_each = [
      for i, d in slice(each.value.disks, 1, length(each.value.disks)) : d
      if lookup(d, "mp", "") != ""
    ]
    content {
      volume = "${each.value.storage}:${mount_point.value.size}"
      path   = mount_point.value.mp
      size   = "${mount_point.value.size}G"
    }
  }

  # Bind mounts
  dynamic "mount_point" {
    for_each = each.value.bind_mounts
    content {
      volume = mount_point.value.source
      path   = mount_point.value.target
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
  }

  # Initialization
  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.network.ip
      }
    }

    user_account {
      password = each.value.root_password
      keys     = local.ssh_keys
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Reboot LXC containers after creation when idmap is configured.
# The bpg/proxmox provider writes idmap entries via SSH after the container
# starts, so bind mounts show 65534 (nobody) until a reboot.
# Triggers on first creation and whenever idmap values change.
resource "terraform_data" "lxc_idmap_reboot" {
  for_each = {
    for name, cfg in local.active_lxc : name => cfg
    if lookup(cfg, "idmap_uid", null) != null
  }

  triggers_replace = [
    each.value.idmap_uid,
    each.value.idmap_gid,
  ]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no root@${var.pve_host_addr} 'pct reboot ${each.value.vmid}'"
  }

  depends_on = [proxmox_virtual_environment_container.lxc]
}
