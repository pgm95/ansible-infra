# Ansible Infrastructure Automation

Automation for provisioning and configuring VPS servers, Proxmox VMs, LXC containers, and Docker Swarm clusters.
Uses [Terraform](https://github.com/bpg/terraform-provider-proxmox) for Proxmox guest lifecycle and Ansible for guest configuration.
[Mise](https://mise.jdx.dev) handles task management, tool versioning, and environment isolation.
Supports multi-environment deployments (dev/prod) with SOPS + age secret encryption.

## Prerequisites

- [mise](https://mise.jdx.dev)
- Proxmox host accessible via SSH
- VPS if public-facing host is needed
- Tailscale for hosts that need it

## Getting Started

```bash
git clone <repo-url> && cd ansible-infra
mise trust && mise run env:setup
mise run sops:init
mise run validate
```

## Architecture

### Responsibility Boundary

**Terraform** owns Proxmox guest lifecycle. Resource definitions (VMIDs, disk layouts, network, device passthrough, bind mounts) live in `terraform/locals.tf`. Environment scoping uses Terraform workspaces aligned to `MISE_ENV`.

**Ansible** owns guest provisioning and configuration, i.e. everything after the guest exists and is reachable via SSH.

### Environment Separation

`MISE_ENV` (dev/prod) controls the active environment via mise's profile system.
All env-specific values and secrets come from mise profile configs (`.mise/config.<env>.toml`).

Terraform uses workspaces (`TF_WORKSPACE`) aligned to `MISE_ENV` for state isolation.

Ansible is fully environment-agnostic. A single inventory serves both environments.
  > If an Ansible var needs to differ per environment, use `lookup('env', 'VAR')`.

### Variable Precedence

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`ansible/roles/*/defaults/main.yml`): internal and computed variables
2. **Group vars** (`ansible/group_vars/`): shared defaults per host type
3. **Host-Specific** (`ansible/host_vars/`): per-host overrides
4. **Command-Line** (`--extra-vars`): runtime overrides (highest priority)

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

Secrets are managed with SOPS + age and loaded as environment variables by mise's `_.file` directive.

- Ansible consumes them via `lookup('env', ...)` in vars.
- Terraform consumes them via `TF_VAR_*` env vars.

| Secret | Location | In Git |
|--------|----------|--------|
| Shared secrets | `.secrets/shared.sops.yaml` | Yes (encrypted) |
| Dev secrets | `.secrets/dev.sops.yaml` | Yes (encrypted) |
| Prod secrets | `.secrets/prod.sops.yaml` | Yes (encrypted) |
| Age private key | `age.key` | No (gitignored) |

  > Use `mise run sops:edit <file>` to edit secrets.

## Playbook Design

### VPS Provisioning (`vps.yml`)

Single-play playbook that connects to VPS hosts via SSH and applies system, network, and application roles. Uses a hybrid `tasks:` + `roles:` execution pattern. SSH hardening runs in `tasks:` with an immediate handler flush (to avoid lock-out mid-play), while remaining roles run in the standard `roles:` section.

First-time provisioning uses password auth (`mise run vps:first-run`), which overrides `ansible_host` with the public IP.
Subsequent runs use key-based auth over Tailscale MagicDNS hostnames.

### LXC and VM Provisioning (`lxc.yml`, `vm.yml`)

Single-play playbooks that connect to guests via SSH and apply provisioning roles. Guest lifecycle (create/destroy) is managed by Terraform - these playbooks only handle configuration after the guest exists.

Each playbook:

- Filters hosts by `env_scope` via shared `filter_env.yml` in pre_tasks
- Applies roles: SSH, users, packages, Docker, Tailscale, etc.
- LXC-specific roles include Samba; VM-specific roles include DNS, NTP

Individual deploy tasks (`lxc:deploy`, `vm:deploy`) run Ansible only. Use `mise run site:deploy` to chain `tf:apply` before all provisioning.

### Docker Swarm (`swarm.yml`)

Swarm requires cross-host orchestration that doesn't fit the standard provision-per-host pattern, so it uses a dedicated four-play playbook:

1. **Discover** (localhost): iterates inventory groups for `docker_swarm_enabled: true`, validates exactly one init node with `docker_swarm_init: true`, and registers hosts to the dynamic `swarm` group.
2. **Bootstrap** (`hosts: swarm`, `serial: 1`): includes the `applications/docker` role's `swarm` tasks. Each node reads its own Swarm state via `docker info`, picks one action (init / join / tokens / noop), and applies labels and availability.
3. **Display Cluster Status** (localhost, `tags: [status]`): queries the init manager and prints a node summary; warns on any non-Ready nodes. Runs as part of `swarm:deploy` and standalone via `swarm:status`.
4. **Reset** (`hosts: swarm`, parallel, `tags: [reset, never]`): every reachable node force-leaves whatever swarm it is in. Tears down the cluster entirely; safe to re-bootstrap immediately after.

Swarm supports heterogeneous clusters spanning LXC, VM, and VPS nodes. The daemon.json is computed from individual variables (e.g., `docker_mtu`, `docker_data_root`) with empty value filtering, so there is no need to override the full config dict per host.

#### Things to Watch Out For

**Serial bootstrap is mandatory.** The bootstrap play runs `serial: 1`. Parallel joins can cause split-brain during Raft elections.

**MTU matters.** When running Swarm over Tailscale, set `docker_mtu` to the Tailscale interface MTU (`1280`), not the overlay MTU. Docker subtracts the VXLAN 50-byte overhead itself, so a value of `1280` yields a `1230` overlay MTU. Setting `docker_mtu: 1230` double-counts the subtraction and produces a broken `1180` overlay.

Set `docker_mtu` in each swarm node's host_vars (applied during provisioning via `lxc:deploy`/`vm:deploy`/`vps:deploy`). The swarm playbook does not write daemon.json, so daemon config variables in swarm group_vars have no effect.

**VXLAN on public IPs.** Docker Swarm binds VXLAN (port 4789/UDP) to `0.0.0.0` regardless of `--data-path-addr`. On nodes with public IPs, set `docker_swarm_vxlan_interface: tailscale0` to restrict overlay traffic to the VPN interface via iptables.

**State is read via `docker info`.**
The role avoids `community.docker.docker_swarm_info` for discovery as the module conflates "not in swarm" and "worker member" into the same error without populating local-state fields.

## Adding New Hosts

### VPS

1. Add the host to `ansible/hosts.yml` under the `vps` group.
2. Create `ansible/host_vars/<hostname>.yml`.
3. Ensure `VPS_PUBLIC_IP` is set in the environment's SOPS secrets (`.secrets/{dev,prod}.sops.yaml`).
4. Run `mise run vps:first-run` for initial password-based provisioning (connects via public IP automatically).

### LXC Container

1. Add the resource definition to `terraform/locals.tf` (`lxc_definitions` map).
2. Add the host to `ansible/hosts.yml` under the `lxc` group.
3. Create `ansible/host_vars/<hostname>.yml` with provisioning variables.
4. Run `mise run lxc:deploy` (or `mise run site:deploy` to chain `tf:apply` first).

### Virtual Machine

1. Add the resource definition to `terraform/locals.tf` (`vm_definitions` map).
2. Add the host to `ansible/hosts.yml` under the `vm` group.
3. Create `ansible/host_vars/<hostname>.yml` with provisioning variables.
4. Run `mise run vm:deploy` (or `mise run site:deploy` to chain `tf:apply` first).

### Swarm Node

1. In the host's existing host_vars, set `docker_swarm_enabled: true`, `docker_swarm_role: manager` (or `worker`), and `docker_swarm_advertise_addr` to a literal IP.
2. Exactly one node must have `docker_swarm_init: true` and `docker_swarm_role: manager`.
3. Run `mise run swarm:deploy`.

## Validation

`mise run validate` runs all hooks configured in [pre-commit](.config/pre-commit.yaml)

A [JSON schema](`ansible/schemas/host.schema.json`) validates host_vars structure covering all role variables.

## Mise Task Reference

  > All operations go through mise; avoid running `ansible-playbook` or `terraform` directly, as mise manages paths, secrets, and environment variables.

```bash
mise run env:setup            # Install tools, collections, hooks
mise run validate             # Lint, schema check, secrets scan
mise run info                 # Display system facts
mise run sops:edit            # Edit shared secrets in editor

mise run site:deploy          # Full deploy (TF apply + all groups + swarm)
mise run vps:first-run        # First-time VPS deploy (password auth)
mise run vps:deploy           # Provision VPS hosts
mise run lxc:deploy           # LXC provisioning
mise run vm:deploy            # VM provisioning

mise run swarm:deploy         # Bootstrap/update Swarm cluster
mise run swarm:check          # Dry-run Swarm bootstrap
mise run swarm:status         # Display cluster status
mise run swarm:reset          # Tear down Swarm cluster

mise run tf:plan              # Preview Terraform changes
mise run tf:apply             # Apply Terraform changes
mise run tf:destroy           # Destroy all TF-managed resources
```
