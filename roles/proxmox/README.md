# Proxmox Roles

Ansible roles for managing Proxmox VE resources including LXC containers and virtual machines.

## Overview

This collection provides declarative infrastructure management for Proxmox environments. Resources are defined as YAML files in `inventory/host_vars/` and automatically discovered, created, and provisioned.

### Key Features

- **File-based discovery**: No static inventory maintenance required
- **Credential inheritance**: Define `pve_host` once, credentials flow automatically
- **Reconciliation**: Reliable matching via `ansible_id` tags survives VMID changes
- **API-first**: Uses Proxmox REST API for state queries and modifications
- **Unified purge**: Tag-based resource removal with accurate change detection

## Roles

| Role | Purpose |
| ------ | --------- |
| `proxmox/lxc` | LXC container lifecycle management |
| `proxmox/vm` | Virtual machine lifecycle with cloud-init |

## Architecture

### Playbook Structure

Both `playbooks/lxc.yml` and `playbooks/vm.yml` follow a 4-play architecture:

1. **Discover**: Scan `host_vars/{lxc,vm}/*.yml` and build dynamic inventory
2. **Create**: Build resources on Proxmox via API/commands
3. **Provision**: Configure resources via SSH (apply common and application roles)
4. **Purge**: Remove resources using tag-based reconciliation (explicit `--tags purge` only)

### Credential Flow

Resources specify only which Proxmox host to target. Credentials are inherited automatically:

```text
host_vars/{lxc,vm}/*.yml  →  defines pve_host: pve
group_vars/proxmox.yml    →  lookups hostvars[pve_host]
host_vars/proxmox/pve.yml →  contains actual secrets
```

### Reconciliation System

Each resource receives a unique identifier computed from its hostname and VMID:

- **ansible_id**: 8-character SHA256 hash of `hostname + vmid`
- **ansible_id_tag**: Applied to Proxmox resource as `ansible_<hash>`

This enables reliable matching even when VMID is manually changed on Proxmox, hostname is updated in host_vars, or resource is recreated with different parameters.

**Lookup priority:** ansible_id tag → VMID fallback → not found

## Shared Tasks

Reusable task files in `roles/proxmox/shared/tasks/` implement common functionality across both roles.

| Task | Purpose |
| ------ | --------- |
| `compute_ansible_id.yml` | Generate unique hash from hostname + vmid for reconciliation |
| `check_resource_state.yml` | Query Proxmox API to determine if resource exists and how it was matched |
| `purge_resource.yml` | Remove resources using API-based lookup and module-based deletion |
| `cleanup_failed_resource.yml` | Remove partially created resources in rescue blocks |
| `resolve_storage.yml` | Auto-select storage pool based on content type requirements |
| `validate_common.yml` | Validate Proxmox environment and pve_host configuration |

### Action Methods

Tasks are categorized by how they interact with Proxmox:

| Method | Count | Modules/Commands |
| -------- | ------- | ------------------ |
| **Proxmox API** | 13 | `community.proxmox.*` modules |
| **Shell Commands** | 15 | `pct`, `qm`, `pveam`, `pvesm` |
| **Config Files** | 5 | Direct writes to `/etc/pve/` or storage |

**Proxmox API** — State queries, disk operations, resource deletion:

| Task | Module | Purpose |
| ------ | -------- | --------- |
| `check_resource_state.yml` | `proxmox_vm_info` | Query resources by ansible_id tag |
| `resolve_storage.yml` | `proxmox_storage_info` | Find storage pools by content type |
| `cleanup_failed_resource.yml` | `proxmox`, `proxmox_kvm` | Force delete failed resources |
| `purge_resource.yml` | `proxmox`, `proxmox_kvm` | Purge with tag lookup |
| `vm/create.yml` | `proxmox_disk` | Import/resize/create disks |
| `vm/create.yml` | `proxmox_kvm` | Start VM (`state: started`) |

**Shell Commands** — Resource creation, template management, IP discovery:

