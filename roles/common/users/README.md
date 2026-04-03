# Users Role

Comprehensive user and group management with SSH key deployment, sudo configuration, and automatic password hashing. Validates configurations to prevent common mistakes.

## Features

- User and group creation with UID/GID support
- Automatic password hashing (SHA512)
- SSH key deployment from central file
- Sudo access configuration (with/without password)
- Interactive shell validation (prevents locked accounts)
- Root SSH access (always maintained for recovery)
- Custom home directory support
- System user support
- Password-only updates on creation

## Requirements

- Debian/Ubuntu based system
- Root or sudo access
- SSH keys provided via `ssh_authorized_keys` (list in group_vars)

## Role Variables

### Core Configuration

**users_list** (list, default: `[]`)
List of users to create and manage. Each user is a dictionary with attributes.

**users_sudo_nopasswd** (boolean, default: `false`)
Require password for sudo commands by default.

## User Attributes

Each user in `users_list` supports:

**name** (string, REQUIRED)
Username for the account.

**password** (string, REQUIRED for interactive shells)
Plain text password (automatically hashed with SHA512).

**uid** (integer, optional)
User ID number.

**gid** (integer, optional)
Primary group ID number.

**group** (string, optional)
Primary group name (created automatically if specified with gid).

**groups** (list, optional)
Additional groups for the user.

**shell** (string, default: `/bin/bash`)
Login shell for the user.

**system** (boolean, default: `false`)
Create as system user.

**create_home** (boolean, default: `true`)
Create home directory for the user.

**home** (string, optional)
Custom home directory path.

**sudo_access** (boolean, default: `false`)
Grant sudo privileges.

**ssh_keys** (boolean, default: `false`)
Deploy SSH keys from `ssh_authorized_keys` list.

## Workflow

### Basic User Creation

1. Define users in host_vars:

```yaml
users_list:
  - name: admin
    password: "plaintext123"
    groups: ['sudo']
    sudo_access: true
    ssh_keys: true
```

1. Run playbook:

```bash
task vps:deploy -- --tags users
```

Result:

- User `admin` created
- Password hashed automatically
- Added to sudo group
- Sudo access configured
- SSH keys deployed

### Multiple Users

```yaml
users_list:
  - name: admin
    password: "admin_password"
    groups: ['sudo', 'docker']
    sudo_access: true
    ssh_keys: true

  - name: developer
    password: "dev_password"
    groups: ['docker']
    ssh_keys: true

  - name: service
    password: ""
    shell: /usr/sbin/nologin
    create_home: false
    system: true
```

### User with Custom UID/GID

```yaml
users_list:
  - name: appuser
    password: "app_password"
    uid: 1500
    gid: 1500
    group: appgroup
    groups: ['docker']
```

### Passwordless Sudo

```yaml
users_sudo_nopasswd: true

users_list:
  - name: admin
    password: "plaintext"
    sudo_access: true
```

## Password Management

**Plain Text Input**: Passwords are defined in plain text in host_vars (gitignored).

**Automatic Hashing**: Role hashes passwords with SHA512 before creation.

**Update Behavior**: Passwords only updated on user creation (`update_password: on_create`).

**Validation**: Users with interactive shells MUST have passwords defined.

Example:

```yaml
users_list:
  - name: user1
    password: "my_secure_password"  # Plain text input
    # Stored as: $6$rounds=656000$... (SHA512 hash)
```

## SSH Key Management

### Root SSH Access

SSH keys are ALWAYS deployed to root user for recovery access:

```yaml
# Automatic - no configuration needed
```

Keys loaded from `ssh_authorized_keys` (list in group_vars)

### User SSH Access

Enable per-user SSH key deployment:

```yaml
users_list:
  - name: admin
    password: "plaintext"
    ssh_keys: true  # Deploy SSH keys
```

**Key Behavior:**

