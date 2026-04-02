# Proxmox Patterns

Rules and constraints for Proxmox VM/LXC automation.

## Required Variables

Every VM/LXC host_vars file must include:

```yaml
pve_host: pve            # REQUIRED — must be in proxmox group
lxc_vmid: "300"          # REQUIRED — explicit, no auto-assign
lxc_hostname: "mycontainer"
```

**Why no auto-assign**: Auto-assignment creates unpredictable identifiers, breaking reconciliation.

## Proxmox Node Name

The inventory hostname (`pve`) is environment-agnostic. The actual Proxmox address and cluster node name come from mise env vars (`PVE_HOST_ADDR`, `PVE_NODE_NAME`), set in `hosts.yml` via `lookup('env', ...)`.

## API `node:` Parameter Rules

| Operation Type | Node Parameter |
|----------------|----------------|
| API queries (reconciliation) | **Omit** `node:` — queries all nodes in cluster |
| API operations (delete/start) | `node: "{{ hostvars[pve_host].proxmox_node_name \| default(pve_host) }}"` |
| Shell commands | `delegate_to: "{{ pve_host }}"` (uses SSH via ansible_host) |
| Purge operations | Extract node from API result: `__purge_node: "{{ __target_resource.node }}"` |

## Authentication

### Token Auth (Default)

```yaml
# playbooks/group_vars/proxmox.yml
proxmox_api_user: "ansible@pve"
proxmox_api_token_id: "homeops"        # Token name only, not "ansible@pve!homeops"
proxmox_api_host: "{{ hostvars[pve_host].ansible_host }}"
proxmox_api_token_secret: "{{ hostvars[pve_host].proxmox_api_token_secret }}"
```

### Password Auth (Disk Operations Only)

Token auth doesn't support disk operations — must use root@pam:

```yaml
community.proxmox.proxmox_disk:
  api_host: "{{ proxmox_api_host }}"
  api_user: "root@pam"
  api_password: "{{ proxmox_api_password }}"
  api_token_id: "{{ omit }}"
  api_token_secret: "{{ omit }}"
```

## Reconciliation

### Hash-Based Identifiers

```
ansible_id = sha256(hostname + vmid)[:8]
```

Stored as Proxmox tag. Deterministic, persistent, queryable.

### Matching Logic

| Condition | Action |
|-----------|--------|
| Matched by ansible_id tag | SKIP (managed, exists) |
| Matched by VMID only | SKIP + warn if mismatch |
| No match | CREATE |

### State Machine

```
DEFINED + EXISTS (matching ansible_id) → SKIP (provision)
DEFINED + EXISTS (matching vmid)       → SKIP (provision + warn)
DEFINED + NOT_EXISTS                   → CREATE
NOT_DEFINED + EXISTS (has ansible_id)  → WARN (orphan)
NOT_DEFINED + EXISTS (no ansible_id)   → IGNORE (unmanaged)
```

## VM Multi-Disk Configuration

```yaml
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

- First disk = boot disk (scsi0), receives cloud image import.
- Additional disks use specified bus type with auto-indexed identifiers.
- Properties inherit from boot disk unless overridden.
- Storage priority: `disk.storage` > `vm_default_storage` > auto-select.

## LXC Multi-Disk Configuration

```yaml
lxc_disks:
  - size: 8             # Rootfs (implicit mp="/")
  - size: 100           # Additional (mp0)
    mp: "/data"         # REQUIRED for index > 0
    acl: true
  - size: 50            # Another (mp1)
    mp: "/media"
    backup: false
```

- First disk (index 0) = rootfs, implicit mount at "/".
- `mp` is **required** for additional disks.
- Mount point indexing: storage disks first (mp0, mp1...), then bind mounts continue the sequence.

## Cloud-Init Vendor Data

For VMs with additional disks that need mounting:

```yaml
vm_cicustom_vendor_enabled: true
vm_cicustom_vendor_storage: "local-btrfs"
```

- Template derives disk config from `vm_disks` host_vars.
- Uses `/dev/disk/by-id/` paths for deterministic device references (avoids `/dev/sdX` enumeration issues).
- Vendor file must persist for VM lifetime (Proxmox regenerates cloud-init ISO on every start).
- Cleaned up by purge task when VM is destroyed.

## Common API Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `missing required arguments: api_user` | Omitting api_user | Always include — required even for token auth |
| `401: no such user ('user!user')` | Full token ID | Use only token name: `homeops` not `ansible@pve!homeops` |
| `Connection refused localhost:8006` | Wrong API host | Use `hostvars[pve_host].ansible_host` |
| `Node X doesn't exist in PVE cluster` | Inventory hostname ≠ node name | Add `proxmox_node_name` or omit `node:` for queries |

## Useful Patterns

### Filter Disabled Resources

```yaml
enabled_resources: >-
  {{ api_response.resources | rejectattr('disable', 'defined') }}
```

### Filesystem Over Command Parsing

```yaml
# Prefer
pvesm path storage:vztmpl/template

# Avoid
pveam list storage | grep -q "template"
```

### SSH Key Deployment

Keys staged on PVE host during create, cleaned up after:
- LXC: staged in host temp dir for `pct create`
- VM: staged in `vm_temp_dir` for `qm create`, cleaned with temp dir

## Key Files

| File | Purpose |
|------|---------|
| `playbooks/group_vars/proxmox.yml` | API credentials (shared defaults) |
| `playbooks/group_vars/vm.yml` | vm_disks structure defaults |
| `playbooks/group_vars/lxc.yml` | lxc_disks structure defaults |
| `roles/proxmox/vm/tasks/create.yml` | VM multi-disk creation |
| `roles/proxmox/lxc/tasks/build_pct_command.yml` | LXC multi-disk command |
| `roles/proxmox/shared/` | Common tasks for VM/LXC |
| `schemas/vm.schema.json` | VM host_vars validation |
| `schemas/lxc.schema.json` | LXC host_vars validation |