| Task | Command | Purpose |
| ------ | --------- | --------- |
| `validate_common.yml` | `pveversion` | Verify Proxmox environment |
| `lxc/build_pct_command.yml` | `pveam available`, `pveam download` | Template management |
| `lxc/create.yml` | `pct create`, `pct start`, `pct exec` | Container lifecycle |
| `vm/create.yml` | `qm create`, `qm agent`, `qm guest exec` | VM lifecycle |
| `vm/cicustom.yml` | `pvesm path` | Resolve storage paths |

**Config Files** — Post-creation config, SSH keys, cloud-init vendor data:

| Task | Target | Purpose |
| ------ | -------- | --------- |
| `lxc/post_configure.yml` | `/etc/pve/lxc/{vmid}.conf` | Append idmap/devices via `blockinfile` |
| `roles/proxmox/lxc/tasks/create.yml` | Temp file (staged and cleaned up) | SSH keys for container injection |
| `roles/proxmox/vm/tasks/create.yml` | `vm_temp_dir` (staged and cleaned up) | SSH keys for cloud-init |
| `vm/cicustom.yml` | `{storage}/snippets/vendor-*.yml` | Custom cloud-init vendor data |

**Design rationale:**

- Shell commands for creation: `pct create`/`qm create` offer precise parameter control unavailable in API modules
- API for disk operations: `proxmox_disk` handles import/resize with better idempotency
- Config file writes are minimal: only `post_configure.yml` touches `/etc/pve/` directly for features unsupported by `pct create`

### Purge System

The unified purge task (`purge_resource.yml`) provides:

- **API-based lookup**: Uses `proxmox_vm_info` module instead of shell parsing
- **Tag-first matching**: Finds resources by ansible_id tag, falls back to VMID
- **Module-based removal**: Uses `community.proxmox` modules for idempotent deletion
- **Accurate change detection**: Reports actual changes instead of `changed_when: true`
- **Vendor file cleanup**: Removes cloud-init vendor files for VMs when enabled

## LXC Role

Creates unprivileged LXC containers using Proxmox container templates.

**Capabilities:**

- Multi-disk configurations with mount points
- Device passthrough (GPU/VAAPI, USB serial, TUN)
- UID/GID mapping for unprivileged host resource access
- Feature flags (nesting for Docker, FUSE, NFS/CIFS mounts)
- Bind mounts from host paths
- Static or DHCP networking with VLAN support

**Workflow:**

1. Validate configuration against schema
2. Check resource state via API reconciliation
3. Download container template if missing
4. Create container with `pct create`
5. Apply post-creation configuration (devices, mounts, features)
6. Start container and discover IP
7. Provision via SSH with application roles

**Required variables:** `pve_host`, `lxc_vmid`, `lxc_hostname`

See `inventory/group_vars/lxc.yml` for all options. Schema: `schemas/lxc.schema.json`.

### Direct Config Modification

The `pct create` command handles 95% of container configuration, but certain LXC features require direct editing of `/etc/pve/lxc/{vmid}.conf` after creation.

**Why direct editing is necessary:**

| Feature | pct Support | Reason |
| --------- | ------------- | -------- |
| UID/GID mapping | None | Requires multiple coordinated `lxc.idmap` entries |
| TUN device | None | Needs atomic cgroup2 permission + mount entry |
| Privileged device passthrough | None | `--devN` is unprivileged-only; privileged needs raw LXC syntax |

**What gets written:**

| Feature | Trigger | Entries Added |
| --------- | --------- | --------------- |
| UID/GID mapping | `lxc_idmap_uid`/`gid` set, unprivileged | `lxc.idmap: u/g` entries for 1:1 user mapping |
| TUN device | `lxc_device_tun: true` | `lxc.cgroup2.devices.allow: c 10:200 rwm` + mount entry |
| VAAPI GPU | `lxc_device_vaapi: true`, privileged | `lxc.cgroup2.devices.allow: c 226:* rwm` + `/dev/dri` mount |
| Framebuffer | `lxc_device_framebuffer: true`, privileged | `lxc.cgroup2.devices.allow: c 29:0 rwm` + `/dev/fb0` mount |
| AMD KFD | `lxc_device_kfd: true`, privileged | `lxc.cgroup2.devices.allow: c 511:0 rwm` + `/dev/kfd` mount |
| USB Serial | `lxc_device_usb_serial: true`, privileged | `lxc.cgroup2.devices.allow: c 188:* rwm` + per-device mounts |
| USB ACM | `lxc_device_usb_acm: true`, privileged | `lxc.cgroup2.devices.allow: c 189:* rwm` + per-device mounts |

