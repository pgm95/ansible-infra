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
- SMB configuration file for smb_conf_file in host_vars
- Samba password provided via host_vars

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

**samba_password** (string, REQUIRED)
Samba user password. Must be provided via host_vars.

**samba_services** (list)
Services to manage:

- smbd (Samba daemon)
- avahi-daemon (mDNS/Zeroconf)

## Configuration File

The role deploys the file specified by `smb_conf_file` to `/etc/samba/smb.conf`. Per-environment configs use `files/smb-{env}.conf` (e.g. `smb-dev.conf`, `smb-prod.conf`), selected via `MISE_ENV` in host_vars.

## Workflow

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
- `files/smb-{env}.conf`: Per-environment SMB configuration file
- `samba_password`: Must be provided via host_vars

## Notes

- This is a simplified role for static configurations
- Samba passwords are not logged (no_log: true)
- Only existing system users can be configured
- Password updates use secure shell piping (no interactive input)
- Configuration changes are validated before application
- Backup of existing configuration is always created
- Dynamic share creation is not supported
- NetBIOS is disabled by default
- Avahi provides mDNS/Zeroconf network discovery
