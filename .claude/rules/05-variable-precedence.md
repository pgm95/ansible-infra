# Variable Precedence

Rules for the variable hierarchy and inventory organization.

## Precedence Tiers

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`roles/*/defaults/main.yml`) — Internal/computed variables only
2. **Inventory group_vars** (`inventory/group_vars/`) — Vault (auto-loaded via symlink)
3. **Playbook group_vars** (`playbooks/group_vars/`) — Shared defaults across environments
4. **Host-Specific** (`inventory/host_vars/`) — Per-host overrides
5. **Play vars_files** — Loaded explicitly in plays; higher than all group_vars and host_vars
6. **Command-Line** (`--extra-vars`) — Runtime overrides (highest priority)

## Partitioning Rule

**Never define the same variable at both inventory and playbook group_vars levels.**

If a variable needs to differ per-env, use `lookup('env', 'VAR')` in host_vars with the value provided by mise profiles.

## Vault

Vault is **not** a separate precedence level. `inventory/group_vars/all/vault.yml` is a symlink to the active `secrets/vault-{env}.yml`, auto-loaded as standard inventory group_vars. The symlink is managed by a mise `enter` hook.

## `vars_files` Caveat

The `lxc.yml` and `vm.yml` plays load `group_vars/proxmox.yml` via `vars_files`, which elevates those variables above inventory host_vars. This is intentional for API credentials, but means **host_vars cannot override variables loaded this way**.

**Do not add new `vars_files` references** unless you understand the precedence implications. Prefer auto-loaded group_vars (tier 2-3) where `add_host` and host_vars win naturally.

## Inventory Organization

### Structure

Single unified inventory at `inventory/`. No per-environment directories — all environment differences are handled by mise env vars.

- `hosts.yml` — Static hosts (`pve`, `swarm-vps`), env-specific values via `lookup('env', ...)`
- `host_vars/` — Per-host variables (single file per host)
- `group_vars/all/vault.yml` — Symlink to active vault (managed by mise hook)

Shared group_vars live at `playbooks/group_vars/` (auto-loaded by Ansible from the playbook directory).

### Groups

| Group | Type | Source |
|-------|------|--------|
| **vps** | Static | `inventory/hosts.yml` |
| **proxmox** | Static | `inventory/hosts.yml` |
| **vm** | File-based | Discovered from `inventory/host_vars/vm/` |
| **lxc** | File-based | Discovered from `inventory/host_vars/lxc/` |
| **swarm** | Dynamic | Populated by `swarm.yml` discovery |

### Host Vars Loading

Two mechanisms:

- **Auto-loaded** (static hosts): Files directly in `host_vars/` whose filename matches a host in `hosts.yml` (e.g., `host_vars/swarm-vps.yml`). No configuration needed.
- **Manually loaded** (dynamic hosts): Files under subdirectories (`host_vars/lxc/`, `host_vars/vm/`) are **not** auto-loaded. The discovery play registers these hosts via `add_host` and loads their variables via `include_vars` with `delegate_facts: true`.

### Environment Scoping

Hosts that only exist in one environment have `env_scope` in their host_vars. Discovery tasks filter by `env_scope` matching `MISE_ENV` — non-matching hosts are never registered to the dynamic group. Hosts without `env_scope` are shared across all environments.
