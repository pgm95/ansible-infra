# Homeops Proxmox Knowledge Base

Comprehensive reference for Proxmox infrastructure automation patterns, learnings, and implementation details.

---

## Architecture Overview

### Multi-PVE Host Support

```text
inventory/{env}/host_vars/lxc/*.yml or inventory/{env}/host_vars/vm/*.yml
├── pve_host: pve1  (REQUIRED - target Proxmox host)
├── lxc_vmid/vm_vmid, lxc_hostname/vm_hostname (REQUIRED)
└── Other configuration...
        ↓
Play 1: Discovery [tags: always] (discover_definitions.yml)
├── Find definition files in inventory_dir/host_vars/{lxc,vm}/
├── add_host: register to single group (lxc or vm), pass _inventory_dir
├── include_vars: load host-specific variables
└── group_by: create dynamic pve_host groups
        ↓
playbooks/group_vars/proxmox.yml (evaluated in VM/LXC context)
├── proxmox_api_host: "{{ hostvars[pve_host].ansible_host }}"
├── proxmox_api_token_secret: "{{ vault_proxmox_token_secret }}"
└── proxmox_api_password: "{{ vault_universal_pass }}"
        ↓
inventory/{env}/host_vars/{pve_host}.yml (PVE host-specific overrides)
│   Auto-loaded by Ansible (filename matches static host in hosts.yml)
│   Currently only defines proxmox_api_token_secret, which is redundant
│   with playbooks/group_vars/proxmox.yml (same value, host_vars wins by
│   precedence but has no effect). These files would only matter if each
│   PVE host needed different API credentials.
│
│   Can hold any variable for the PVE host. Variables accessed via
│   hostvars[pve_host] by LXC/VM plays: ansible_host, proxmox_node_name,
│   proxmox_api_token_secret. First two are currently set inline in hosts.yml.
└── VPS host_vars also live directly in host_vars/ (auto-loaded, same as PVE hosts).
    Only host_vars/lxc/ and host_vars/vm/ subdirectories use manual loading
    via the discovery task (include_vars + delegate_facts).
        ↓
Play 2: Create [hosts: lxc/vm] (delegate_to: "{{ pve_host }}")
└── Skipped if resource exists, otherwise create on target PVE host
        ↓
Play 3: Provision [hosts: lxc/vm] (SSH to resource)
└── Apply configured roles

Environment selection: PROJECT_ENV=prod or PROJECT_ENV=dev (default: dev)
Workflow: Always run `mise run lxc:deploy` or `mise run vm:deploy` - creation skipped if exists.

Interactive deployment (prompts for hosts/tags when args omitted):
  mise run vm:deploy [hosts] [tags]
  mise run lxc:deploy [hosts] [tags]

All deploy/check/purge tasks use shared `.mise/scripts/deploy.sh`, parametrized via TOML env vars.
Env vars: DEPLOY_GROUP (required), DEPLOY_INTERACTIVE, DEPLOY_CHECK_MODE, usage_tags.
```

### Key Variables

**Required in inventory/{env}/host_vars (VM/LXC)**:

```yaml
pve_host: pve            # REQUIRED - must be in proxmox group
lxc_vmid: "300"          # REQUIRED - explicit, no auto-assign
lxc_hostname: "mycontainer"
```

**Shared Settings (playbooks/group_vars/proxmox.yml)**:

```yaml
proxmox_api_user: "ansible@pve"
proxmox_api_token_id: "homeops"
proxmox_api_validate_certs: false

# Dynamic lookups (evaluated per-resource)
proxmox_api_host: "{{ hostvars[pve_host].ansible_host }}"
proxmox_api_token_secret: "{{ hostvars[pve_host].proxmox_api_token_secret }}"
proxmox_api_password: "{{ vault_universal_pass }}"

# DRY pattern for shared tasks
proxmox_api_auth:
  api_host: "{{ proxmox_api_host }}"
  api_user: "{{ proxmox_api_user }}"
  api_token_id: "{{ proxmox_api_token_id }}"
  api_token_secret: "{{ proxmox_api_token_secret }}"
  validate_certs: "{{ proxmox_api_validate_certs }}"
```

### Vault Requirements

