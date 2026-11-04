# Dotfiles Role

Deploys dotfiles from a private GitHub repository by cloning locally, syncing to the remote host, and invoking the repository's own `deploy.sh` entrypoint. Hosts choose components with `dotfiles_components`; file content and rendering stay in the dotfiles repo, and the role never lists individual files.

## Features

- **Script-driven**: All file placement logic lives in the dotfiles repo's `deploy.sh`
- **Idempotent**: Change detection comes from the script's JSON result
- **Drift reporting**: `--check` compares each home against the last deployed source, without writing to the host
- **Persistent cache**: Repository cached locally on the control node, updated via git pull
- GitHub OAuth token authentication (never logged)
- Deployment to root and/or regular users
- Error handling with continue-on-error option

## Requirements

- Debian/Ubuntu based system
- GitHub repository with dotfiles and a `deploy.sh` script
- GitHub Personal Access Token with repo access
- Git installed on control machine
- **rsync** installed on control machine and targets

## Role Variables

### Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dotfiles_enabled` | `false` | Master switch for dotfiles deployment |
| `dotfiles_repo_url` | `""` | Git repository URL (without `https://` prefix) |
| `dotfiles_repo_branch` | `""` | Git branch to checkout |

### Deployment Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dotfiles_deploy_to_root` | `true` | Deploy to root user's home directory |
| `dotfiles_deploy_to_users` | `false` | Deploy to regular users from `users_list` |
| `dotfiles_components` | `[]` | Components to deploy; required when enabled |
| `dotfiles_force_update` | `true` | Force git pull (overwrite local changes in cache) |
| `dotfiles_continue_on_error` | `false` | Don't fail playbook on dotfiles failure |

### Directory Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dotfiles_cache_dir` | `{{ lookup('config', 'ANSIBLE_HOME') }}/cache/dotfiles` | Local cache for git clone (control node) |
| `dotfiles_staging_dir` | `/var/lib/dotfiles` | Persistent remote source directory; check mode reads it |

### `dotfiles_components` Examples

```yaml
dotfiles_components: [bash, nano, claude]   # Specific components
dotfiles_components: [all]                  # Every component
```

A component is a directory in the dotfiles repo's `dotfiles/`. The role checks each name against the cached repository before deploying.

## Authentication

GitHub Personal Access Token is provided via `dotfiles_github_token` variable:

```yaml
# In group_vars or host_vars
dotfiles_repo_url: "github.com/username/dotfiles"
dotfiles_repo_branch: "main"
dotfiles_github_token: "ghp_xxxxxxxxxxxxx"  # from env var via lookup
```

Token is never logged (`no_log: true` on git tasks).

## Deployment Process

1. **Clone/Update**: Clone repository to local cache (or `git pull` if cache exists)
2. **Sync**: rsync entire repository to remote `dotfiles_staging_dir` (excluding `.git`)
3. **Apply root**: Run `deploy.sh apply` (if `deploy_to_root`)
4. **Apply users**: Run `deploy.sh apply --home <home>` for each user (if `deploy_to_users`)
5. **Fix ownership**: Correct file ownership for non-root user deployments

### Change Detection

`deploy.sh --json` prints one result line on stdout, and Ansible reports `changed` from its `changed` field.

### Drift Reporting

Under `--check`, the role skips clone, sync and apply, then runs `deploy.sh check` against the source from the last deploy. Drifted hosts report `changed` and list the files for root. The source stays in `dotfiles_staging_dir` for this reason. It answers "has this host changed since its last deploy", not "is a newer repo commit pending".

```bash
mise run vps:check --tags dotfiles
```

## Usage

### Basic Deployment (Root Only)

```yaml
# In host_vars or group_vars
dotfiles_enabled: true
```

```bash
mise run vps:deploy --tags dotfiles
```

### Selective Components

```yaml
dotfiles_enabled: true
dotfiles_components: [bash, nano]  # Only deploy bash and nano configs
```

### Deploy to All Users

```yaml
dotfiles_enabled: true
dotfiles_deploy_to_users: true
```

Users from `users_list` with home directories receive dotfiles. Users with `create_home: false` are skipped.

## User Selection

When `dotfiles_deploy_to_users: true`, only users with home directories receive dotfiles:

- Users with `create_home: true`
- Users without `create_home` specified (defaults to true)

## deploy.sh Contract

The role expects `deploy.sh` at the repository root and supports:

- **Commands**: `apply`, `check`
- **`--components a,b`**: Host selection
- **`--home DIR`**: Override target home directory (used for non-root user deployment)
- **`--json`**: One line on stdout: `{"changed":bool,"drift":bool,"files":[...],"components":[...]}`
- **Exit codes**: `0` success or clean, `1` drift (`check`), `2` usage error, `3` runtime error

## Error Handling

If `dotfiles_continue_on_error: false` (default): failures stop playbook execution.
If `dotfiles_continue_on_error: true`: failures are logged but the playbook continues.

An empty or unknown `dotfiles_components` always fails, whatever this is set to.

## Security Considerations

- GitHub token is never logged (`no_log: true`)
- Cache directory is gitignored (contains cloned repo)
- Only users with home directories receive dotfiles
- rsync uses SSH transport (encrypted)

## Directory Structure

```text
.ansible/cache/dotfiles/         # Persistent local cache (control node, gitignored)
/var/lib/dotfiles/               # Remote source directory (synced repo)
/root/.bashrc                    # Deployed dotfiles (root, copied by deploy.sh)
/root/.dotfiles_backup/          # Files replaced by apply
/home/user/.bashrc               # Deployed dotfiles (users, copied by deploy.sh)
```

## Dependencies

- `ansible.posix.synchronize` module (rsync wrapper)
- This role works with the `users` role for user list and home directory information

## Troubleshooting

### "rsync command not found"

Install rsync on both control machine and targets:

```bash
apt install rsync
```

### "deploy.sh: not found"

Ensure `deploy.sh` exists at the root of your dotfiles repository.

### Permission Denied

- Ensure target user home directories exist
- Check SSH key authentication works
- Verify the staging directory is accessible
