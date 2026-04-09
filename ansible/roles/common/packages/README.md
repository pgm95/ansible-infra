# Packages Role

System package installation with feature flags and lock management for unattended-upgrades.

## Purpose

Installs optional package categories and ad-hoc extras with automatic system upgrades and APT lock handling. All features are off by default -- enable in group_vars or host_vars.

## Features

- Feature-based package categories (base, shell, network)
- Per-host extra packages list
- Full system upgrade with autoremove/autoclean
- Unattended-upgrades lock management
- APT lock detection and waiting

## Variables

**Feature Flags** (all default to `false`):

- `packages_fullupgrade` - Full system upgrade
- `packages_install_base` - Base packages (curl, wget, git, rsync, gnupg)
- `packages_install_shell` - Shell tools (ripgrep, fzf, bat, lsd, jq, tree)
- `packages_install_network` - Network tools (nmap, traceroute, bind9-dnsutils, whois)

**Package Lists** (overridable):

- `packages_base_list` - Essential system tools (9 packages)
- `packages_shell_list` - Enhanced CLI experience (12 packages)
- `packages_network_list` - Network diagnostics (6 packages)
- `packages_extra_list` - Ad-hoc per-host packages (default: `[]`)

## Workflow

### Lock Management

1. Stop unattended-upgrades service
2. Wait for APT locks to release (10s timeout per lock)
3. Verify all locks released
4. Perform package operations
5. Re-enable unattended-upgrades (always runs)

### Package Installation

1. Update APT cache
2. Full system upgrade (if enabled)
3. Install base packages (if enabled)
4. Install shell packages (if enabled)
5. Install network packages (if enabled)
6. Install extra packages (if list is non-empty)
7. Clean cache and autoremove

## Configuration Examples

### Enable Base + Shell (group_vars)

```yaml
packages_fullupgrade: true
packages_install_base: true
packages_install_shell: true
```

### Ad-Hoc Packages (host_vars)

```yaml
packages_extra_list:
  - htop
  - strace
```

## Lock Handling

The role handles APT locks automatically:

**Locks Monitored**:

- `/var/lib/dpkg/lock-frontend`
- `/var/lib/apt/lists/lock`
- `/var/cache/apt/archives/lock`

**Behavior**:

- Waits up to 10 seconds per lock
- Fails if locks not released after timeout
- Unattended-upgrades always re-enabled in cleanup

## Dependencies

None

## Notes

- All features off by default -- enable via group_vars or host_vars
- Skips package installation in check mode
- Package lists can be overridden in host_vars
- Full upgrade includes autoremove/autoclean
- Block/always pattern ensures unattended-upgrades always restarted
