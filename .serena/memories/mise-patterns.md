# Mise Task Patterns

## Shared Deploy Script Architecture

All ansible deploy/check/purge tasks across vps, lxc, and vm groups use a single shared script
at `.mise/scripts/deploy.sh`, referenced via the `file` property in each TOML task definition.

### Env Var Interface

| Env Var | Required | Default | Purpose |
|---------|----------|---------|---------|
| `DEPLOY_GROUP` | Yes | — | Inventory group name (`vps`, `lxc`, `vm`). Derives playbook as `playbooks/{group}.yml` |
| `DEPLOY_INTERACTIVE` | No | `true` | When `false`, skips host/tag interactive prompts |
| `DEPLOY_CHECK_MODE` | No | `false` | When `true`, appends `--check --diff` to the command |
| `usage_hosts` | No | — | Pre-set hosts (from mise `usage` args or TOML `env`) |
| `usage_tags` | No | — | Pre-set tags (from mise `usage` args or TOML `env`) |

### Host Discovery Logic

The script auto-detects the discovery method based on the group:

- **File-based** (lxc, vm): Checks if `inventory/host_vars/${GROUP}/` contains `.yml` files,
  lists them via `find` with `basename` stripping.
- **Inventory-based** (vps): Falls back to `ansible-inventory --graph ${GROUP}`, parsing the tree output.

### Environment System (2026-04)

Mise native `MISE_ENV` profiles replace the custom `PROJECT_ENV` system. Ansible is fully env-agnostic.

- `.config/miserc.toml` sets default `env = ["dev"]`
- `.mise/config.dev.toml` / `.mise/config.prod.toml` provide env-specific values (Proxmox address, VPS address, vault key)
- Vault symlink: `enter` hook in config.toml creates `inventory/group_vars/all/vault.yml → secrets/vault-${MISE_ENV}.yml`
- Per-profile `ANSIBLE_VAULT_PASSWORD_FILE` selects the vault key
- Single unified `inventory/` directory — no per-env split

### Environment-Specific Values

| Variable | Dev | Prod | Consumed By |
|----------|-----|------|-------------|
| `PVE_HOST_ADDR` | `proxmox.home.arpa` | `nas.home.arpa` | `hosts.yml` → pve ansible_host |
| `PVE_NODE_NAME` | `proxmox` | `nas` | `hosts.yml` → pve proxmox_node_name |
| `VPS_ADDR` | `100.88.0.1` | `100.88.0.2` | `hosts.yml` → swarm-vps ansible_host |
| `VPS_HOSTNAME` | `nerd1` | `prod-swarm-vps` | `swarm-vps.yml` → hostname |
| `ANSIBLE_VAULT_PASSWORD_FILE` | `.secrets/vault-dev.key` | `.secrets/vault-prod.key` | Ansible vault decryption |

All other values (Tailscale IPs, swarm config, disk layouts) are identical across envs and stay as literals in host_vars.

### Limit Format

- `lxc` and `vm` groups prepend `localhost,` to `--limit` (needed for the discovery play).
- All other groups use `--limit "$HOSTS"` directly.

### Adding a New Group

To add a new Ansible group to the shared deploy system:

1. Create `playbooks/{group}.yml` (the script derives the path from `DEPLOY_GROUP`).
2. Create `.mise/tasks/{group}.toml` with tasks pointing `file` to the shared script.
3. Add the new file to `task_config.includes` in `.mise/config.toml`.
4. If the group uses dynamic discovery (like lxc/vm), add its case to the `localhost` limit
   block in the deploy script. Static inventory groups work automatically.

### Task Variant Conventions

- **deploy**: Interactive by default (`DEPLOY_INTERACTIVE` omitted = `true`). Accepts optional
  `usage` args for hosts and tags — prompts when omitted, runs directly when provided.
- **check**: Non-interactive dry-run. Sets `DEPLOY_INTERACTIVE=false` and `DEPLOY_CHECK_MODE=true`.
- **purge**: Non-interactive with a fixed tag. Sets `DEPLOY_INTERACTIVE=false` and `usage_tags` to the desired tag.
- Custom variants follow the same pattern: combine env vars to control script behavior.

### Layout

- `.mise/scripts/` — Shared executable scripts referenced by TOML tasks via `file`.
- `.mise/tasks/` — Per-group TOML task definitions, included via `task_config.includes` in config.
- `.mise/config.toml` — Tool versions, env vars (including `ANSIBLE_INVENTORY`), shell settings, task includes.

## Mise DRY Features Research (2026-02)

### `task_templates` + `extends`

- **Requires `experimental = true`** in settings — not used in this project.
- Templates defined in `[task_templates.*]`, tasks use `extends = "template_name"`.
- `env` and `tools` deep-merge; `run`/`file` completely overridden by local.
- `usage` inheritance is undocumented but inferred from "other fields: local overrides".
- Cross-include template resolution (templates in config.toml, tasks in included files) is undocumented.

### `file` property

- Stable, non-experimental. References external script instead of inline `run`.
- `usage` defined in TOML alongside `file` passes `usage_*` env vars to the script.
- Path is relative to project root (not to the TOML file's location).

### `vars` (shared variables)

- Defined in `[vars]` section, referenced as `{{vars.name}}` in task definitions.
- Available in config.toml but not in included task TOML files.

### Portability Notes

- Use `[[:space:]]` instead of `\s` in grep patterns (POSIX-compatible).
- All `sed` substitutions use basic `s/pattern/replacement/` (portable between BSD and GNU).
- Use `find ... -exec basename {} .yml \;` instead of `ls | xargs basename` (ShellCheck SC2011).

## Shell Settings

```toml
# .mise/config.toml
unix_default_file_shell_args = "bash -o errexit -o nounset -o pipefail"
unix_default_inline_shell_args = "bash -c -o errexit -o nounset -o pipefail"
```

These align with `set -euo pipefail` in the deploy script. All mise-executed bash
(both inline `run` and `file` scripts) runs with strict error handling.
