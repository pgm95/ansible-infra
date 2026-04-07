# Swap Role

Manages swap memory configuration on Linux systems. Primarily used to disable swap for Docker Swarm and Kubernetes deployments, which require swap to be disabled for proper operation.

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

## Idempotency

This role is fully idempotent:

- Running multiple times produces the same result
- Only reports changes when actual modifications occur
- Safe to include in routine playbook runs
- No side effects from repeated execution

## Tags

This role does not define specific tags. Use playbook-level tags for selective execution.
