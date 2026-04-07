# Swap Role

Manages swap memory configuration on Linux systems. Primarily used to disable swap for Kubernetes/K3s deployments, which require swap to be disabled for proper operation.

## Features

- Check current swap status
- Disable swap immediately (runtime)
- Remove swap entries from /etc/fstab (persistent)
- Idempotent operations (safe to run multiple times)
- Backup /etc/fstab before modifications
- Clear status reporting

## Requirements

- Debian/Ubuntu based system
- Root or sudo access
- `/etc/fstab` must be writable

## Role Variables

### Swap Configuration

**swap_disable** (boolean, default: `true`)
Controls whether swap should be disabled.

- `true`: Disable swap immediately and remove from fstab
- `false`: No action taken (swap remains as configured)

## Usage

### In Playbooks

```yaml
- hosts: k3s
  roles:
    - role: common/swap
```

### With Custom Variables

```yaml
- hosts: all
  roles:
    - role: common/swap
      vars:
        swap_disable: true
```

### In Group Variables

```yaml
# inventory/group_vars/k3s.yml
swap_disable: true
```

## Behavior

### When swap_disable is true

1. **Check Current Status**: Queries active swap using `swapon --show`
2. **Disable Runtime Swap**: Executes `swapoff -a` if swap is active
3. **Remove Fstab Entries**: Removes all uncommented swap entries from `/etc/fstab`
4. **Create Backup**: Backs up `/etc/fstab` before modification
5. **Report Status**: Displays changes made

### When swap_disable is false

- No actions performed
- Swap configuration remains unchanged

## Examples

### Check if swap is currently active

```bash
# On target system
swapon --show

# Via Ansible ad-hoc
ansible k3s -m command -a "swapon --show"
```

### Verify swap is disabled after role execution

```bash
# Runtime check
free -h | grep Swap

# Persistence check
grep swap /etc/fstab
```

### Re-enable swap manually (if needed)

```bash
# Create swap file (example)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Add to fstab for persistence
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## Why Disable Swap?

### Kubernetes/K3s Requirement

Kubernetes requires swap to be disabled because:

- **Memory Guarantees**: Pod resource limits become unreliable with swap
- **Performance Predictability**: Swap introduces unpredictable latency
- **OOM Behavior**: Kubernetes expects OOM kills, not swapping
- **Scheduler Assumptions**: Resource allocation assumes physical memory only

### When to Keep Swap Enabled

Swap may be appropriate for:

- Non-Kubernetes workloads
- Development/testing environments with limited RAM
- Systems requiring overcommit protection
- Workloads tolerant of latency variability

## Integration

### Common Playbook Integration

This role is typically included in playbooks that deploy K3s or other swap-sensitive workloads:

```yaml
# playbooks/k3s.yml
- name: Deploy K3s Cluster
  hosts: k3s
  become: true
  roles:
    - common/packages
    - common/users
    - common/ssh
    - common/swap        # Disable swap before K3s
    - k3s                # K3s installation
```

## Idempotency

This role is fully idempotent:

- Running multiple times produces the same result
- Only reports changes when actual modifications occur
- Safe to include in routine playbook runs
- No side effects from repeated execution

## Troubleshooting

### Swap still shows as enabled

```bash
# Check if swapoff was successful
sudo swapoff -a
free -h | grep Swap

# Check for persistent swap configuration
grep -v '^#' /etc/fstab | grep swap

# Check for zram or other swap types
swapon --show --verbose
```

### Fstab modifications not persisting

```bash
# Verify fstab backup was created
ls -la /etc/fstab*

# Check file permissions
ls -l /etc/fstab

# Manually verify modifications
cat /etc/fstab | grep -v '^#' | grep swap
```

### Swap re-enabled after reboot

```bash
# Verify fstab has no swap entries
grep swap /etc/fstab

# Check for systemd swap units
systemctl list-units --type swap

# Disable systemd swap targets if present
sudo systemctl mask swap.target
```

## Tags

This role does not define specific tags. Use playbook-level tags for selective execution:

```bash
# Include swap role via common tag
ansible-playbook playbooks/k3s.yml --tags common

# Skip swap role
ansible-playbook playbooks/k3s.yml --skip-tags swap
```

## Dependencies

None. This role is standalone and has no dependencies on other roles.

## Compatibility

Tested on:

- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

Should work on any modern Debian/Ubuntu-based distribution with:

- systemd init system
- Standard `/etc/fstab` format
- `swapon`/`swapoff` utilities available
