# Unified Environment System — Implementation Report

## Summary

Replaced the dual-directory inventory system (`inventory/dev/`, `inventory/prod/`) with a single unified inventory where Ansible is fully environment-agnostic. All environment differences are handled by mise's native profile system (`MISE_ENV`). Ansible sees one Proxmox host (`pve`), one VPS host (`swarm-vps`), and one set of host_vars — it never knows or cares which environment is active.

---

## Architecture

### Environment Switching

Mise's native `MISE_ENV` (default: `dev` via `.config/miserc.toml`) controls everything:

- `.mise/config.toml` — shared base config, re-exports `MISE_ENV` for Ansible
- `.mise/config.dev.toml` — dev-specific: Proxmox address, VPS address, vault key
- `.mise/config.prod.toml` — prod-specific: same variables, different values
- Switch: `MISE_ENV=prod mise run swarm:deploy`

### Inventory Structure

```
inventory/
  hosts.yml                    # Single file: pve, swarm-vps, dynamic groups
  group_vars/
    all/
      vault.yml                # Symlink → secrets/vault-{MISE_ENV}.yml
  host_vars/
    lxc/
      swarm-lxc.yml            # Shared (no env_scope)
      fileserver.yml           # env_scope: prod
      mediaserver.yml          # env_scope: prod
    vm/
      swarm-vm.yml             # Shared (no env_scope)
    swarm-vps.yml              # Shared (hostname from env var)
```

### Static Hosts (`hosts.yml`)

Flat structure — no env groups, no nested children:

- `pve` — single Proxmox host, `ansible_host` and `proxmox_node_name` from mise env vars
- `swarm-vps` — single VPS host, `ansible_host` from mise env var
- `swarm`, `lxc`, `vm` — empty placeholders for dynamic groups

### Environment-Specific Values

| Variable | Dev | Prod | Consumed By |
|----------|-----|------|-------------|
| `PVE_HOST_ADDR` | `proxmox.home.arpa` | `nas.home.arpa` | `hosts.yml` → pve ansible_host |
| `PVE_NODE_NAME` | `proxmox` | `nas` | `hosts.yml` → pve proxmox_node_name |
| `VPS_ADDR` | `100.88.0.1` | `100.88.0.2` | `hosts.yml` → swarm-vps ansible_host |
| `VPS_HOSTNAME` | `nerd1` | `prod-swarm-vps` | `swarm-vps.yml` → hostname |
| `ANSIBLE_VAULT_PASSWORD_FILE` | `secrets/vault-dev.key` | `secrets/vault-prod.key` | Ansible vault decryption |

All other values (Tailscale IPs, swarm config, disk layouts, etc.) are identical across envs and stay as literals in host_vars.

### Vault

Two vault files in `secrets/`, each encrypted with its own key:

- `secrets/vault-dev.yml` (encrypted with `secrets/vault-dev.key`)
- `secrets/vault-prod.yml` (encrypted with `secrets/vault-prod.key`)

A mise `enter` hook creates a symlink at `inventory/group_vars/all/vault.yml` pointing to the active vault. Ansible auto-loads it for all hosts — no `vars_files` references needed in any playbook.

Per-profile `ANSIBLE_VAULT_PASSWORD_FILE` (set in `config.{dev,prod}.toml`) tells Ansible which key to use.

### Host Scoping

- **Shared hosts** (`swarm-lxc`, `swarm-vm`, `swarm-vps`): No `env_scope`. Discovered and targeted in every env. Env-specific values come from mise env vars via `lookup('env', ...)`.
- **Prod-only hosts** (`fileserver`, `mediaserver`): Have `env_scope: prod` in host_vars. Discovery tasks filter by `env_scope` matching `MISE_ENV` — these hosts are never registered to the dynamic group when running in dev.
- **Static hosts** (`pve`, `swarm-vps`): Single entry in `hosts.yml`. Mise env vars control which physical machine they resolve to.

### Discovery

Both `discover_definitions.yml` and `discover_swarm.yml` use `include_vars` + `delegate_facts: true`:

1. Find all host_vars files in the directory
2. Register candidates to a temp group, load vars via `include_vars`
3. Filter by `env_scope` (shared hosts pass, env-scoped hosts only pass if scope matches `MISE_ENV`)
4. Register matching hosts to the target group

Jinja2 templates in host_vars (including `lookup('env', ...)`) are evaluated normally via lazy resolution.

---

## What Changed

### Phase 0: Swarm Discovery Refactor (DONE — committed `7bc94a8`)

Replaced `lookup('file') | from_yaml` with `include_vars` + `delegate_facts`. Eliminated the 19-variable `add_host` passthrough. Validated with full swarm reset + deploy.

### Phase 1: Unified Inventory (DONE — pending commit)

| Component | Before | After |
|-----------|--------|-------|
| Env switching | Custom `PROJECT_ENV` env var | Mise native `MISE_ENV` via profiles |
| Inventory | `inventory/dev/` + `inventory/prod/` | Single `inventory/` |
| Static hosts | `pve1`/`pve2`, `nerd1`/`nerd2` | `pve`, `swarm-vps` (env vars control identity) |
| Host_vars | Duplicated per env | Single set, `lookup('env')` for divergent values |
| Vault | `inventory/{env}/group_vars/all/vault.yml` | `secrets/vault-{env}.yml` + symlink auto-loaded via `group_vars/all/` |
| Vault key | `ANSIBLE_VAULT_PASSWORD_FILE` from `PROJECT_ENV` | Per-profile `ANSIBLE_VAULT_PASSWORD_FILE` |
| deploy.sh | `HOST_VARS_DIR` with `PROJECT_ENV` in path, `--limit` for env scoping | Direct path, no env limit needed |
| Discovery | No env filtering | `env_scope` filter in both discovery tasks |
| `discover_definitions.yml` | Single-phase: find → add_host → include_vars | Two-phase: find → temp group → include_vars → filter by env_scope → register to target group |

### Decisions Made

1. **`env_scope` for host filtering** — Discovery-level filtering. Non-matching hosts never enter the dynamic group. Zero downstream play changes needed.
2. **Vault via symlink** — Mise `enter` hook creates symlink to active vault. Ansible auto-loads from `group_vars/all/`. Fully transparent to playbooks.
3. **Flat hosts.yml** — No `dev`/`prod` groups in inventory. Single `pve` and `swarm-vps` entries. Ansible is completely env-agnostic.
4. **Prod safety** — `miserc.toml` defaults to `dev`. Prod requires explicit `MISE_ENV=prod`.

---

## Validation Results

| Playbook | Dev Result |
|----------|-----------|
| `swarm:check` | 3 hosts discovered (swarm-vm, swarm-lxc, swarm-vps). Prod-only hosts excluded. |
| `lxc:check` | 1 host (swarm-lxc). fileserver/mediaserver excluded by env_scope. |
| `vps:check` | swarm-vps targeted. Vault decrypted successfully. |
| `validate` | All 12 pre-commit hooks pass. |

---

## Remaining Work

- Full `swarm:reset` + `swarm:deploy` to validate end-to-end with new inventory
- Documentation updates (CLAUDE.md rules, README, Serena memories)
- Commit and cleanup