```yaml
# inventory/{env}/group_vars/all/vault.yml (auto-loaded, per-environment)
vault_proxmox_token_secret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## Reconciliation Patterns

### Hash-Based Infrastructure Identifiers

**Pattern**: Compute deterministic hash from stable identifiers for reliable resource matching.

```text
ansible_id = sha256(hostname + vmid)[:8]
```

**Why It Works**:

- Deterministic: Same inputs = same output
- Persistent: Stored as Proxmox tag, survives changes
- Queryable: Filter by tags via API
- Short: 8 chars = 4B combinations (sufficient)

### Two-Tier Reconciliation Matching

**Tier 1 - Primary (ansible_id tag)**:

- Most reliable, indicates managed resource
- Survives VMID/hostname changes

**Tier 2 - Fallback (VMID)**:

- Backward compatibility for existing resources
- Migration path for untagged resources

**Decision Logic**:

```text
matched_by_tag   → SKIP (managed, exists)
matched_by_id    → SKIP + warn if mismatch
no_match         → CREATE
```

### Reconciliation State Machine

```text
DEFINED + EXISTS (matching ansible_id) → SKIP (provision)
DEFINED + EXISTS (matching vmid)       → SKIP (provision + warn)
DEFINED + NOT_EXISTS                   → CREATE
NOT_DEFINED + EXISTS (has ansible_id)  → WARN (orphan)
NOT_DEFINED + EXISTS (no ansible_id)   → IGNORE (unmanaged)
```

### Strict Enforcement for Predictability

Always enforce explicit definition of identifier components:

```yaml
- ansible.builtin.assert:
    that:
      - vm_vmid is defined
      - vm_vmid | string | length > 0
    fail_msg: "vm_vmid MUST be explicitly defined"
```

**Why**: Auto-assignment creates unpredictable identifiers, breaking reconciliation.

---

## VM Multi-Disk Support

### Configuration Structure (2026-01-15)

```yaml
vm_default_storage: ""  # Fallback storage pool (auto-select if empty)
vm_scsi_controller: "virtio-scsi-single"
vm_disks:
  - size: 32            # Boot disk (always scsi0)
    cache: "none"
    ssd: true
    discard: "on"
    iothread: true
    backup: true
  - size: 100           # Additional disk (scsi1)
    bus: scsi
  - size: 500           # Another disk (sata0)
    bus: sata
    backup: false
```

### Disk Properties

| Property | Type | Default | Description |
| ---------- | ------ | --------- | ------------- |
| size | int | - | **Required**: Disk size in GiB |
| bus | str | scsi | Bus type: scsi, sata, virtio, ide (ignored for boot disk) |
| storage | str | "" | Storage pool (empty = vm_default_storage) |
| cache | str | none | Cache mode: none, writethrough, writeback, directsync, unsafe |
| ssd | bool | true | SSD emulation |
| discard | str | on | TRIM support: on, ignore |
| iothread | bool | true | Dedicated IO thread |
| backup | bool | true | Include in Proxmox backups |
| mp | str | "" | Guest mount point for cloud-init disk setup (additional disks only) |

### Key Implementation Details

- First disk = boot disk (scsi0), receives cloud image import
- Additional disks use specified bus type with auto-indexed identifiers
- Properties inherit from boot disk unless overridden
- Storage priority: `disk.storage` > `vm_default_storage` > auto-select

### Disk Index Calculation

For mixed bus types:

```yaml
disk: >-
  {{ item.bus | default('scsi') }}{{
    (count_same_bus_before_current)
    + (1 if bus == 'scsi' else 0)  # scsi starts at 1 (scsi0=boot)
  }}
```

---

## Proxmox Node Name vs Ansible Inventory Hostname

### The Problem (2026-01-21)

The Ansible inventory hostname (`pve_host`) may differ from the actual Proxmox cluster node name. The Proxmox API `node:` parameter requires the **cluster node name**, not the inventory hostname.

**Example:**

- Ansible inventory: `pve` (env-agnostic, single entry)
- Actual Proxmox node: set via `PVE_NODE_NAME` mise env var

### Solution: `proxmox_node_name` Variable

Add `proxmox_node_name` to each Proxmox host in inventory:

```yaml
# inventory/{env}/hosts.yml
proxmox:
  hosts:
    pve:
      ansible_host: "{{ lookup('env', 'PVE_HOST_ADDR') }}"
      proxmox_node_name: "{{ lookup('env', 'PVE_NODE_NAME') }}"
