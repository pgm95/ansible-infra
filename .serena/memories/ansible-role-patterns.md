# Ansible Role Development Patterns

## Variable Naming Convention

All roles in this project follow a consistent variable naming pattern:

| Prefix | Scope | Purpose | Example |
| -------- | ------- | --------- | --------- |
| `__var` | Internal | Computed/consumed within a single task file | `__packages_to_install` |
| `_var` | Interface | Passed between tasks, templates, and handlers | `_ssh_config_path` |
| `role_var` | Role Output | Exposed to playbooks and inventory | `docker_version` |

### Critical Rule

**Variables used in templates or handlers MUST use `_var` (interface prefix), not `__var` (internal prefix).**

This ensures:

- Templates can access variables set in tasks
- Handlers can access variables from the role context
- Clear visibility of what's exposed vs. internal

## Role File Structure

```text
roles/<role_name>/
├── defaults/main.yml          # Convention header + public defaults
├── meta/
│   ├── main.yml               # Role metadata (dependencies, platforms)
│   └── argument_specs.yml     # IDE autocompletion and validation
├── tasks/
│   ├── main.yml               # Entry point, includes other task files
│   └── *.yml                  # Task files with pre-configuration validation
├── handlers/main.yml          # Handlers (use _var interface variables)
└── templates/*.j2             # Templates (use _var interface variables)
```

## Pre-Configuration Validation Pattern

Every role should validate its configuration early with actionable error messages:

```yaml
- name: Validate configuration
  ansible.builtin.assert:
    that:
      - some_required_var is defined
      - some_required_var | length > 0
    fail_msg: |
      Missing required configuration.

      What's wrong: 'some_required_var' is not defined or empty.
      How to fix: Add 'some_required_var' to your host_vars or group_vars.
    quiet: true
```

### Error Message Format

Always use two-part error messages:

1. **What's wrong**: Describe the specific validation failure
2. **How to fix**: Provide actionable steps to resolve the issue

## Block/Rescue Error Handling

For complex operations that may fail, use block/rescue with descriptive errors:

```yaml
- name: Perform operation with error handling
  block:
    - name: Attempt operation
      # ... tasks ...

  rescue:
    - name: Handle failure
      ansible.builtin.fail:
        msg: |
          Operation failed.

          What's wrong: Brief description of what failed.
          How to fix: Steps to diagnose and resolve.
```

## argument_specs.yml Structure

Provides IDE autocompletion and runtime validation:

```yaml
argument_specs:
  main:
    short_description: Brief role description
    description:
      - Detailed role description
    options:
      role_public_var:
        description: What this variable controls
        type: str
        required: false
        default: "some_default"
```

## Reference Implementations

These roles demonstrate all patterns:

- `docker` - Full pattern implementation with validation
- `tailscale` - Interface variables with handlers
- `users` - Complex validation with multiple checks
- `ssh` - Template integration with interface variables

## Task Name Prefixing for Included Files

When a role uses `import_tasks` or `include_tasks` to load sub-task files, prefix all task names with the role name for log clarity:

```yaml
# In roles/applications/tailscale/tasks/validate.yml
- name: Tailscale | Validate auth key is defined
  ansible.builtin.assert:
    that:
      - _ts_authkey is defined
```

**Pattern**: `RoleName | Task description`

This matches the existing handler naming convention and improves log readability by showing which role/sub-file a task belongs to.

**Roles using this pattern**:

- `tailscale` → `Tailscale |`
- `proxmox/vm` → `VM |`
- `proxmox/lxc` → `LXC |`

## Debug Verbosity Levels

Use `verbosity: 1` for informational debug output that should only appear with `-v`:

```yaml
# Information/status messages - use verbosity: 1
- name: Display configuration summary
  ansible.builtin.debug:
    msg: "Configuration: {{ config }}"
    verbosity: 1  # Only shows with -v

# Warnings and errors - NO verbosity (always show)
- name: Warn if insecure configuration
  ansible.builtin.debug:
    msg: "WARNING: Insecure setting detected"
  # No verbosity - always displayed
```

**Guidelines**:

- `verbosity: 1` → Status messages, configuration summaries, success confirmations
- No verbosity → Security warnings, errors, important skip notices

## Backup Parameter for Config Files

Always add `backup: true` when writing system configuration files:

```yaml
- name: Deploy configuration
  ansible.builtin.copy:
    dest: /etc/myservice/config.conf
    content: "{{ config_content }}"
    mode: "0644"
    backup: true  # Creates timestamped backup before overwrite
```

**When to use**:

- SSH configs (`/etc/ssh/sshd_config.d/*`)
- Docker daemon config (`/etc/docker/daemon.json`)
- Network configs, NTP configs, etc.

**When to skip**:

- Temporary files
- Files in dynamic storage paths (e.g., Proxmox cicustom)

## Quick Reference

When developing roles:

1. **Start with validation** - Add `assert` tasks for required configuration
2. **Use correct prefixes** - `__` for internal, `_` for interface, none for output
3. **Add argument_specs** - Enables IDE support and self-documentation
4. **Prefix task names** - Use `RoleName |` in included task files
5. **Set debug verbosity** - `verbosity: 1` for info, none for warnings/errors
6. **Add backup: true** - For system configuration files
7. **Test with `mise run validate`** - Catches linting issues early
