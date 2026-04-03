# Ansible Infrastructure Automation

Ansible-based automation for provisioning and configuring VPS servers, Proxmox VMs, LXC containers, and Docker Swarm clusters. Uses [mise](https://mise.jdx.dev) for task management, tool versioning, and environment isolation. Supports multi-environment deployments (dev/prod) with SOPS + age secret encryption.

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
mise run sops:edit                     # Edit shared secrets in editor
```

Deploy commands are interactive when `[hosts]` and `[tags]` are omitted, prompting for selection. All operations go through mise; never run `ansible-playbook` directly, as mise manages paths, secrets, and environment variables.

## Prerequisites

- [mise](https://mise.jdx.dev), which automatically installs ansible-core (via pipx), uv, shellcheck, and pre-commit
- SSH access to target hosts
- Proxmox API token (for VM/LXC targets)
- Tailscale (for Swarm clusters communicating over WAN)

## Getting Started

```bash
git clone <repo-url> && cd ansible-infra
mise trust && mise run env:setup
# Place age.key at project root (obtain from secure channel)
mise run sops:status    # verify secrets are encrypted
mise run validate
```

## Architecture

### Directory Structure

```text
.
├── .config/             # Ansible, lint, and pre-commit configuration
├── inventory/
│   ├── hosts.yml        # Static hosts (vps, proxmox), env values via lookup('env')
│   ├── host_vars/       # Per-host configs (lxc/, vm/, and static host files)
│   └── group_vars/      # Group defaults and API credentials (auto-loaded by Ansible)
├── playbooks/
│   ├── tasks/           # Shared discovery tasks
│   └── *.yml            # Playbooks (vps, lxc, vm, swarm, get-facts)
├── roles/
│   ├── common/          # Base system (packages, users, ssh, dotfiles, hostname, qemu_agent, swap)
│   ├── network/         # Network config (dns, ntp, interface)
│   ├── applications/    # Services (docker, tailscale, samba)
│   └── proxmox/         # VM/LXC lifecycle + shared reconciliation tasks
├── schemas/             # JSON schemas for host_vars validation
├── .secrets/            # SOPS-encrypted secrets (committed), age key (gitignored)
└── .mise/
    ├── config.toml      # Tool versions, env vars, inline tasks
    ├── config.dev.toml  # Dev-specific env vars (Proxmox addr, VPS addr, secrets)
    ├── config.prod.toml # Prod-specific env vars
    ├── scripts/         # Shared deploy script
    └── tasks/           # Per-group TOML task definitions
```

> **Note:** `host_vars/` is gitignored. Host definitions contain environment-specific details and are not tracked in the repository. Distribute them through a secure channel or maintain them locally.

### Environment Separation

`MISE_ENV` controls the active environment via mise's native profile system. Default: `dev` (set in `.config/miserc.toml`).

```bash
MISE_ENV=prod mise run lxc:deploy    # Inline override
```

Ansible is fully environment-agnostic. All env-specific values (Proxmox address, VPS address, secrets) come from mise profile configs (`.mise/config.dev.toml`, `.mise/config.prod.toml`). A single unified inventory serves both environments.

- **Inventory** (`inventory/hosts.yml`): static host definitions with `lookup('env', ...)` for env-specific values
- **Host vars** (`inventory/host_vars/`): single file per host, shared across environments
- **Secrets** (`.secrets/*.sops.yaml`): SOPS-encrypted with age, auto-decrypted by mise into env vars

### Variable Precedence

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`roles/*/defaults/main.yml`): internal and computed variables
2. **Group vars** (`inventory/group_vars/`): shared defaults, API credentials
3. **Host-Specific** (`inventory/host_vars/`): per-host overrides
4. **Command-Line** (`--extra-vars`): runtime overrides (highest priority)

> **Important:** If a variable needs to differ per environment, use `lookup('env', 'VAR')` in host_vars with the value provided by mise profiles.

### Inventory and Host Discovery

| Group | Type | Source |
|-------|------|--------|
| `vps` | Static | Defined in `inventory/hosts.yml` |
| `proxmox` | Static | Defined in `inventory/hosts.yml` (parent of `lxc` and `vm`) |
| `lxc` | File-based | Child of `proxmox`. Discovered from `inventory/host_vars/lxc/*.yml` |
| `vm` | File-based | Child of `proxmox`. Discovered from `inventory/host_vars/vm/*.yml` |
| `swarm` | Dynamic | Populated at runtime by the `swarm.yml` discovery play |

**Static groups** (vps, proxmox) require entries in `hosts.yml`. **File-based groups** (vm, lxc) need no inventory editing: drop a YAML file in the right `host_vars/` subdirectory and the discovery play finds it automatically via `add_host`. The **swarm** group is assembled at runtime by scanning all host_vars directories for `docker_swarm_enabled: true`. Hosts with `env_scope` are filtered by `MISE_ENV` during discovery.

### Secrets

Secrets are managed with SOPS + age and loaded as environment variables by mise's `_.file` directive. Ansible consumes them via `lookup('env', ...)` in group_vars and host_vars. Roles never reference the secrets backend directly.

| Secret | Location | In Git |
|--------|----------|--------|
| Shared secrets | `.secrets/shared.sops.yaml` | Yes (encrypted) |
| Dev secrets | `.secrets/dev.sops.yaml` | Yes (encrypted) |
| Prod secrets | `.secrets/prod.sops.yaml` | Yes (encrypted) |
| Age private key | `age.key` | No (gitignored) |

`mise run sops:edit` opens secrets in the editor. `mise run sops:status` shows encryption status.

## Playbook Design

### VPS Provisioning (`vps.yml`)

Single-play playbook that connects to VPS hosts via SSH and applies system, network, and application roles. Uses a hybrid `tasks:` + `roles:` execution pattern. SSH hardening runs in `tasks:` with an immediate handler flush (to avoid locking yourself out mid-play), while remaining roles run in the standard `roles:` section.

First-time provisioning uses password auth (`mise run vps:first-run`), which automatically connects via the public IP (`VPS_PUBLIC_IP` from the active mise profile). Subsequent runs use key-based auth over Tailscale (`VPS_ADDR`).

### VM and LXC Lifecycle (`vm.yml`, `lxc.yml`)

Both follow a four-play architecture (discover, create, provision, purge):

1. **Discovery** (localhost): scans `host_vars/{vm,lxc}/` for definition files, registers each host dynamically via `add_host`, and loads its variables with `include_vars` + `delegate_facts`.
2. **Create** (delegated to Proxmox host): each VM/LXC definition specifies `pve_host` (e.g., `pve`), and creation tasks delegate to that host. Skips resources that already exist (matched by `ansible_id` tag or VMID).
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
pve_host: pve         # Must exist in the proxmox group
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
- **Hostname validation** warns if `ansible_hostname` differs from `inventory_hostname`. The unified inventory intentionally decouples these (e.g., `swarm-vps` in inventory vs `nerd1` on the system). Node operations use the system hostname.
- **Init-must-be-manager** runtime assertion catches misconfigured nodes (the init node must have `docker_swarm_role: manager`). LXC and VM schemas enforce this via JSON Schema; the runtime check covers VPS hosts.

#### Things to Watch Out For

**Serial execution is mandatory.** All bootstrap operations run `serial: 1`. Parallel joins cause split-brain during Raft elections.

**Advertise addresses can use Jinja2.** Discovery uses `include_vars` + `delegate_facts`, so Jinja2 templates in host_vars (including `lookup('env', ...)`) are evaluated normally. Literal IPs are still recommended for clarity.

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

1. Add the host to `inventory/hosts.yml` under the `vps` group.
2. Create `inventory/host_vars/<hostname>.yml`.
3. Set `VPS_PUBLIC_IP` in the active mise profile (`.mise/config.{dev,prod}.toml`).
4. Run `mise run vps:first-run` for initial password-based provisioning (connects via public IP automatically).

### LXC Container

1. Create `inventory/host_vars/lxc/<hostname>.yml` with required fields: `pve_host`, `lxc_vmid`, `lxc_hostname`.
2. Run `mise run lxc:deploy`.

No inventory file editing needed. The container is auto-discovered.

### Virtual Machine

1. Create `inventory/host_vars/vm/<hostname>.yml` with required fields: `pve_host`, `vm_vmid`, `vm_hostname`.
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

Hook configs live in `.config/`. Never run linters directly.

## Roadmap

### Proxmox Host Management (Planned)

- Network bridge/VLAN management
- Backup and snapshot management
- Storage pool configuration
- Backup/restore playbooks

## Config Files

| Config | Location |
|--------|----------|
| Ansible | `.config/ansible.cfg` |
| Ansible Lint | `.config/ansible-lint.yml` |
| YAML Lint | `.config/yamllint.yml` |
| Pre-commit | `.config/pre-commit.yaml` |
| Galaxy Requirements | `.config/requirements.yml` |
| JSON Schemas | `schemas/*.schema.json` |
| Mise | `.mise/config.toml` |
| Mise Tasks | `.mise/tasks/*.toml` |