```

### API `node:` Parameter Pattern

| Operation Type | Node Parameter |
|----------------|----------------|
| API queries (reconciliation) | **Omit** `node:` - queries all nodes in cluster |
| API operations (delete/start) | `node: "{{ hostvars[pve_host].proxmox_node_name \| default(pve_host) }}"` |
| Shell commands | `delegate_to: "{{ pve_host }}"` (uses SSH via ansible_host) |

**Query example (no node):**

```yaml
- community.proxmox.proxmox_vm_info:
    api_host: "{{ proxmox_api_host }}"
    # node: OMITTED - queries all nodes
    type: qemu
```

**Operation example (with node lookup):**

```yaml
- community.proxmox.proxmox_kvm:
    node: "{{ hostvars[pve_host].proxmox_node_name | default(pve_host) }}"
    vmid: "{{ vm_vmid }}"
    state: started
```

**Purge pattern (extract node from API result):**

```yaml
# Query returns actual node name in response
__purge_node: "{{ __target_resource.node }}"

# Use extracted node for deletion
- community.proxmox.proxmox_kvm:
    node: "{{ __purge_node }}"
    state: absent
```

### Finding Proxmox Node Name

```bash
# On the Proxmox host
hostname  # This is the cluster node name

# Or check Proxmox UI: Datacenter → Nodes
```

---

## API & Module Quirks

### proxmox_disk Module

| Issue | Solution |
| ------- | ---------- |
| Size parameter | Number WITHOUT suffix (`32` not `32G`) |
| New disk creation | Use `create: regular` |
| Password auth with module_defaults | Explicitly `omit` token params |

### Vault Variable Resolution

~~Resolved~~: Each environment now has one PVE host, so vault variables use generic names (`vault_proxmox_token_secret`) directly. No dynamic lookup needed.

### Common API Errors

| Error | Cause | Fix |
| ------- | ------- | ----- |
| `missing required arguments: api_user` | Omitting api_user | Always include - required even for token auth |
| `401: no such user ('user!user')` | Full token ID | Use only token name: `homeops` not `ansible@pve!homeops` |
| `Connection refused localhost:8006` | Wrong API host | Use `hostvars[pve_host].ansible_host` |
| `Node X doesn't exist in PVE cluster` | Inventory hostname ≠ node name | Add `proxmox_node_name` to inventory or omit `node:` for queries |
| YAML corruption after lint | `combine()` with module args | Use inline parameters, not `{{ auth_dict \| combine({...}) }}` |

### Disk Operations (Require Password Auth)

Token auth doesn't support disk operations - must use root@pam:

```yaml
community.proxmox.proxmox_disk:
  api_host: "{{ proxmox_api_host }}"
  api_user: "root@pam"
  api_password: "{{ proxmox_api_password }}"
  api_token_id: "{{ omit }}"
  api_token_secret: "{{ omit }}"
```

---

## Useful Patterns

### Filter Disabled Resources

APIs return all resources including disabled ones:

```yaml
enabled_resources: >-
  {{ api_response.resources | rejectattr('disable', 'defined') }}
```

### Filesystem Over Command Parsing

**Prefer**:

```yaml
pvesm path storage:vztmpl/template  # Returns path or fails
```

**Avoid**:

```yaml
pveam list storage | grep -q "template"  # Fragile parsing
```

### Version-Aware Template Selection

```bash
pveam available | grep "debian-12" | awk '{print $2}' | sort -V | tail -1
```

Key: `sort -V` = version sort (12.12 > 12.7)

### Multi-Tier IP Discovery

Priority order:

1. **QEMU Agent** - Real-time IP from guest (most reliable)
2. **Cloud-init** - Configured static IP
3. **DNS Resolution** - Hostname-based fallback

### Testing: Purge and Redeploy

Complete validation workflow:

1. Purge existing resources
2. Deploy from scratch
3. Verify resource state
4. Run again (reconciliation test)
5. Verify skipped (idempotency)

---

## Shell Commands (No API)

- Template management: `pveam available`, `pveam download`, `pveam list`
- Guest agent: `qm agent ping`, `qm guest exec`
- Complex creation: `qm create`, `pct create` (shell for full control)

---

## LXC Multi-Disk Support

### Configuration Structure (2026-01-16)

