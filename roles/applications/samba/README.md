# Samba Role

Simplified Samba file sharing role using static configuration. Deploys a pre-configured smb.conf from project files and manages Samba user passwords for existing system users.

## Features

- Static SMB configuration deployment from project files
- Existing user validation and Samba password management
- Automatic service management (smbd, avahi-daemon)
- NetBIOS daemon disabled (not needed for modern networks)
- Configuration validation with testparm
- Backup of existing configuration before deployment

## Requirements

- Debian/Ubuntu based system
- Pre-existing system user (created by users role)
- SMB configuration file at `files/smb.conf`
- Samba password in vault

## Packages Installed

- `samba` - SMB/CIFS server
- `smbclient` - SMB client utilities
- `cifs-utils` - CIFS mount helpers
- `avahi-daemon` - mDNS/Zeroconf discovery
- `avahi-utils` - Avahi utilities
- `libnss-mdns` - NSS module for mDNS resolution

## Role Variables

### Core Configuration

**samba_enabled** (boolean, default: `false`)
Master switch to enable Samba installation and configuration.

**samba_existing_user** (string, REQUIRED)
Name of an existing system user to configure for Samba access. Must reference a user from `users_list`.

**samba_user** (string, default: `{{ samba_existing_user }}`)
Resolved username for Samba authentication.

**samba_password** (string, default: `{{ vault_smb_pass }}`)
Samba password loaded from ansible-vault encrypted secrets.

**samba_services** (list)
Services to manage:

- smbd (Samba daemon)
- avahi-daemon (mDNS/Zeroconf)

## Configuration File

The role deploys `files/smb.conf` to `/etc/samba/smb.conf`. This file must exist in your project structure and contain your complete Samba share configuration.

Location: `files/smb.conf` (relative to playbook root)

## Workflow

### Prerequisites

1. Create system user with users role:

```yaml
users_list:
  - name: shareuser
    password: "system_password"
    groups: ['users']
```

1. Create Samba password in vault:

```bash
ansible-vault edit vault.yml
```

```yaml
vault_smb_pass: "samba_password"
```

1. Create SMB configuration:

```bash
cat > files/smb.conf << 'EOF'
[global]
    workgroup = WORKGROUP
    server string = File Server
    security = user
    map to guest = bad user

[share]
    path = /srv/samba/share
    browseable = yes
    writable = yes
    valid users = shareuser
EOF
```

### Basic Deployment

1. Enable in host_vars:

```yaml
samba_enabled: true
samba_existing_user: shareuser
```

1. Run playbook:

```bash
task vps:deploy -- --tags samba
```

## User Validation

The role validates that:

1. `samba_existing_user` is defined
2. User exists on the system (verified with `id` command)
3. User is configured for Samba access

Validation failures stop the playbook with clear error messages.

## Password Management

Samba passwords are managed separately from system passwords:

- First run: Creates Samba user with password
- Subsequent runs: Updates password if changed
- User is automatically enabled after password creation

## Service Management

**Enabled Services:**

- smbd: Samba file sharing daemon
- avahi-daemon: mDNS/Zeroconf for network discovery

**Disabled Services:**

- nmbd: NetBIOS name service (not needed for modern networks)

## Configuration Validation

All configuration changes are validated with `testparm` before service restart. Invalid configurations prevent deployment.

## Handler Behavior

**restart samba services**: Triggered when smb.conf is deployed. Restarts smbd and avahi-daemon to apply configuration changes.

## Tags

- `samba`: All Samba-related tasks
- `validation`: User and configuration validation tasks
- `packages`: Package installation tasks
- `users`: Samba user management tasks
- `config`: Configuration deployment tasks
- `services`: Service management tasks

## Directory Structure

```text
/etc/samba/smb.conf              # Samba configuration
/etc/samba/smb.conf.backup       # Automatic backup of previous config
/var/lib/samba/private/          # Samba user database
```

## Dependencies

This role requires:

- `users` role: For system user creation
- `files/smb.conf`: Static SMB configuration file
- `vault_smb_pass`: Encrypted password in vault

## Security Considerations

- Samba passwords are not logged (no_log: true)
- Only existing system users can be configured
- Password updates use secure shell piping (no interactive input)
- Configuration changes are validated before application
- Backup of existing configuration is always created

## Notes

- This is a simplified role for static configurations
- Dynamic share creation is not supported
- User must exist before running this role
- NetBIOS is disabled by default
- Avahi provides mDNS/Zeroconf network discovery
