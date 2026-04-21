# Dotfiles Role

Deploys dotfiles from a private GitHub repository by cloning locally, syncing to the remote host, and invoking the repository's own `deploy.sh` script. The role is intentionally agnostic to `deploy.sh` internals - components and flags are passed through verbatim so the role never needs updating when the script grows.

## Features

- **Script-driven**: All file placement logic lives in the dotfiles repo's `deploy.sh`
- **Idempotent**: Git change detection + script's own `[CHANGED]`/`[UNCHANGED]` output
- **Persistent cache**: Repository cached locally on the control node, updated via git pull
- **Passthrough args**: `dotfiles_deploy_args` sent verbatim to `deploy.sh`
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
| `dotfiles_deploy_args` | `""` | Arguments passed verbatim to `deploy.sh` |
| `dotfiles_force_update` | `true` | Force git pull (overwrite local changes in cache) |
| `dotfiles_continue_on_error` | `true` | Don't fail playbook on dotfiles failure |

### Directory Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `dotfiles_cache_dir` | `{{ lookup('config', 'ANSIBLE_HOME') }}/cache/dotfiles` | Local cache for git clone (control node) |
| `dotfiles_staging_dir` | `/root/.dotfiles` | Remote staging directory for repository sync |

### `dotfiles_deploy_args` Examples

```yaml
dotfiles_deploy_args: ""                    # Deploy all components (script default)
dotfiles_deploy_args: "bash nano claude"    # Deploy only specific components
dotfiles_deploy_args: "--force bash"        # Force-deploy bash without backups
dotfiles_deploy_args: "--verbose"           # Deploy all with verbose output
```

The role does not parse or validate this string. Whatever `deploy.sh` supports today or in the future works without role changes.

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
3. **Deploy root**: Run `deploy.sh` with `dotfiles_deploy_args` (if `deploy_to_root`)
4. **Deploy users**: Run `deploy.sh --home /home/{user}` for each user (if `deploy_to_users`)
5. **Fix ownership**: Correct file ownership for non-root user deployments

### Change Detection

The role detects changes via `deploy.sh` output:

- Script prints `[CHANGED]` for files that were updated
- Script prints `[UNCHANGED]` for files already in sync
- Ansible reports `changed` only when `[CHANGED]` appears in stdout

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
dotfiles_deploy_args: "bash nano"  # Only deploy bash and nano configs
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

The role expects `deploy.sh` to exist at the repository root and support:

- **Positional args**: Component names (e.g., `bash`, `nano`, `all`)
- **`--home DIR`**: Override target home directory (used for non-root user deployment)
- **Exit code 0**: Success
- **stdout**: `[CHANGED]` / `[UNCHANGED]` markers for Ansible change detection

Any additional flags (`--force`, `--verbose`, `--dry-run`, etc.) are the script's concern and passed through via `dotfiles_deploy_args`.

## Error Handling

If `dotfiles_continue_on_error: true` (default): failures are logged but playbook continues.
If `dotfiles_continue_on_error: false`: failures stop playbook execution.

## Security Considerations

- GitHub token is never logged (`no_log: true`)
- Cache directory is gitignored (contains cloned repo)
- Only users with home directories receive dotfiles
- rsync uses SSH transport (encrypted)

## Directory Structure

```text
.cache/dotfiles/                 # Persistent local cache (control node, gitignored)
/root/.dotfiles/                 # Remote staging directory (synced repo)
/root/.bashrc                    # Deployed dotfiles (root, managed by deploy.sh)
/home/user/.bashrc               # Deployed dotfiles (users, managed by deploy.sh)
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
