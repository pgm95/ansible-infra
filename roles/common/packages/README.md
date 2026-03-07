# Packages Role

System package installation with feature flags and lock management for unattended-upgrades.

## Purpose

Installs base system packages and optional tool categories with automatic system upgrades and APT lock handling.

## Features

- Feature-based package categories (base, shell, network)
- Full system upgrade with autoremove/autoclean
- Unattended-upgrades lock management
- APT lock detection and waiting
- Idempotent operations

## Variables

**Feature Flags**:

- `packages_fullupgrade` (boolean, default: `true`) - Full system upgrade
- `packages_install_base` (boolean, default: `true`) - Base packages (curl, wget, git, rsync, gnupg)
- `packages_install_shell` (boolean, default: `false`) - Shell tools (ripgrep, fzf, bat, lsd, jq, tree)
- `packages_install_network` (boolean, default: `false`) - Network tools (nmap, traceroute, bind9-dnsutils, whois)

**Package Lists**:

- `packages_base_list` - Essential system tools (11 packages)
- `packages_shell_list` - Enhanced CLI experience (12 packages)
- `packages_network_list` - Network diagnostics (6 packages)

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
6. Clean cache and autoremove

## Configuration Examples

### Base System Only (Default)

```yaml
# No configuration needed - defaults install base packages only
```

### Development Environment

```yaml
packages_install_shell: true
packages_install_network: true
```

### Minimal System

```yaml
packages_fullupgrade: false
packages_install_base: true
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

## Tags

- No specific tags (runs with common/default tags)

## Dependencies

None

## Notes

- Skips package installation in check mode
- Cache valid for 3600 seconds (1 hour)
- Package lists can be overridden in host_vars
- Full upgrade includes autoremove/autoclean
- Block/rescue pattern ensures unattended-upgrades always restarted