```yaml
lxc_default_storage: ""  # Fallback storage pool (auto-select if empty)
lxc_disks:
  - size: 8             # Rootfs disk (implicit mp="/")
    # storage: ""       # Optional, inherits from lxc_default_storage
    # backup: true

  - size: 100           # Additional storage (mp0)
    mp: "/data"         # REQUIRED for index > 0
    acl: true           # Enable ACL for Samba
    # quota: false

  - size: 50            # Another storage (mp1)
    mp: "/media"
    backup: false
```

### LXC Disk Properties

| Property | Type | Default | Description |
| ---------- | ------ | --------- | ------------- |
| size | int | - | **Required**: Disk size in GiB |
| mp | str | - | Mount point (implicit "/" for rootfs, **required** for additional) |
| storage | str | "" | Storage pool (empty = lxc_default_storage) |
| backup | bool | true | Include in Proxmox backups |
| acl | bool | false | ACL support (useful for Samba) |
| quota | bool | false | Enable disk quota |
| replicate | bool | true | Replication support |
| ro | bool | false | Read-only mount |

### LXC Key Implementation Details

- First disk (index 0) = rootfs, implicit mount at "/"
- Additional disks become mount points: mp0, mp1, mp2...
- Storage priority: `disk.storage` > `lxc_default_storage` > auto-select
- Bind mounts indexed AFTER storage disks

### Mount Point Indexing

```text
Storage disks:  mp0, mp1, mp2...  (from lxc_disks[1:])
Bind mounts:    mp{N}, mp{N+1}... (where N = len(additional_disks))
```

**Example with 2 storage disks + 2 bind mounts**:

```text
lxc_disks[0]     → rootfs (/)
lxc_disks[1]     → mp0 (/data)
lxc_disks[2]     → mp1 (/media)
bind_mounts[0]   → mp2 (/host/path1)
bind_mounts[1]   → mp3 (/host/path2)
```

### Proxmox pct Syntax

```bash
# rootfs (no mp parameter)
--rootfs <storage>:<size>[,acl=<1|0>][,quota=<1|0>][,replicate=<1|0>]

# additional mount points
--mpN <storage>:<size>,mp=<path>[,acl=<1|0>][,backup=<1|0>][,quota=<1|0>][,replicate=<1|0>][,ro=<1|0>]
```

---

## VM Cloud-Init Disk Mounting (2026-02-12)

### The Problem

Unlike LXC where `lxc_disks[n].mp` specifies mount points natively, VM additional disks are only attached as block devices — they are NOT automatically partitioned, formatted, or mounted. Additionally, kernel device enumeration order (`/dev/sdX`) is non-deterministic — the boot disk can land on `/dev/sdb` instead of `/dev/sda`, causing cloud-init to mount the wrong partition.

### Solution: Templatized Vendor Data with Stable Device Paths

The vendor data template (`roles/proxmox/vm/templates/vendor.yml.j2`) derives disk config from `vm_disks` host_vars, using `/dev/disk/by-id/` paths for deterministic device references.

**How it works:**

1. Disks with `mp` defined in `vm_disks[1:]` are collected as mountable disks
2. Each disk's SCSI bus index maps to a stable by-id path
3. Template generates `disk_setup`, `fs_setup`, `mounts`, `bootcmd` sections
4. If no disks have `mp`, disk sections are omitted entirely (vendor data still useful for DNS/packages)

### Device Path Mapping

| vm_disks index | SCSI bus | /dev/disk/by-id/ path |
|----------------|----------|-----------------------|
| 0 | scsi0 | `scsi-0QEMU_QEMU_HARDDISK_drive-scsi0` (boot, never mounted by vendor) |
| 1 | scsi1 | `scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` |
| 2 | scsi2 | `scsi-0QEMU_QEMU_HARDDISK_drive-scsi2` |

Note: assumes all disks use the default `scsi` bus. Mixed bus types produce different by-id paths.

### Example Configuration

```yaml
# inventory/{env}/host_vars/vm/myvm.yml
vm_cicustom_vendor_enabled: true
vm_cicustom_vendor_storage: "local-btrfs"
vm_disks:
  - size: 32    # Boot disk (no mp)
  - size: 100   # Data disk
    mp: "/data"
```

### ZFS Host Optimizations

