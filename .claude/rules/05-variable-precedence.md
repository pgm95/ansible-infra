# Variable Precedence

Rules for the variable hierarchy and inventory organization.

## Precedence Tiers

Configuration follows Ansible-native precedence (later overrides earlier):

1. **Role Defaults** (`roles/*/defaults/main.yml`) — Internal/computed variables only
2. **Inventory group_vars** (`inventory/{env}/group_vars/`) — Env-specific values, including vault
3. **Playbook group_vars** (`playbooks/group_vars/`) — Shared defaults across environments
4. **Host-Specific** (`inventory/{env}/host_vars/`) — Per-host overrides
5. **Play vars_files** — Loaded explicitly in plays; higher than all group_vars and host_vars
6. **Command-Line** (`--extra-vars`) — Runtime overrides (highest priority)

## Partitioning Rule

**Never define the same variable at both inventory and playbook group_vars levels.**

If a shared variable needs to differ per-env, move it from `playbooks/group_vars/` to both `inventory/dev/group_vars/` and `inventory/prod/group_vars/`.

## Vault

Vault is **not** a separate precedence level. `inventory/{env}/group_vars/all/vault.yml` is standard inventory group_vars that happens to be encrypted. It shares precedence with tier 2.

## `vars_files` Caveat

The `lxc.yml` and `vm.yml` plays load `group_vars/proxmox.yml` via `vars_files`, which elevates those variables above inventory host_vars. This is intentional for API credentials, but means **host_vars cannot override variables loaded this way**.

**Do not add new `vars_files` references** unless you understand the precedence implications. Prefer auto-loaded group_vars (tier 2-3) where `add_host` and host_vars win naturally.

## Inventory Organization

### Environments

Split per environment under `inventory/{env}/` (e.g., `inventory/prod/`, `inventory/dev/`).

Each contains:
- `hosts.yml` — Static hosts (proxmox, vps)
- `host_vars/` — Per-host variables
- `group_vars/all/vault.yml` — Encrypted secrets (auto-loaded)

Shared group_vars live at `playbooks/group_vars/` (auto-loaded by Ansible from the playbook directory).

### Groups

| Group | Type | Source |
|-------|------|--------|
| **vps** | Static | `inventory/{env}/hosts.yml` |
| **proxmox** | Static | `inventory/{env}/hosts.yml` |
| **vm** | File-based | Discovered from `inventory/{env}/host_vars/vm/` |
| **lxc** | File-based | Discovered from `inventory/{env}/host_vars/lxc/` |
| **swarm** | Dynamic | Populated by `swarm.yml` discovery |

### Host Vars Loading

Two mechanisms:

- **Auto-loaded** (static hosts): Files directly in `host_vars/` whose filename matches a host in `hosts.yml` (e.g., `host_vars/nerd1.yml`). No configuration needed.
- **Manually loaded** (dynamic hosts): Files under subdirectories (`host_vars/lxc/`, `host_vars/vm/`) are **not** auto-loaded. The discovery play registers these hosts via `add_host` and loads their variables via `include_vars` with `delegate_facts: true`.

Static hosts (proxmox, vps) get their host_vars automatically. Dynamic hosts (lxc, vm) require the discovery play to run first.