- Root keys: `exclusive: false` (don't remove existing keys)
- User keys: `exclusive: true` (replace all keys)

## Sudo Configuration

### With Password (Default)

```yaml
users_list:
  - name: admin
    password: "plaintext"
    sudo_access: true
```

Creates: `/etc/sudoers.d/admin`

```
admin ALL=(ALL) ALL
```

### Without Password

```yaml
users_sudo_nopasswd: true

users_list:
  - name: admin
    password: "plaintext"
    sudo_access: true
```

Creates: `/etc/sudoers.d/admin`

```
admin ALL=(ALL) NOPASSWD:ALL
```

## Validation

The role validates user configurations before creation:

**Interactive Shell Validation**: Users with interactive shells must have passwords.

Fails for:

```yaml
users_list:
  - name: baduser
    password: ""  # ERROR: No password with interactive shell
    shell: /bin/bash
```

Allowed for:

```yaml
users_list:
  - name: service
    password: ""  # OK: nologin shell
    shell: /usr/sbin/nologin
```

**Non-interactive shells:**

- /usr/sbin/nologin
- /bin/false
- /usr/bin/nologin
- /bin/true

## Group Management

### Primary Group

```yaml
users_list:
  - name: user1
    password: "plaintext"
    group: customgroup
    gid: 2000
```

Creates group `customgroup` with GID 2000, then creates user with this as primary group.

### Additional Groups

```yaml
users_list:
  - name: developer
    password: "plaintext"
    groups: ['docker', 'sudo', 'www-data']
```

User added to all specified groups (groups must exist or be created by other roles).

## System Users

For service accounts:

```yaml
users_list:
  - name: appservice
    password: ""
    shell: /usr/sbin/nologin
    system: true
    create_home: false
```

## Custom Home Directory

```yaml
users_list:
  - name: webuser
    password: "plaintext"
    home: /var/www/webuser
```

## Security Considerations

### Password Storage

- Plain text passwords defined in host_vars (gitignored)
- Hashed automatically with SHA512
- Never logged (no_log: true)
- Only updated on user creation

### SSH Key Security

- Root keys preserve existing entries (recovery access)
- User keys are exclusive (complete replacement)
- Keys loaded from `ssh_authorized_keys` (provided via group_vars)

### Sudo Validation

All sudo configurations validated with `visudo -cf` before deployment.

## Tags

- No specific tags (runs with common/default tags)

## Dependencies

- **ssh** role: For SSH daemon configuration (recommended)
- **dotfiles** role: For dotfiles deployment to created users (optional)

## Handler Behavior

No handlers. Changes take effect immediately.

## File Structure

```
/etc/sudoers.d/{username}              # Sudo configuration per user
/home/{username}/                      # User home directories
/home/{username}/.ssh/authorized_keys  # User SSH keys
/root/.ssh/authorized_keys             # Root SSH keys (recovery)
group_vars/all/main.yml                # Source SSH keys (ssh_authorized_keys)
```

## Common Configurations

### Standard Administrator

```yaml
users_list:
  - name: admin
    password: "secure_password"
    groups: ['sudo']
    sudo_access: true
    ssh_keys: true
```

### Developer with Docker

```yaml
users_list:
  - name: developer
    password: "dev_password"
    groups: ['docker']
    ssh_keys: true
```

### Service Account

```yaml
users_list:
  - name: appservice
    password: ""
    shell: /usr/sbin/nologin
    system: true
    create_home: false
```

### Multiple Admins

```yaml
users_sudo_nopasswd: false

users_list:
  - name: admin1
    password: "password1"
    groups: ['sudo']
    sudo_access: true
    ssh_keys: true

  - name: admin2
    password: "password2"
    groups: ['sudo']
    sudo_access: true
    ssh_keys: true
```

## Verification

### Check User Creation

```bash
# List users
cat /etc/passwd | grep username

# Check groups
groups username

# Check sudo access
sudo -l -U username

# Test SSH key
ssh -i ~/.ssh/id_rsa username@server
```

### Check Sudo Configuration

```bash
# View sudo config
cat /etc/sudoers.d/username

# Validate all sudoers
visudo -c
```

## Notes

- Root user is excluded from all management tasks
- Password hashing uses SHA512 with 656000 rounds
- User creation is idempotent
- Passwords never shown in logs
- Groups are appended (existing memberships preserved)
- SSH keys for users are exclusive (not appended)
- Validation prevents locked accounts with interactive shells
- Only passwords are hashed - other attributes used as-is
