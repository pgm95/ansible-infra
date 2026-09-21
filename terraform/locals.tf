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
      os_version  = "debian-13"
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
        { size = 16, mp = "/data", backup = true, floating = true, slot = 0 },
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
      os_version  = "debian-13"
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
      vm_id       = 201
      description = "Samba LXC test"
      tags        = ["terraform"]
      os_version  = "debian-13"
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
        { size = 4, mp = "/data", backup = true, floating = true, slot = 0 },
      ]
      network = {
        bridge      = "vmbr3"
        vlan_id     = 40
        address     = "dhcp"
        mac_address = "BC:24:11:59:A4:74"
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
      os          = "debian-13"
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
        { size = 16, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 128, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true, floating = true, slot = 0 },
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
        datastore_id = "zfs-vm"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "zfs-cold"
    }

    swarm-vm-dev = {
      env_scope   = "dev"
      vm_id       = 202
      description = "Test Swarm VM"
      tags        = ["terraform", "swarm"]
      os          = "debian-13"
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
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 32, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true, floating = true, slot = 0 },
      ]
      network = {
        bridge      = "vmbr3"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:0F:1B:77"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        datastore_id = "local-btrfs"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "local-btrfs"
    }

    swarm-gpu = {
      env_scope   = "prod"
      vm_id       = 104
      description = ""
      tags        = ["terraform", "swarm"]
      os          = "ubuntu-26"
      cores       = 8
      numa        = true
      started     = true
      memory = {
        dedicated = 16384
        floating  = 0
      }
      on_boot           = true
      startup_order     = 22
      machine           = "q35"
      bios              = "ovmf"
      scsi_hardware     = "virtio-scsi-single"
      kvm_arguments     = "-fw_cfg name=opt/ovmf/X-PciMmio64Mb,string=65536"
      rng_source        = "/dev/urandom"
      disk_datastore_id = "zfs-vm"
      disks = [
        { size = 16, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 128, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true, floating = true, slot = 1 },
      ]
      hostpci = [
        { mapping = "B50", pcie = true },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:9B:BE:DC"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        datastore_id = "zfs-vm"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "zfs-cold"
    }

    swarm-gpu-dev = {
      env_scope   = "dev"
      vm_id       = 204
      description = "Test Swarm GPU"
      tags        = ["terraform", "swarm"]
      os          = "ubuntu-26"
      cores       = 4
      memory = {
        dedicated = 8192
        floating  = 0
      }
      on_boot           = true
      startup_order     = 22
      machine           = "q35"
      bios              = "seabios"
      scsi_hardware     = "virtio-scsi-single"
      disk_datastore_id = "local-btrfs"
      disks = [
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 32, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true, floating = true, slot = 1 },
      ]
      network = {
        bridge      = "vmbr3"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:78:A4:11"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        datastore_id = "local-btrfs"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "local-btrfs"
    }

    swarm-qdevice = {
      env_scope   = "prod"
      vm_id       = 106
      description = ""
      tags        = ["terraform", "swarm"]
      os          = "debian-13"
      cores       = 2
      memory = {
        dedicated = 4096
        floating  = 0
      }
      on_boot           = true
      startup_order     = 11
      machine           = "q35"
      bios              = "seabios"
      scsi_hardware     = "virtio-scsi-single"
      disk_datastore_id = "zfs-vm"
      disks = [
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true, floating = true, slot = 2 },
      ]
      network = {
        bridge      = "vmbr0"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:E2:2C:4D"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
        datastore_id = "zfs-vm"
      }
      vendor_data_enabled = true
      vendor_datastore_id = "zfs-cold"
    }

    swarm-qdevice-dev = {
      env_scope   = "dev"
      vm_id       = 206
      description = "Test Swarm QDevice"
      tags        = ["terraform", "swarm"]
      os          = "debian-13"
      cores       = 2
      memory = {
        dedicated = 4096
        floating  = 0
      }
      on_boot           = true
      startup_order     = 22
      machine           = "q35"
      bios              = "seabios"
      scsi_hardware     = "virtio-scsi-single"
      disk_datastore_id = "local-btrfs"
      disks = [
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, backup = true },
        { size = 8, cache = "none", ssd = true, discard = "on", iothread = true, mp = "/data", backup = true },
      ]
      network = {
        bridge      = "vmbr3"
        vlan_id     = 40
        model       = "virtio"
        mac_address = "BC:24:11:91:45:33"
      }
      cloudinit = {
        username     = "root"
        password     = var.universal_pass
        address      = "dhcp"
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
  # Segment domains | mirrors the per-VLAN dnsmasq `domain=` ranges on the router
  # ---------------------------------------------------------------------------
  # The router is authoritative for resolution (options 6, 15 and 119). This map
  # exists only because Proxmox needs a search domain to build a guest's FQDN:
  # containers get it via `initialization.dns.domain`, VMs via the cloud-init
  # `fqdn:` derived from the same field. Without it Proxmox falls back to the
  # first token of the hypervisor's own resolv.conf search line.

  segment_domain = {
    "10" = "admin.home.arpa"
    "20" = "lan.home.arpa"
    "30" = "iot.home.arpa"
    "40" = "lab.home.arpa"
    "50" = "k8s.home.arpa"
  }

  # Per-guest domain: an explicit value wins, otherwise it is derived from the
  # VLAN the guest sits on. Computed once so the `dynamic "dns"` guard in vm.tf
  # and the block it renders cannot disagree.

  lxc_domain = {
    for name, cfg in local.active_lxc :
    name => try(cfg.dns.domain, lookup(local.segment_domain, tostring(lookup(cfg.network, "vlan_id", "")), null))
  }

  vm_domain = {
    for name, cfg in local.active_vm :
    name => lookup(cfg.cloudinit, "domain", lookup(local.segment_domain, tostring(lookup(cfg.network, "vlan_id", "")), null))
  }

  # ---------------------------------------------------------------------------
  # Floating data volumes | holder guests own the data, real guests attach it
  # ---------------------------------------------------------------------------
  # Proxmox frees a volume on guest destroy only when the destroying guest's ID
  # equals the owner encoded in the volume name. One never-started holder per
  # guest type owns every disk marked `floating = true`; `slot` pins where the
  # disk lives on the holder (scsi<slot> on the VM holder, mp<slot> on the LXC
  # holder) so adding or removing a guest never moves another guest's volume.
  # Holder VMIDs are fixed per type; dev and prod are separate hypervisors.

  data_holder_vm_id  = 900
  data_holder_lxc_id = 901
  data_holder_os     = "debian-13" # LXC holder needs a template, never boots it

  lxc_floating = merge([
    for name, cfg in local.active_lxc : {
      for d in slice(cfg.disks, 1, length(cfg.disks)) : "${name}/${d.slot}" => {
        guest        = name
        slot         = d.slot
        size         = d.size
        mp           = d.mp
        backup       = lookup(d, "backup", true)
        datastore_id = lookup(d, "datastore_id", cfg.disk_datastore_id)
        holder_path  = "/${name}${d.mp}"
      } if lookup(d, "floating", false) && lookup(d, "mp", "") != ""
    }
  ]...)

  vm_floating = merge([
    for name, cfg in local.active_vm : {
      for i, d in slice(cfg.disks, 1, length(cfg.disks)) : "${name}/${d.slot}" => {
        guest        = name
        slot         = d.slot
        index        = i + 1 # guest-side scsi index, keeps the by-id path stable
        size         = d.size
        mp           = d.mp
        backup       = lookup(d, "backup", true)
        datastore_id = lookup(d, "datastore_id", cfg.disk_datastore_id)
        cache        = d.cache
        ssd          = d.ssd
        discard      = d.discard
        iothread     = d.iothread
      } if lookup(d, "floating", false) && lookup(d, "mp", "") != ""
    }
  ]...)

  # Slot-ordered lists drive the holder blocks (map keys iterate lexically).
  lxc_floating_by_slot = values({ for k, f in local.lxc_floating : format("%03d", f.slot) => f })
  vm_floating_by_slot  = values({ for k, f in local.vm_floating : format("%03d", f.slot) => f })

  lxc_holder_datastore = try(local.lxc_floating_by_slot[0].datastore_id, null)

  # Read-back from the holders: volume ids the guests attach. Unknown until
  # the holder exists, empty when there is nothing floating.
  lxc_holder_volumes = try({
    for m in proxmox_virtual_environment_container.data_holder["holder"].mount_point : m.path => m.path_in_datastore
  }, {})

  vm_holder_disks = try({
    for hd in proxmox_virtual_environment_vm.data_holder["holder"].disk : hd.interface => hd
  }, {})

  # ---------------------------------------------------------------------------
  # OS image mapping | LXC templates and VM cloud images
  # ---------------------------------------------------------------------------
  # Downloads are gated on what the active workspace actually uses, so a node
  # never stores an image no guest on it references.

  used_lxc_os = toset([for cfg in values(local.active_lxc) : cfg.os_version])
  used_vm_os  = toset([for cfg in values(local.active_vm) : cfg.os])

  os_template = {
    "debian-13" = one(proxmox_download_file.debian_13_lxc[*].id)
  }

  vm_cloud_image = {
    "debian-13" = one(proxmox_download_file.debian_13_cloud[*].id)
    "ubuntu-26" = one(proxmox_download_file.ubuntu_26_cloud[*].id)
  }

}
