# Variable Precedence

Rules for the variable hierarchy and inventory organization.

## Precedence Tiers

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`roles/*/defaults/main.yml`) — Internal/computed variables only
2. **Group vars** (`inventory/group_vars/`) — Shared defaults, API credentials
3. **Host-Specific** (`inventory/host_vars/`) — Per-host overrides
4. **Command-Line** (`--extra-vars`) — Runtime overrides (highest priority)

All group_vars live in `inventory/group_vars/`. No playbook-level group_vars or `vars_files`.

## Secrets

Secrets are loaded as environment variables by mise (SOPS + age), not as Ansible group_vars. Group vars and host vars reference them via `lookup('env', 'VAR')`. This means secrets are not part of the Ansible variable precedence hierarchy -- they resolve at task evaluation time through the env lookup.

## Proxmox API Credentials

`inventory/group_vars/proxmox.yml` provides API credentials to all hosts in the `proxmox` group. Since `lxc` and `vm` are children of `proxmox` in the inventory, credentials auto-load for all LXC/VM hosts via group inheritance — no `vars_files` needed.

If a variable needs to differ per-env, use `lookup('env', 'VAR')` in host_vars with the value provided by mise profiles.

## Inventory Organization

### Structure

Single unified inventory at `inventory/`. No per-environment directories — all environment differences are handled by mise env vars.

- `hosts.yml` — Static hosts (`pve`, `swarm-vps`), env-specific values via `lookup('env', ...)`
- `host_vars/` — Per-host variables (single file per host)
- `group_vars/` — All group defaults, API credentials

### Groups

| Group | Type | Source |
|-------|------|--------|
| **vps** | Static | `inventory/hosts.yml` |
| **proxmox** | Static | `inventory/hosts.yml` (parent of `lxc` and `vm`) |
| **lxc** | File-based | Child of `proxmox`. Discovered from `inventory/host_vars/lxc/` |
| **vm** | File-based | Child of `proxmox`. Discovered from `inventory/host_vars/vm/` |
| **swarm** | Dynamic | Populated by `swarm.yml` discovery |

### Host Vars Loading

Two mechanisms:

- **Auto-loaded** (static hosts): Files directly in `host_vars/` whose filename matches a host in `hosts.yml` (e.g., `host_vars/swarm-vps.yml`). No configuration needed.
- **Manually loaded** (dynamic hosts): Files under subdirectories (`host_vars/lxc/`, `host_vars/vm/`) are **not** auto-loaded. The discovery play registers these hosts via `add_host` and loads their variables via `include_vars` with `delegate_facts: true`.

### Environment Scoping

Hosts that only exist in one environment have `env_scope` in their host_vars. Discovery tasks filter by `env_scope` matching `MISE_ENV` — non-matching hosts are never registered to the dynamic group. Hosts without `env_scope` are shared across all environments.