**Privileged vs unprivileged device handling:**

- **Unprivileged**: Devices passed via `pct create --devN` with GID mapping. Detection runs before creation, builds command arguments.
- **Privileged**: Devices passed via direct `lxc.cgroup2` + `lxc.mount.entry` directives. Detection runs after creation, appends to config file.

**Safety mechanisms:**

- Uses `blockinfile` with `# BEGIN/END ANSIBLE MANAGED` markers for idempotent updates
- Template renders empty output if no features enabled (skips modification entirely)
- Immediate read-back verification after modification
- Failed modifications trigger container cleanup via rescue block

**Template:** `lxc_extra_config.j2` renders conditional sections based on enabled features and container privilege mode.

## VM Role

Creates virtual machines using cloud images and cloud-init configuration.

**Capabilities:**

- Cloud image support (Debian, Ubuntu, or custom qcow2/img)
- Multi-disk configurations with mixed bus types (scsi, sata, virtio)
- Cloud-init user data, network config, and vendor data
- QEMU guest agent integration
- Static or DHCP networking with VLAN support

**Workflow:**

1. Validate configuration against schema
2. Check resource state via API reconciliation
3. Download and cache cloud image if needed
4. Create VM with `qm create`
5. Import and resize boot disk
6. Configure cloud-init settings
7. Optionally apply custom vendor data
8. Start VM and discover IP via DNS or guest agent
9. Provision via SSH with application roles

**Required variables:** `pve_host`, `vm_vmid`, `vm_hostname`

See `inventory/group_vars/vm.yml` for all options. Schema: `schemas/vm.schema.json`.

### Cloud-Init Integration

The VM role implements cloud-init through Proxmox's native support, combining automatic network configuration with optional custom vendor data injection.

**Two-Layer Networking:**

| Layer | Parameter | Purpose |
| ------- | ----------- | --------- |
| Physical | `--net0` | VM's virtual NIC in Proxmox (model, bridge, VLAN, MAC) |
| Guest OS | `--ipconfig0` | Network config inside guest via cloud-init (IP, gateway) |

The physical layer defines how Proxmox connects the VM to the network. The guest layer tells cloud-init how to configure the OS networking. Both are required for functional connectivity.

**Network Modes:**

| Mode | ipconfig0 Value | Requirements |
| ------ | ----------------- | -------------- |
| DHCP | `ip=dhcp` | None (default) |
| Static IPv4 | `ip=192.168.1.100/24,gw=192.168.1.1` | `vm_cloudinit_gateway` required |
| Dual-stack | Above + `ip6=auto` or IPv6 CIDR | Optional IPv6 settings |

**SSH Key Injection:**
Keys from `vault_ssh_authorized_keys` are written to a temporary file on the Proxmox host, passed via `--sshkeys`, and injected by cloud-init into the user's `authorized_keys`. The temporary file is cleaned up after creation.

**Custom Vendor Data (cicustom):**

Pre-boot initialization that runs before network configuration. Useful for:

- Installing QEMU guest agent before first boot
- Configuring DNS before DHCP
- Setting up package repositories

**Requirements when enabled:**

- `vm_cicustom_vendor_enabled: true`
- `vm_cicustom_vendor_storage`: Proxmox storage name with snippets support
- Disks requiring guest-side mounting need `mp` field in `vm_disks` entries (additional disks only)

The vendor data is rendered from `templates/vendor.yml.j2`, which derives disk config (`disk_setup`, `fs_setup`, `mounts`, `bootcmd`) from `vm_disks` entries that define a `mp` field. Device paths use `/dev/disk/by-id/` for deterministic references regardless of kernel enumeration order. The rendered file is placed at `{storage}/snippets/vendor-{hostname}.yml` and passed via `--cicustom vendor=...`.

**Cloud-Init Parameters:**

