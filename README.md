# Ansible Infrastructure Automation

Ansible-based automation for provisioning and configuring VPS servers, Proxmox VMs, LXC containers, and Docker Swarm clusters. Uses [mise](https://mise.jdx.dev) for task management, tool versioning, and environment isolation. Supports multi-environment deployments (dev/prod) with per-environment vault encryption.

## Quick Reference

```bash
mise run env:setup                     # Install tools, collections, hooks
mise run validate                      # Lint, schema check, secrets scan

mise run vps:deploy [hosts] [tags]     # Provision VPS hosts
mise run vps:first-run [password]      # First-time VPS deploy (password auth)
mise run lxc:deploy [hosts] [tags]     # Deploy LXC containers
mise run vm:deploy [hosts] [tags]      # Deploy VMs
mise run swarm:deploy                  # Bootstrap/update Swarm cluster

mise run lxc:purge                     # Destroy LXC containers
mise run vm:purge                      # Destroy VMs
mise run swarm:reset                   # Tear down Swarm cluster

mise run info                          # Display system facts
mise run vault                         # Edit vault in editor
```

Deploy commands are interactive when `[hosts]` and `[tags]` are omitted, prompting for selection. All operations go through mise; never run `ansible-playbook` directly, as mise manages paths, vault keys, and environment variables.

## Prerequisites

- [mise](https://mise.jdx.dev), which automatically installs ansible-core (via pipx), uv, shellcheck, and pre-commit
- SSH access to target hosts
- Proxmox API token (for VM/LXC targets)
- Tailscale (for Swarm clusters communicating over WAN)

## Getting Started

```bash
git clone <repo-url> && cd ansible-infra
mise trust && mise run env:setup
echo "your-vault-password" > secrets/vault-dev.key
mise run validate
```

## Architecture

### Directory Structure

```text
.
├── config/              # Ansible, lint, and pre-commit configuration
├── inventory/
│   ├── dev/             # Dev environment
│   │   ├── hosts.yml    # Static hosts (vps, proxmox)
│   │   ├── host_vars/   # Per-host configs (lxc/, vm/, and static host files)
│   │   └── group_vars/  # Environment-specific group vars and vault
│   └── prod/            # Prod environment (same structure)
├── playbooks/
│   ├── group_vars/      # Shared defaults across environments
│   ├── tasks/           # Shared discovery tasks
│   └── *.yml            # Playbooks (vps, lxc, vm, swarm, get-facts)
├── roles/
│   ├── common/          # Base system (packages, users, ssh, dotfiles, hostname, qemu_agent, swap)
│   ├── network/         # Network config (dns, ntp, interface)
│   ├── applications/    # Services (docker, tailscale, samba)
│   └── proxmox/         # VM/LXC lifecycle + shared reconciliation tasks
├── schemas/             # JSON schemas for host_vars validation
├── secrets/             # Vault keys and .env (gitignored)
└── .mise/
    ├── config.toml      # Tool versions, env vars, inline tasks
    ├── scripts/         # Shared deploy script
    └── tasks/           # Per-group TOML task definitions
```

> **Note:** `host_vars/` is gitignored. Host definitions contain environment-specific details and are not tracked in the repository. Distribute them through a secure channel or maintain them locally.

### Environment Separation

`PROJECT_ENV` controls the active environment. Default: `dev` (safe).

```bash
PROJECT_ENV=prod mise run lxc:deploy    # Inline override
```

Each environment maintains independent state:

- **Inventory** (`inventory/{env}/hosts.yml`): static host definitions
- **Host vars** (`inventory/{env}/host_vars/`): per-host configuration
- **Vault** (`inventory/{env}/group_vars/all/vault.yml`): encrypted secrets
- **Vault key** (`secrets/vault-{env}.key`): decryption password (gitignored)

You can also set `PROJECT_ENV` in `secrets/.env` (auto-loaded by mise).

### Variable Precedence

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`roles/*/defaults/main.yml`): internal and computed variables
2. **Inventory group_vars** (`inventory/{env}/group_vars/`): environment-specific values, including vault
3. **Playbook group_vars** (`playbooks/group_vars/`): shared defaults across environments
4. **Host-Specific** (`inventory/{env}/host_vars/`): per-host overrides
5. **Play vars_files**: loaded explicitly in plays (higher than all group/host vars)
6. **Command-Line** (`--extra-vars`): runtime overrides (highest priority)

> **Important:** Never define the same variable at both inventory and playbook group_vars levels. If a shared variable needs to differ per environment, move it from `playbooks/group_vars/` to both `inventory/dev/group_vars/` and `inventory/prod/group_vars/`.

### Inventory and Host Discovery

| Group | Type | Source |
|-------|------|--------|
| `vps` | Static | Defined in `inventory/{env}/hosts.yml` |
| `proxmox` | Static | Defined in `inventory/{env}/hosts.yml` |
| `vm` | File-based | Discovered from `inventory/{env}/host_vars/vm/*.yml` |
| `lxc` | File-based | Discovered from `inventory/{env}/host_vars/lxc/*.yml` |
| `swarm` | Dynamic | Populated at runtime by the `swarm.yml` discovery play |

**Static groups** (vps, proxmox) require entries in `hosts.yml`. **File-based groups** (vm, lxc) need no inventory editing: drop a YAML file in the right `host_vars/` subdirectory and the discovery play finds it automatically via `add_host`. The **swarm** group is assembled at runtime by scanning all host_vars directories for `docker_swarm_enabled: true`.

### Secrets

| Secret | Location | In Git |
|--------|----------|--------|
| Encrypted vault | `inventory/{env}/group_vars/all/vault.yml` | Yes (encrypted) |
| Vault password | `secrets/vault-{env}.key` | No |
| Environment variables | `secrets/.env` | No |
| SSH authorized keys | Inside vault as `vault_ssh_authorized_keys` | Yes (encrypted) |

Mise auto-configures `ANSIBLE_VAULT_PASSWORD_FILE` based on the active environment.

## Playbook Design

### VPS Provisioning (`vps.yml`)

Single-play playbook that connects to VPS hosts via SSH and applies system, network, and application roles. Uses a hybrid `tasks:` + `roles:` execution pattern. SSH hardening runs in `tasks:` with an immediate handler flush (to avoid locking yourself out mid-play), while remaining roles run in the standard `roles:` section.

First-time provisioning uses password auth (`mise run vps:first-run`). Subsequent runs use key-based auth.

### VM and LXC Lifecycle (`vm.yml`, `lxc.yml`)

Both follow a three-play architecture:

1. **Discovery** (localhost): scans `host_vars/{vm,lxc}/` for definition files, registers each host dynamically via `add_host`, and loads its variables with `include_vars` + `delegate_facts`.
2. **Create** (delegated to Proxmox host): each VM/LXC definition specifies `pve_host` (e.g., `pve1`), and creation tasks delegate to that host. Skips resources that already exist (matched by `ansible_id` tag or VMID).
3. **Provision** (SSH to resource): connects to the newly created VM/LXC via DNS-resolved hostname and applies roles (packages, users, ssh, docker, tailscale, etc.).

**VM features**: cloud image auto-download (Debian, Ubuntu), cloud-init for early configuration, QEMU guest agent auto-installation, multi-disk with mixed bus types (SCSI, SATA, VirtIO).

**LXC features**: device passthrough (GPU, USB, TUN) with automatic detection, UID/GID mapping for unprivileged containers, bind mounts, Docker support via nesting.

#### Reconciliation

Resources are matched using a deterministic hash stored as a Proxmox tag:

```text
ansible_id = sha256(hostname + vmid)[:8]
```

This survives hostname or VMID changes and distinguishes managed resources from manually created ones. The state machine:

- **Matched by ansible_id tag** → skip (already managed)
- **Matched by VMID only** → skip + warn (potential mismatch)
- **No match** → create
- **Exists with ansible_id but no definition file** → warn (orphan)

#### Proxmox Credentials

VM/LXC definitions inherit API credentials from their target Proxmox host via `hostvars[pve_host]`. The shared config in `playbooks/group_vars/proxmox.yml` resolves credentials dynamically, so there is no need to duplicate secrets across host_vars files.

```yaml
# In a VM/LXC host_vars file, only this is needed:
pve_host: pve1        # Must exist in the proxmox group
vm_vmid: "200"        # Explicit, never auto-assigned
vm_hostname: "myvm"
```

#### Multi-Disk Support

Both VMs and LXCs support multiple disks via `vm_disks` / `lxc_disks` arrays. The first disk is the boot disk (VMs) or rootfs (LXCs); additional entries become extra SCSI devices or mount points. See `playbooks/group_vars/vm.yml` and `playbooks/group_vars/lxc.yml` for the full schema and defaults.

VMs can optionally generate cloud-init vendor data (`vm_cicustom_vendor_enabled`) that auto-partitions, formats, and mounts additional disks using stable `/dev/disk/by-id/` paths (avoids `/dev/sdX` enumeration issues).

### Docker Swarm (`swarm.yml`)

Swarm requires cross-host orchestration that doesn't fit the standard provision-per-host pattern, so it uses a dedicated five-play playbook:

1. **Discover**: scans all host_vars directories for `docker_swarm_enabled: true`, validates exactly one init node with `docker_swarm_init: true`, and registers hosts to the `swarm` group.
2. **Init**: the init node creates the cluster and retrieves join tokens, which are cached on localhost via `delegate_to` + `set_fact`.
3. **Join managers**: remaining managers join using the cached token (`serial: 1` for Raft consensus safety).
4. **Join workers**: workers join the cluster.
5. **Configure**: applies node labels, availability settings, and VXLAN security rules.

Swarm supports heterogeneous clusters spanning LXC, VM, and VPS nodes. The daemon.json is computed from individual variables (e.g., `docker_mtu`, `docker_data_root`) with empty value filtering, so there is no need to override the full config dict per host.

#### Hardening

- **Pre-flight connectivity checks** before join: forward (joining node to manager:2377) and reverse (init node to joining node:22), both with 60s timeout.
- **Listen address** auto-derives from `docker_swarm_advertise_addr` when set. Falls back to `0.0.0.0:2377` only when no advertise address is configured.
- **Hostname validation** before node label/availability operations verifies `ansible_hostname` matches `inventory_hostname`, preventing silent misapplication if the system hostname diverges.
- **Init-must-be-manager** runtime assertion catches misconfigured nodes (the init node must have `docker_swarm_role: manager`). LXC and VM schemas enforce this via JSON Schema; the runtime check covers VPS hosts.

#### Things to Watch Out For

**Serial execution is mandatory.** All bootstrap operations run `serial: 1`. Parallel joins cause split-brain during Raft elections.

**Advertise addresses must be literals.** The discovery play reads host_vars as raw YAML, so Jinja2 templates are not evaluated. Use `docker_swarm_advertise_addr: 100.88.0.1`, not `docker_swarm_advertise_addr: "{{ tailscale_ip }}"`.

**MTU matters.** When running Swarm over Tailscale, the MTU stack is:

```text
tailscale0 (MTU 1280) - VXLAN overhead (50) = Docker MTU 1230
```

`docker_mtu: 1230` must be set in each swarm node's host_vars (applied during provisioning via `lxc:deploy`/`vm:deploy`/`vps:deploy`). Do not set it in `playbooks/group_vars/swarm.yml` — the swarm playbook does not write daemon.json, so daemon config variables there have no effect. Do not set `lxc_net_mtu` below 1400 on LXC containers running Tailscale, as this reduces the physical interface MTU and breaks WireGuard encapsulation. Symptom: Tailscale pings work but gRPC/TLS connections (like Swarm join) silently fail.

**VXLAN on public IPs.** Docker Swarm binds VXLAN (port 4789/UDP) to `0.0.0.0` regardless of `--data-path-addr`. On nodes with public IPs, set `docker_swarm_vxlan_interface: tailscale0` to restrict overlay traffic to the VPN interface via iptables.

**Join retries.** Don't use Ansible `retries` on the join task. The first attempt starts a background join, and retries see "already part of a swarm". The role handles this with structured recovery (force leave, retry) and background join polling.

**Reset ordering.** Cluster teardown runs in order: workers, then non-init managers, then init node. This is enforced by play structure, not hostname ordering.

## Roles

| Category | Role | Purpose |
|----------|------|---------|
| Common | `packages` | System package management with optional feature flags |
| Common | `users` | User/group management, SSH key deployment, sudo |
| Common | `ssh` | SSH server hardening |
| Common | `dotfiles` | Dotfiles deployment from a Git repository |
| Common | `hostname` | Hostname and FQDN configuration |
| Common | `qemu_agent` | QEMU guest agent (VMs only) |
| Common | `swap` | Swap management |
| Network | `dns` | DNS resolver configuration (systemd-resolved, resolvconf, resolv.conf) |
| Network | `ntp` | NTP time synchronization via systemd-timesyncd |
| Network | `interface` | Network interface configuration (static/DHCP) |
| Application | `docker` | Docker CE, daemon config, optional Swarm mode, GPU support |
| Application | `tailscale` | Tailscale VPN with OAuth auth and API-based IP assignment |
| Application | `samba` | Samba file sharing |
| Infrastructure | `proxmox/vm` | VM lifecycle on Proxmox (create, provision, purge) |
| Infrastructure | `proxmox/lxc` | LXC lifecycle on Proxmox (create, provision, purge) |
| Infrastructure | `proxmox/shared` | Shared reconciliation and state management tasks |

For role variables, see `roles/<name>/defaults/main.yml` and `roles/<name>/meta/argument_specs.yml`. Roles applied by each playbook are defined in the playbook files; check `playbooks/*.yml` for the current list.

## Adding New Hosts

### VPS

1. Add the host to `inventory/{env}/hosts.yml` under the `vps` group.
2. Create `inventory/{env}/host_vars/<hostname>.yml`.
3. Run `mise run vps:first-run` for initial password-based provisioning.

### LXC Container

1. Create `inventory/{env}/host_vars/lxc/<hostname>.yml` with required fields: `pve_host`, `lxc_vmid`, `lxc_hostname`.
2. Run `mise run lxc:deploy`.

No inventory file editing needed. The container is auto-discovered.

### Virtual Machine

1. Create `inventory/{env}/host_vars/vm/<hostname>.yml` with required fields: `pve_host`, `vm_vmid`, `vm_hostname`.
2. Run `mise run vm:deploy`.

No inventory file editing needed. The VM is auto-discovered.

### Swarm Node

1. In the host's existing host_vars, set `docker_swarm_enabled: true`, `docker_swarm_role: manager` (or `worker`), and `docker_swarm_advertise_addr` to a literal IP.
2. Exactly one node must have `docker_swarm_init: true` and `docker_swarm_role: manager`.
3. Run `mise run swarm:deploy`.

## Validation

```bash
mise run validate
```

Runs all pre-commit hooks: ansible-lint (includes yamllint), shellcheck, check-jsonschema (host_vars schema validation), gitleaks (secret detection), markdownlint-cli2, taplo-lint, and standard checks (trailing whitespace, YAML syntax, large files, private keys, merge conflicts).

JSON schemas in `schemas/` validate host_vars structure for `common`, `lxc`, and `vm` groups.

Hook configs live in `config/`. Never run linters directly.

## Roadmap

### Proxmox Host Management (Planned)

- Network bridge/VLAN management
- Backup and snapshot management
- Storage pool configuration
- Backup/restore playbooks

## Config Files

| Config | Location |
|--------|----------|
| Ansible | `config/ansible.cfg` |
| Ansible Lint | `config/ansible-lint.yml` |
| YAML Lint | `config/yamllint.yml` |
| Pre-commit | `config/pre-commit.yaml` |
| Galaxy Requirements | `config/requirements.yml` |
| JSON Schemas | `schemas/*.schema.json` |
| Mise | `.mise/config.toml` |
| Mise Tasks | `.mise/tasks/*.toml` |
