# Ansible Infrastructure Automation

Automation for provisioning and configuring VPS servers, Proxmox VMs, LXC containers, and Docker Swarm clusters. Uses [Terraform](https://www.terraform.io/) (bpg/proxmox provider) for Proxmox guest lifecycle and [Ansible](https://docs.ansible.com/) for guest configuration. [Mise](https://mise.jdx.dev) handles task management, tool versioning, and environment isolation. Supports multi-environment deployments (dev/prod) with SOPS + age secret encryption.

## Prerequisites

- [mise](https://mise.jdx.dev), which automatically installs ansible-core (via pipx), terraform, uv, shellcheck, and pre-commit
- Proxmox host accessible via SSH (for Terraform provider)
- Tailscale (for Swarm clusters communicating over WAN)

## Getting Started

```bash
git clone <repo-url> && cd ansible-infra
mise trust && mise run env:setup
mise run sops:init
mise run validate
```

## Architecture

### Responsibility Boundary

**Terraform** owns Proxmox guest lifecycle (create/destroy). Resource definitions (VMIDs, disk layouts, network, device passthrough, bind mounts) live in `terraform/locals.tf`. Environment scoping uses Terraform workspaces aligned to `MISE_ENV`.

**Ansible** owns guest provisioning - everything after the guest exists and is reachable via SSH. Playbooks are single-play, connecting directly to hosts and applying roles (SSH hardening, users, packages, Docker, Tailscale, etc.).

LXC and VM deploy tasks chain both tools: `mise run lxc:deploy` runs `tf:apply` first (idempotent, fast when no changes), then `ansible-playbook`.

### Directory Structure

```text
.
├── .config/             # Linting, sops, and pre-commit configurations
├── terraform/
│   ├── locals.tf        # Guest definitions (VMID, disks, network, devices)
│   ├── lxc.tf           # LXC resource logic with dynamic blocks
│   ├── vm.tf            # VM resource logic + vendor data snippet
│   ├── images.tf        # OS template and cloud image downloads
│   ├── providers.tf     # bpg/proxmox provider config
│   ├── variables.tf     # Input variables
│   └── templates/       # Cloud-init vendor data template
├── ansible/
│   ├── hosts.yml        # All hosts defined statically
│   ├── host_vars/       # Per-host provisioning configs (flat directory)
│   ├── group_vars/      # Group defaults (auto-loaded by Ansible)
│   ├── playbooks/       # Playbooks
│   ├── roles/
│   │   ├── common/      # Base system (packages, users, ssh, dotfiles, hostname, qemu_agent, swap)
│   │   ├── network/     # Network config (dns, ntp, interface)
│   │   └── applications/ # Services (docker, tailscale, samba)
│   └── schemas/         # JSON schema for host_vars validation (host.schema.json)
├── .secrets/            # SOPS-encrypted secrets (committed), age key (gitignored)
└── .mise/
    ├── config.toml      # Tool versions, env vars, inline tasks
    ├── config.dev.toml  # Dev-specific env vars (Proxmox addr, VPS addr, secrets)
    ├── config.prod.toml # Prod-specific env vars
    ├── scripts/         # Shared deploy script
    └── tasks/           # TOML task definitions
```

### Environment Separation

`MISE_ENV` controls the active environment via mise's native profile system. Default: `dev` (set in `.config/miserc.toml`).

```bash
MISE_ENV=prod mise run lxc:deploy    # Inline override
```

Ansible is fully environment-agnostic. All env-specific values (Proxmox address, VPS address, secrets) come from mise profile configs (`.mise/config.dev.toml`, `.mise/config.prod.toml`). Terraform uses workspaces (`TF_WORKSPACE`) aligned to `MISE_ENV` for state isolation. A single unified inventory serves both environments.

- **Inventory** (`ansible/hosts.yml`): static host definitions with `lookup('env', ...)` for env-specific values
- **Host vars** (`ansible/host_vars/`): single file per host, shared across environments
- **Secrets** (`.secrets/*.sops.yaml`): SOPS-encrypted with age, auto-decrypted by mise into env vars

### Variable Precedence

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`ansible/roles/*/defaults/main.yml`): internal and computed variables
2. **Group vars** (`ansible/group_vars/`): shared defaults per host type
3. **Host-Specific** (`ansible/host_vars/`): per-host overrides
4. **Command-Line** (`--extra-vars`): runtime overrides (highest priority)

> **Important:** If a variable needs to differ per environment, use `lookup('env', 'VAR')` in host_vars with the value provided by mise profiles.

### Inventory

All hosts are defined statically in `ansible/hosts.yml`. Host_vars are auto-loaded from the flat `ansible/host_vars/` directory (filename matches hostname).

| Group | Type | Description |
|-------|------|-------------|
| `vps` | Static | VPS/bare-metal hosts |
| `lxc` | Static | Proxmox LXC containers (lifecycle via Terraform) |
| `vm` | Static | Proxmox VMs (lifecycle via Terraform) |
| `swarm` | Dynamic | Populated at runtime by `swarm.yml` discovery |

The **swarm** group is assembled at runtime by iterating all inventory groups and filtering for `docker_swarm_enabled: true`. Hosts with `env_scope` not matching `MISE_ENV` are skipped.

### Secrets

Secrets are managed with SOPS + age and loaded as environment variables by mise's `_.file` directive. Ansible consumes them via `lookup('env', ...)` in group_vars and host_vars. Terraform consumes them via `TF_VAR_*` env vars. Roles never reference the secrets backend directly.

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

### LXC and VM Provisioning (`lxc.yml`, `vm.yml`)

Single-play playbooks that connect to guests via SSH and apply provisioning roles. Guest lifecycle (create/destroy) is managed by Terraform - these playbooks only handle configuration after the guest exists.

Each playbook:

- Filters hosts by `env_scope` via `meta: end_host` in pre_tasks
- Applies roles: SSH, users, packages, Docker, Tailscale, etc.
- LXC-specific roles include Samba; VM-specific roles include QEMU guest agent, DNS, NTP

The `lxc:deploy` and `vm:deploy` mise tasks chain `tf:apply` before running the playbook, ensuring guests exist before provisioning.

### Docker Swarm (`swarm.yml`)

Swarm requires cross-host orchestration that doesn't fit the standard provision-per-host pattern, so it uses a dedicated seven-play playbook:

1. **Discover**: iterates inventory groups for `docker_swarm_enabled: true`, validates exactly one init node with `docker_swarm_init: true`, and registers hosts to the `swarm` group.
2. **Validate**: verifies Docker is active on all swarm hosts.
3. **Bootstrap** (`serial: 1`): init node creates cluster and retrieves join tokens cached on localhost; remaining nodes join using cached tokens.
4. **Status**: displays cluster info from init node.
5-7. **Reset** (requires explicit `--tags reset`): tears down in order - workers, non-init managers, init node - all with `ignore_unreachable: true`.

Swarm supports heterogeneous clusters spanning LXC, VM, and VPS nodes. The daemon.json is computed from individual variables (e.g., `docker_mtu`, `docker_data_root`) with empty value filtering, so there is no need to override the full config dict per host.

#### Things to Watch Out For

**Serial execution is mandatory.** All bootstrap operations run `serial: 1`. Parallel joins cause split-brain during Raft elections.

**MTU matters.** When running Swarm over Tailscale, the MTU stack is:

```text
tailscale0 (MTU 1280) - VXLAN overhead (50) = Docker MTU 1230
```

`docker_mtu: 1230` must be set in each swarm node's host_vars (applied during provisioning via `lxc:deploy`/`vm:deploy`/`vps:deploy`). Do not set it in `playbooks/group_vars/swarm.yml` - the swarm playbook does not write daemon.json, so daemon config variables there have no effect.

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

For role variables, see `ansible/roles/<name>/defaults/main.yml` and `ansible/roles/<name>/meta/argument_specs.yml`. Roles applied by each playbook are defined in the playbook files; check `ansible/playbooks/*.yml` for the current list.

## Adding New Hosts

### VPS

1. Add the host to `ansible/hosts.yml` under the `vps` group.
2. Create `ansible/host_vars/<hostname>.yml`.
3. Set `VPS_PUBLIC_IP` in the active mise profile (`.mise/config.{dev,prod}.toml`).
4. Run `mise run vps:first-run` for initial password-based provisioning (connects via public IP automatically).

### LXC Container

1. Add the resource definition to `terraform/locals.tf` (`lxc_definitions` map).
2. Add the host to `ansible/hosts.yml` under the `lxc` group.
3. Create `ansible/host_vars/<hostname>.yml` with provisioning variables.
4. Run `mise run lxc:deploy` (chains `tf:apply` → Ansible provisioning).

### Virtual Machine

1. Add the resource definition to `terraform/locals.tf` (`vm_definitions` map).
2. Add the host to `ansible/hosts.yml` under the `vm` group.
3. Create `ansible/host_vars/<hostname>.yml` with provisioning variables.
4. Run `mise run vm:deploy` (chains `tf:apply` → Ansible provisioning).

### Swarm Node

1. In the host's existing host_vars, set `docker_swarm_enabled: true`, `docker_swarm_role: manager` (or `worker`), and `docker_swarm_advertise_addr` to a literal IP.
2. Exactly one node must have `docker_swarm_init: true` and `docker_swarm_role: manager`.
3. Run `mise run swarm:deploy`.

## Validation

```bash
mise run validate
```

Runs all pre-commit hooks: ansible-lint (includes yamllint), shellcheck, check-jsonschema (host_vars schema validation), gitleaks (secret detection), markdownlint-cli2, taplo-lint, terraform_fmt, terraform_validate, and standard checks (trailing whitespace, YAML syntax, large files, private keys, merge conflicts).

A unified JSON schema (`ansible/schemas/host.schema.json`) validates host_vars structure covering all provisioning variables from every role.

## Mise Task Reference

```bash
mise run env:setup                     # Install tools, collections, hooks
mise run validate                      # Lint, schema check, secrets scan
mise run info                          # Display system facts
mise run sops:edit                     # Edit shared secrets in editor

mise run vps:first-run [password]      # First-time VPS deploy (password auth)
mise run vps:deploy [hosts] [tags]     # Provision VPS hosts
mise run lxc:deploy [hosts] [tags]     # TF apply + LXC provisioning
mise run vm:deploy [hosts] [tags]      # TF apply + VM provisioning

mise run swarm:deploy                  # Bootstrap/update Swarm cluster
mise run swarm:reset                   # Tear down Swarm cluster

mise run tf:plan                       # Preview Terraform changes
mise run tf:apply                      # Apply Terraform changes
mise run tf:destroy                    # Destroy all TF-managed resources
```

Deploy commands are interactive when `[hosts]` and `[tags]` are omitted, prompting for selection. All operations go through mise; avoid running `ansible-playbook` or `terraform` directly, as mise manages paths, secrets, and environment variables.
