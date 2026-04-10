locals {
  ssh_keys = compact(split("\n", var.ssh_authorized_keys))

  # ---------------------------------------------------------------------------
  # LXC Definitions
  # ---------------------------------------------------------------------------

  lxc_definitions = {

    fileserver = {
      vmid          = 101
      description   = " "
      env_scope     = "prod"
      tags          = ["terraform"]
      os_version    = "13"
      cores         = 1
      memory        = 2048
      swap          = 4096
      start_on_boot = true
      startup_order = 1
      storage       = "zfs-lxc"
      idmap_uid     = 1000
      idmap_gid     = 1000
      root_password = var.universal_pass
      disks = [
        { size = 32 },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        ip          = "dhcp"
        firewall    = false
        mac_address = "BC:24:11:AB:27:65"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = []
      bind_mounts = [
        { source = "/sata/apple", target = "/mnt/apple" },
        { source = "/sata/media", target = "/mnt/media" },
        { source = "/sata/photos", target = "/mnt/photos" },
        { source = "/sata/personal", target = "/mnt/personal" },
      ]
    }

    fileserver-dev = {
      vmid          = 401
      env_scope     = "dev"
      description   = "Samba LXC test"
      tags          = ["terraform"]
      os_version    = "12"
      cores         = 2
      memory        = 2048
      swap          = 0
      start_on_boot = true
      startup_order = 1
      storage       = "local-btrfs"
      idmap_uid     = 1000
      idmap_gid     = 1000
      root_password = var.universal_pass
      disks = [
        { size = 8 },
      ]
      network = {
        bridge  = "vmbr3"
        vlan_id = 50
        ip      = "dhcp"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = []
      bind_mounts = [
        { source = "/mnt/test_mounts/personal", target = "/mnt/personal" },
        { source = "/mnt/test_mounts/photos", target = "/mnt/photos" },
        { source = "/mnt/test_mounts/media", target = "/mnt/media" },
        { source = "/mnt/test_mounts/apple", target = "/mnt/apple" },
      ]
    }

    swarm-lxc = {
      env_scope     = "prod"
      vmid          = 103
      description   = " "
      tags          = ["terraform", "swarm"]
      os_version    = "13"
      cores         = 8
      memory        = 8192
      swap          = 0
      start_on_boot = true
      startup_order = 22
      storage       = "zfs-lxc"
      idmap_uid     = 1000
      idmap_gid     = 1000
      root_password = var.universal_pass
      disks = [
        { size = 8 },
        { size = 32, mp = "/data" },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        ip          = "dhcp"
        firewall    = false
        mac_address = "BC:24:11:38:3A:7C"
      }
      features = {
        fuse    = true
        nesting = true
        keyctl  = true
      }
      devices = [
        { path = "/dev/dri/card0" },
        { path = "/dev/dri/renderD128", gid = 1000 },
        { path = "/dev/kfd", gid = 1000 },
        { path = "/dev/net/tun" },
      ]
      bind_mounts = [
        { source = "/mnt/test_mounts/personal", target = "/mnt/personal" },
        { source = "/mnt/test_mounts/photos", target = "/mnt/photos" },
        { source = "/mnt/test_mounts/media", target = "/mnt/media" },
        { source = "/mnt/test_mounts/apple", target = "/mnt/apple" },
      ]
    }

    swarm-lxc-dev = {
      vmid          = 403
      description   = "Swarm LXC test"
      tags          = ["terraform", "swarm"]
      os_version    = "12"
      cores         = 4
      memory        = 8192
      swap          = 0
      start_on_boot = true
      startup_order = 11
      storage       = "local-btrfs"
      idmap_uid     = 1000
      idmap_gid     = 1000
      root_password = var.universal_pass
      disks = [
        { size = 32 },
        { size = 32, mp = "/data" },
      ]
      network = {
        bridge  = "vmbr3"
        vlan_id = 50
        ip      = "dhcp"
      }
      features = {
        fuse    = false
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
        { source = "/mnt/test_mounts/personal", target = "/mnt/personal" },
        { source = "/mnt/test_mounts/photos", target = "/mnt/photos" },
        { source = "/mnt/test_mounts/media", target = "/mnt/media" },
        { source = "/mnt/test_mounts/apple", target = "/mnt/apple" },
      ]
    }

  }

  # ---------------------------------------------------------------------------
  # VM Definitions
  # ---------------------------------------------------------------------------

  vm_definitions = {

    swarm-vm = {
      env_scope     = "prod"
      vmid          = 102
      description   = " "
      tags          = ["terraform", "swarm"]
      cores         = 8
      sockets       = 1
      cpu_type      = "host"
      memory        = 20480
      balloon       = 0
      start_on_boot = true
      startup_order = 11
      machine       = "q35"
      bios          = "seabios"
      scsi_hardware = "virtio-scsi-single"
      storage       = "zfs-vm"
      disks = [
        { size = 16, cache = "none", ssd = true, discard = "on", iothread = true },
        { size = 64, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data" },
      ]
      network = {
        bridge   = "vmbr0"
        vlan_id  = 40
        model    = "virtio"
        firewall = false
      }
      cloudinit = {
        user       = "root"
        password   = var.universal_pass
        ip         = "dhcp"
        nameserver = "1.1.1.1"
        domain     = "home.arpa"
        datastore  = "local-btrfs"
      }
      vendor_data_enabled = true
      vendor_data_storage = "local"
      vga                 = "serial0"
    }

    swarm-vm-dev = {
      env_scope     = "dev"
      vmid          = 402
      description   = "Test Swarm VM"
      tags          = ["terraform", "swarm"]
      cores         = 4
      sockets       = 1
      cpu_type      = "host"
      memory        = 8192
      balloon       = 4096
      start_on_boot = true
      startup_order = 22
      machine       = "q35"
      bios          = "seabios"
      scsi_hardware = "virtio-scsi-single"
      storage       = "local-btrfs"
      disks = [
        { size = 32, cache = "none", ssd = true, discard = "on", iothread = true },
        { size = 32, cache = "none", ssd = false, discard = "ignore", iothread = true, mp = "/data" },
      ]
      network = {
        bridge   = "vmbr3"
        vlan_id  = 50
        model    = "virtio"
        firewall = true
      }
      cloudinit = {
        user       = "root"
        password   = var.universal_pass
        ip         = "dhcp"
        nameserver = "1.1.1.1"
        domain     = "home.arpa"
        datastore  = "local-btrfs"
      }
      vendor_data_enabled = true
      vendor_data_storage = "local-btrfs"
      vga                 = "serial0"
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