When Proxmox storage is ZFS-backed:

- `noatime`: reduces writes (ZFS CoW benefits from fewer writes)
- No `discard` mount option: ZFS handles TRIM at pool level
- ext4 filesystem: simple, overlay2-compatible for Docker

### Vendor File Lifecycle

- **Rendered** by `cicustom.yml` task using `ansible.builtin.template`
- **Stored** at `{storage}/snippets/vendor-{hostname}.yml` on Proxmox host
- **Must persist** for VM lifetime (Proxmox regenerates cloud-init ISO on every VM start)
- **Cleaned up** by purge task when VM is destroyed

---

## LXC Network MTU and Tailscale (2026-02)

### The Problem

Setting `lxc_net_mtu` on an LXC container reduces the **physical** eth0 MTU. If Tailscale runs inside the container, its WireGuard tunnel (MTU 1280) encapsulates packets with ~60-80 bytes overhead. When eth0 MTU is too small (e.g., 1230), the encapsulated packets exceed the physical MTU and are silently dropped.

**Symptom**: Tailscale pings work (small ICMP), but gRPC/TLS connections fail with "context deadline exceeded while waiting for connections to become ready". Docker Swarm join is the most common victim.

### MTU Stack

```text
Application (Docker Swarm Raft/gRPC)
    ↓ up to 1280 bytes
tailscale0 (MTU 1280)
    ↓ + ~80 bytes WireGuard overhead = ~1360 bytes
eth0 (physical MTU must be >= 1360)
    ↓
Proxmox bridge
```

### Rules

- **`lxc_net_mtu`**: Controls the Proxmox-level physical interface MTU. Leave empty (`""`) to use bridge default (1500) when Tailscale runs inside the container.
- **`docker_mtu`**: Controls Docker's internal bridge/overlay MTU (set in daemon.json). This is where the 1230 value belongs (Tailscale 1280 - VXLAN 50).
- **Never** set `lxc_net_mtu` below 1400 on containers running Tailscale.

### Diagnosis

```bash
# Inside LXC: test path MTU to Tailscale peer
ping -c 1 -M do -s 1252 <peer_ts_ip>   # 1252 + 28 = 1280 total
# 100% loss = physical MTU too small for Tailscale
```

---

## LXC udev Limitations

LXC containers don't run their own udev daemon — it's managed by the host. Any handler or task that calls `udevadm` (e.g., reloading udev rules after deploying GPU device permissions) must be skipped inside LXC:

```yaml
when: ansible_virtualization_type | default('') != 'lxc'
```

Device access in LXC is controlled by the host's udev + Proxmox device passthrough, so reloading rules inside the container has no effect.

**Affected**: `Docker | Reload udev rules` handler (notified by GPU task).

---

## SSH Keys Management

SSH keys are stored in Ansible vault as `vault_ssh_authorized_keys` (list format):

```yaml
# inventory/{env}/group_vars/all/vault.yml
vault_ssh_authorized_keys:
  - "ssh-ed25519 AAAA... user1@host"
  - "ssh-rsa AAAA... user2@host"
```

Keys are deployed via:

- `roles/common/users/tasks/main.yml` - deploys to managed hosts
- `roles/proxmox/lxc/tasks/create.yml` - stages vault keys on PVE host for pct create, cleans up after
- `roles/proxmox/vm/tasks/create.yml` - stages keys in vm_temp_dir for qm create, cleaned up with temp dir

---

## Files Reference

### VM Role

- `playbooks/group_vars/vm.yml` - vm_disks structure (shared defaults)
- `roles/proxmox/vm/tasks/create.yml` - Multi-disk creation
- `roles/proxmox/vm/tasks/validate.yml` - Disk array validation
- `schemas/vm.schema.json` - JSON schema with vm_disks

### LXC Role

- `playbooks/group_vars/lxc.yml` - lxc_disks structure, lxc_default_storage (shared defaults)
- `roles/proxmox/lxc/tasks/build_pct_command.yml` - Multi-disk command construction
- `roles/proxmox/lxc/tasks/validate.yml` - Disk array validation
- `schemas/lxc.schema.json` - JSON schema with lxc_disks

### Shared

- `roles/proxmox/shared/` - Common tasks for VM/LXC
- `playbooks/group_vars/proxmox.yml` - API credentials (shared defaults)
