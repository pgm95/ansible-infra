# Infrastructure Operations

Rules for operating this infrastructure. All actions go through mise and Ansible.

## Infrastructure as Code

- **Always** manage infrastructure via Ansible (edit YAML in `roles/`, `playbooks/`, `inventory/`, commit, push).
- **Never** configure hosts manually via SSH or direct commands.
- **Exceptions** only for short-lived debugging or documented one-time bootstrap steps.

## Mise-Only Operations

- **Always** use mise tasks for Ansible actions.
- **Never** run `ansible-playbook` directly — mise ensures correct paths, vault, and environment.
- **Always** rely on mise to set all needed environment variables.
- **Never** prefix commands with `ANSIBLE_VAULT_PASSWORD_FILE=`, `ANSIBLE_CONFIG=`, etc. manually.

### Deploy Commands

```bash
mise run lxc:deploy [hosts] [tags]   # LXC lifecycle
mise run vm:deploy [hosts] [tags]    # VM lifecycle
mise run vps:deploy [hosts] [tags]   # VPS provisioning
mise run swarm:deploy                # Swarm bootstrap
mise run swarm:reset                 # Swarm teardown (destructive)
```

### Environment Control

`PROJECT_ENV` controls the active environment (`dev` or `prod`). Default: `dev` (safe).

```bash
# Override via .env file
PROJECT_ENV=prod

# Or inline
PROJECT_ENV=prod mise run lxc:deploy
```

## Linting & Validation

- **Always** use `mise run validate` for linting and validation.
- **Never** run `ansible-lint`, `yamllint`, `markdownlint-cli2`, `taplo`, `shellcheck`, or schema validators directly.
- Hooks: ansible-lint (includes yamllint), shellcheck, check-jsonschema, gitleaks, markdownlint-cli2, taplo-lint.
- Hook configs live in `config/`.

## Shared Deploy Script

All deploy/check/purge tasks use `.mise/scripts/deploy.sh`, parametrized via env vars in each TOML task.

### Env Var Interface

| Env Var | Required | Default | Purpose |
|---------|----------|---------|---------|
| `DEPLOY_GROUP` | Yes | — | Inventory group. Derives playbook as `playbooks/{group}.yml` |
| `DEPLOY_INTERACTIVE` | No | `true` | `false` skips host/tag prompts |
| `DEPLOY_CHECK_MODE` | No | `false` | `true` appends `--check --diff` |
| `usage_hosts` | No | — | Pre-set hosts (from mise `usage` args or TOML `env`) |
| `usage_tags` | No | — | Pre-set tags (from mise `usage` args or TOML `env`) |

### Task Variants

- **deploy**: Interactive by default. Accepts optional hosts/tags — prompts when omitted.
- **check**: Non-interactive dry-run. `DEPLOY_INTERACTIVE=false`, `DEPLOY_CHECK_MODE=true`.
- **purge**: Non-interactive with fixed tag. `DEPLOY_INTERACTIVE=false`, `usage_tags` set.

### Host Discovery

- **File-based** (lxc, vm): Scans `inventory/${PROJECT_ENV}/host_vars/${GROUP}/` for `.yml` files.
- **Inventory-based** (vps): Falls back to `ansible-inventory --graph ${GROUP}`.

### Limit Format

- `lxc` and `vm` groups prepend `localhost,` to `--limit` (needed for the discovery play).
- All other groups use `--limit "$HOSTS"` directly.

## Adding a New Group

1. Create `playbooks/{group}.yml`.
2. Create `.mise/tasks/{group}.toml` with tasks pointing `file` to the shared script.
3. Add the new file to `task_config.includes` in `.mise/config.toml`.
4. If the group uses dynamic discovery (like lxc/vm), add its case to the `localhost` limit block in deploy.sh. Static inventory groups work automatically.

## Config File Locations

| Config | Location |
|--------|----------|
| Ansible | `config/ansible.cfg` (path-dependent settings via mise env vars) |
| Ansible-lint | `config/ansible-lint.yml` |
| Yamllint | `config/yamllint.yml` |
| Pre-commit | `config/pre-commit.yaml` |
| Requirements | `config/requirements.yml` |
| JSON Schemas | `schemas/*.schema.json` |
| Mise tasks | `.mise/tasks/*.toml` |
| Mise config | `.mise/config.toml` |

## Secrets

- **Ansible vault**: `inventory/{env}/group_vars/all/vault.yml`. Vault password: `secrets/vault-{env}.key`.
- **SSH keys**: Stored in vault as `vault_ssh_authorized_keys` (list).
