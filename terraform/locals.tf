locals {
  ssh_keys = compact(split("\n", var.ssh_authorized_keys))

  # ---------------------------------------------------------------------------
  # LXC Definitions
  # ---------------------------------------------------------------------------

  lxc_definitions = {

    docker-lxc = {
      env_scope   = "prod"
      vm_id       = 103
      description = ""
      tags        = ["terraform", "docker"]
      os_version  = "13"
      cores       = 2
      memory = {
        dedicated = 2048
        swap      = 2048
      }
      start_on_boot     = true
      startup_order     = 5
      disk_datastore_id = "zfs-lxc"
      idmap_uid         = 1000
      idmap_gid         = 1000
      password          = var.universal_pass
      disks = [
        { size = 8 },
        { size = 16, mp = "/data" },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        address     = "dhcp"
        mac_address = "BC:24:11:74:D4:08"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = [
        { path = "/dev/net/tun" },
      ]
      bind_mounts = [
        { volume = "/sata/media", path = "/mnt/media" },
      ]
    }

    fileserver = {
      env_scope   = "prod"
      vm_id       = 101
      description = ""
      tags        = ["terraform"]
      os_version  = "13"
      cores       = 1
      memory = {
        dedicated = 2048
        swap      = 4096
      }
      start_on_boot     = true
      startup_order     = 1
      disk_datastore_id = "zfs-lxc"
      idmap_uid         = 1000
      idmap_gid         = 1000
      password          = var.universal_pass
      disks = [
        { size = 16 },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        address     = "dhcp"
        mac_address = "BC:24:11:AB:27:65"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = []
      bind_mounts = [
        { volume = "/sata/apple", path = "/mnt/apple" },
        { volume = "/sata/media", path = "/mnt/media" },
        { volume = "/sata/photos", path = "/mnt/photos" },
        { volume = "/sata/personal", path = "/mnt/personal" },
      ]
    }

    fileserver-dev = {
      env_scope   = "dev"
      vm_id       = 401
      description = "Samba LXC test"
      tags        = ["terraform"]
      os_version  = "12"
      cores       = 2
      memory = {
        dedicated = 2048
        swap      = 0
      }
      start_on_boot     = true
      startup_order     = 1
      disk_datastore_id = "local-btrfs"
      idmap_uid         = 1000
      idmap_gid         = 1000
      password          = var.universal_pass
      disks = [
        { size = 8 },
      ]
      network = {
        bridge  = "vmbr3"
        vlan_id = 50
        address = "dhcp"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = []
      bind_mounts = [
        { volume = "/mnt/test_mounts/personal", path = "/mnt/personal" },
        { volume = "/mnt/test_mounts/photos", path = "/mnt/photos" },
        { volume = "/mnt/test_mounts/media", path = "/mnt/media" },
        { volume = "/mnt/test_mounts/apple", path = "/mnt/apple" },
      ]
    }

    swarm-lxc = {
      env_scope   = "prod"
      vm_id       = 105
      description = ""
      tags        = ["terraform", "swarm"]
      os_version  = "13"
      cores       = 8
      memory = {
        dedicated = 8192
        swap      = 0
      }
      start_on_boot     = true
      startup_order     = 22
      disk_datastore_id = "zfs-lxc"
      idmap_uid         = 1000
      idmap_gid         = 1000
      password          = var.universal_pass
      disks = [
        { size = 8 },
        { size = 64, mp = "/data" },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        address     = "dhcp"
        mac_address = "BC:24:11:38:3A:7C"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = [
        { path = "/dev/dri/card0", gid = 1000 },
        { path = "/dev/dri/renderD128", gid = 1000 },
        { path = "/dev/kfd", gid = 1000 },
        { path = "/dev/net/tun" },
      ]
      bind_mounts = [
        { volume = "/sata/apple", path = "/mnt/apple" },
        { volume = "/sata/media", path = "/mnt/media" },
        { volume = "/sata/photos", path = "/mnt/photos" },
        { volume = "/sata/personal", path = "/mnt/personal" },
      ]
    }

    swarm-lxc-dev = {
      env_scope   = "dev"
      vm_id       = 403
      description = "Swarm LXC test"
      tags        = ["terraform", "swarm"]
      os_version  = "12"
      cores       = 4
      memory = {
        dedicated = 8192
        swap      = 0
      }
      start_on_boot     = true
      startup_order     = 11
      disk_datastore_id = "local-btrfs"
      idmap_uid         = 1000
      idmap_gid         = 1000
      password          = var.universal_pass
      disks = [
        { size = 32 },
        { size = 32, mp = "/data" },
      ]
      network = {
        bridge  = "vmbr3"
        vlan_id = 50
        address = "dhcp"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = [
        { path = "/dev/dri/card1" },
        { path = "/dev/dri/renderD128", gid = 1000 },
        { path = "/dev/kfd", gid = 1000 },
        { path = "/dev/net/tun" },
      ]
      bind_mounts = [
        { volume = "/mnt/test_mounts/personal", path = "/mnt/personal" },
        { volume = "/mnt/test_mounts/photos", path = "/mnt/photos" },
        { volume = "/mnt/test_mounts/media", path = "/mnt/media" },
        { volume = "/mnt/test_mounts/apple", path = "/mnt/apple" },
      ]
    }

  }

  # ---------------------------------------------------------------------------
  # VM Definitions
  # ---------------------------------------------------------------------------

  vm_definitions = {

    swarm-vm = {
      env_scope   = "prod"
      vm_id       = 102
      description = ""
      tags        = ["terraform", "swarm"]
      cores       = 8
      memory = {
        dedicated = 20480
        floating  = 0
      }
      on_boot           = true
      startup_order     = 11
      machine           = "q35"
      bios              = "seabios"
      scsi_hardware     = "virtio-scsi-single"
      disk_datastore_id = "zfs-vm"
      disks = [
        { size = 16, cache = "none", ssd = true, discard = "on", iothread = true },
        { size = 64, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data" },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:06:72:8C"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        servers      = "1.1.1.1"
        domain       = "home.arpa"
        datastore_id = "zfs-vm"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "zfs-cold"
    }

    swarm-vm-dev = {
      env_scope   = "dev"
      vm_id       = 402
      description = "Test Swarm VM"
      tags        = ["terraform", "swarm"]
      cores       = 4
      memory = {
        dedicated = 8192
        floating  = 4096
      }
      on_boot           = true
      startup_order     = 22
      machine           = "q35"
      bios              = "seabios"
      scsi_hardware     = "virtio-scsi-single"
      disk_datastore_id = "local-btrfs"
      disks = [
        { size = 32, cache = "none", ssd = true, discard = "on", iothread = true },
        { size = 32, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data" },
      ]
      network = {
        bridge  = "vmbr3"
        vlan_id = 50
        model   = "virtio"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        servers      = "1.1.1.1"
        domain       = "home.arpa"
        datastore_id = "local-btrfs"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "local-btrfs"
    }
  }

  # ---------------------------------------------------------------------------
  # env_scope filtering | Resources without env_scope set will match both.
  # ---------------------------------------------------------------------------

  active_lxc = {
    for name, cfg in local.lxc_definitions :
    name => cfg
    if lookup(cfg, "env_scope", terraform.workspace) == terraform.workspace
  }

  active_vm = {
    for name, cfg in local.vm_definitions :
    name => cfg
    if lookup(cfg, "env_scope", terraform.workspace) == terraform.workspace
  }

  # ---------------------------------------------------------------------------
  # OS template mapping
  # ---------------------------------------------------------------------------

  os_template = {
    "12" = proxmox_download_file.debian_12_lxc.id
    "13" = proxmox_download_file.debian_13_lxc.id
  }

}