| Parameter | Variable | Description |
| ----------- | ---------- | ------------- |
| `--ide2` | (auto) | Cloud-init CDROM on storage |
| `--citype` | `vm_cloudinit_type` | Datasource: nocloud, configdrive2 |
| `--ciuser` | `vm_cloudinit_user` | Initial user (default: root) |
| `--cipassword` | `vm_cloudinit_password` | Optional password from vault |
| `--sshkeys` | `vault_ssh_authorized_keys` | Public keys for injection |
| `--ipconfig0` | `vm_cloudinit_ip` + gateway | Network configuration |
| `--ciupgrade` | `vm_cloudinit_upgrade` | Upgrade packages on boot |
| `--nameserver` | `vm_cloudinit_nameserver` | Custom DNS resolver |
| `--searchdomain` | `vm_cloudinit_searchdomain` | DNS search domain |
| `--cicustom` | rendered from `vendor.yml.j2` | Custom vendor data (disk setup from `vm_disks.mp`) |

**Validation Rules:**

- Cloud-init enabled → user and IP required
- Static IP (not "dhcp") → gateway required
- Vendor data enabled → storage and file path required
- SSH keys missing → warning (not failure)

**Post-Creation Verification:**
After VM creation, the role queries the Proxmox API to verify CPU, memory, and disk match the requested values. Mismatches trigger immediate failure.

## Integration

### Applied Roles (Provisioning Phase)

**Common roles** (both LXC and VM): ssh, users, packages, dotfiles

**VM-specific roles**: qemu_agent, dns, ntp

**Application roles** (when enabled): docker, tailscale, samba

### Post-Provisioning

Resources can be further managed by other playbooks such as `playbooks/swarm.yml` for Docker Swarm cluster formation or `playbooks/k3s.yml` for Kubernetes deployment.

## Node Configuration

### Proxmox Node Name vs Inventory Hostname

The Ansible inventory hostname (`pve_host`) may differ from the actual Proxmox cluster node name. The Proxmox API requires the cluster node name for operations.

**Configuration:**

```yaml
# inventory/hosts.yml
proxmox:
  hosts:
    pve:                                    # Ansible inventory hostname
      ansible_host: "proxmox.home.arpa"      # SSH connection address
      proxmox_node_name: "proxmox"           # Actual Proxmox cluster node name
```

**Usage in tasks:**

| Operation Type | Node Parameter |
|----------------|----------------|
| API queries (reconciliation) | Omit `node:` - queries all nodes |
| API operations (delete/start) | `node: "{{ hostvars[pve_host].proxmox_node_name \| default(pve_host) }}"` |
| Shell commands | `delegate_to: "{{ pve_host }}"` (uses SSH via ansible_host) |

**Finding your Proxmox node name:**

```bash
# On the Proxmox host
hostname  # This is the cluster node name
# Or check Proxmox UI: Datacenter → Nodes
```

## Troubleshooting

### Resource Not Found During Purge

The purge system searches by ansible_id tag first, then falls back to VMID. If neither matches, the resource is considered already absent.

Check existing tags with `pct config <vmid> | grep tags` (LXC) or `qm config <vmid> | grep tags` (VM).

### Reconciliation Mismatch

If a resource exists but isn't matched, the ansible_id tag may be missing (pre-existing resource) or the VMID in host_vars may differ from actual. Add the correct ansible_id tag manually or update host_vars to match actual VMID.

### Creation Failures

Both roles use rescue blocks to clean up partially created resources. Verify storage availability with `pvesm status`, check for VMID conflicts with `pvesh get /cluster/nextid`, and ensure template/image availability.

### IP Discovery Failures

Resources must be reachable for provisioning. Verify DNS resolution or DHCP lease, check cloud-init status for VMs with `qm guest exec <vmid> -- cloud-init status`, and verify SSH service is running.

### Node Name Mismatch

If API operations fail with "Node X doesn't exist in PVE cluster":

1. Check your Proxmox node name: `ssh pve hostname`
2. Add `proxmox_node_name` to inventory:

```yaml
pve:
  ansible_host: "proxmox.home.arpa"
  proxmox_node_name: "proxmox"  # Actual cluster node name
```
