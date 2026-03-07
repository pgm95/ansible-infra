# Ansible Conventions

Rules for writing Ansible code in this project. All roles follow these patterns.

## Variable Naming

| Prefix | Scope | Purpose | Example |
|--------|-------|---------|---------|
| `__var` | Internal | Computed/consumed within a single task file | `__packages_to_install` |
| `_var` | Interface | Passed between tasks, templates, and handlers | `_ssh_config_path` |
| `role_var` | Role output | Exposed to playbooks and inventory | `docker_version` |

**Key rule**: Variables used in templates or handlers MUST use `_var`, not `__var`.

## Task Naming

In included task files, prefix all task names with the role name:

```yaml
# roles/applications/tailscale/tasks/validate.yml
- name: Tailscale | Validate auth key is defined
```

**Pattern**: `RoleName |` — matches handler naming convention, improves log readability.

Roles using this: `Tailscale |`, `VM |`, `LXC |`.

## Role File Structure

```
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

## Output Styling

### `fail_msg`

- **Always** use `>-` (folded scalar, strip newline)
- Keep to 1-3 concise sentences
- Include diagnostic values (`got: {{ var }}`)
- **Never** use `|` (literal block) — produces noisy `\n\n` in Ansible's JSON error output
- **Never** use section headers ("What's wrong:", "How to fix:") — state the problem and fix directly

```yaml
- ansible.builtin.assert:
    that: some_var is defined
    fail_msg: >-
      some_var is not defined. Add it to host_vars or group_vars
      (got: {{ some_var | default('undefined') }}).
```

### `success_msg`

Single-line quoted string with key values:

```yaml
success_msg: "Validated: {{ var }}"
```

### `msg` (debug)

Single-line or short `>-`. Use `verbosity: 1` for informational, no verbosity for warnings.

```yaml
# Informational — only with -v
- ansible.builtin.debug:
    msg: "Configuration: {{ config }}"
    verbosity: 1

# Warning — always displayed
- ansible.builtin.debug:
    msg: "WARNING: Insecure setting detected"
```

### Jinja2 in Error Messages

Escape Jinja2 examples: `"{{ '{{' }} var {{ '}}' }}"`

## Validation Pattern

Every role validates configuration early with actionable error messages:

```yaml
- name: Validate configuration
  ansible.builtin.assert:
    that:
      - some_required_var is defined
      - some_required_var | length > 0
    fail_msg: >-
      some_required_var is not defined or empty.
      Add it to your host_vars or group_vars.
    quiet: true
```

## Config File Backups

**Always** add `backup: true` when writing system configuration files:

```yaml
- name: Deploy configuration
  ansible.builtin.copy:
    dest: /etc/myservice/config.conf
    content: "{{ config_content }}"
    mode: "0644"
    backup: true
```

**When to use**: SSH configs, Docker daemon config, network configs, NTP configs.
**When to skip**: Temporary files, dynamic storage paths (e.g., Proxmox cicustom).

## Reference Roles

These roles demonstrate all patterns:

- `docker` — Full pattern implementation with validation
- `tailscale` — Interface variables with handlers
- `users` — Complex validation with multiple checks
- `ssh` — Template integration with interface variables
