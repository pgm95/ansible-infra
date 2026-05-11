# SSH Role

Owns all SSH-protocol concerns on a host: sshd hardening via a drop-in file, and `authorized_keys` deployment to root and to configured users.

## Features

- Drop-in configuration (no main sshd_config modification)
- SSH configuration validation before reload
- Security hardening defaults
- Connection timeout management
- Authentication method control
- Maximum authentication attempts limit
- Automatic SSH daemon reload on changes
- Authorized keys deployed to root (recovery, non-exclusive) and to users in `users_list` with `ssh_keys: true` (exclusive)

## Requirements

- Debian/Ubuntu based system
- OpenSSH server
- Root or sudo access
- sshd_config.d directory support

## Role Variables

### Authorized Keys

**ssh_authorized_keys** (list, default: `[]`)
SSH public keys deployed to root (`exclusive: false`) and to every user in `users_list` with `ssh_keys: true` (`exclusive: true`). Typically populated from the `SSH_AUTHORIZED_KEYS` env var via `ansible/group_vars/all.yml`.

Trusted SSH client identities (e.g., a bastion's pubkey) are merged into this list at the `group_vars/all.yml` resolution layer through the `ssh_trusted_client_pubkeys` registry and the per-host `ssh_trusted_clients` opt-in list -- not inside this role. The role itself only consumes the final resolved list.

### Client Identity

**ssh_client_identity** (dict, default: `{}`)
Optional private key deployed to `/root/.ssh/<name>` for outbound SSH from this host (e.g., a bastion authenticating to managed swarm nodes). Empty dict skips deployment. When set, must contain:

- `name`: filename under `/root/.ssh/` (use `id_ed25519` for default OpenSSH key search)
- `private_key`: key content, typically `{{ lookup('env', '<SECRET>') }}`

File mode is `0600`, owned by root. Use in combination with `ssh_trusted_clients` on the target hosts to scope which hosts trust which clients.

### Authentication Configuration

**ssh_password_authentication** (boolean, default: `false`)
Enable/disable password-based authentication.

**ssh_pubkey_authentication** (boolean, default: `true`)
Enable/disable public key authentication.

**ssh_permit_root_login** (string, default: `"prohibit-password"`)
Root login policy:

- `prohibit-password`: Allow key-based root login only
- `yes`: Allow all root login methods
- `no`: Disable root login entirely

**ssh_permit_empty_passwords** (boolean, default: `false`)
Allow accounts with empty passwords to login.

**ssh_challenge_response_authentication** (boolean, default: `false`)
Enable challenge-response authentication.

**ssh_use_pam** (boolean, default: `true`)
Enable PAM (Pluggable Authentication Modules) support.

### Security Limits

**ssh_max_auth_tries** (integer, default: `3`)
Maximum number of authentication attempts per connection.

### Connection Management

**ssh_client_alive_interval** (integer, default: `300`)
Seconds between keepalive messages sent to client.

**ssh_client_alive_count_max** (integer, default: `2`)
Number of keepalive messages before disconnecting unresponsive client.

**Effective Timeout**: `client_alive_interval * client_alive_count_max`

- Default: 300 * 2 = 600 seconds (10 minutes)

## Workflow

### Basic Hardening (Default)

The role applies security hardening automatically:

```yaml
# No configuration needed - defaults are secure
```

Run playbook:

```bash
mise run vps:deploy --tags ssh
```

Result:

- Password authentication disabled
- Only key-based authentication allowed
- Root login with keys only
- 3 authentication attempts maximum
- 10-minute idle timeout

### Allow Password Authentication

Not recommended, but available for specific use cases:

```yaml
ssh_password_authentication: true
```

### Disable Root Login Entirely

```yaml
ssh_permit_root_login: "no"
```

### Custom Timeout Settings

Disconnect after 5 minutes of inactivity:

```yaml
ssh_client_alive_interval: 60   # Check every 60 seconds
ssh_client_alive_count_max: 5   # Disconnect after 5 checks (5 minutes)
```

### Permissive Configuration (Testing Only)

```yaml
ssh_password_authentication: true
ssh_permit_root_login: "yes"
ssh_max_auth_tries: 6
```

## Configuration File Location

**Deployed to**: `/etc/ssh/sshd_config.d/99-ansible.conf`

**Why 99-ansible.conf?**

- Last file processed (99 prefix)
- Overrides other drop-in configurations
- Clearly identifies Ansible-managed content
- Doesn't modify main sshd_config

## Validation

All configuration changes are validated before application:

```bash
sshd -t -f /etc/ssh/sshd_config -f /etc/ssh/sshd_config.d/99-ansible.conf
```

Invalid configuration prevents deployment and displays errors.

## Handler Behavior

**Reload sshd**: Triggered when configuration is modified. SSH daemon is reloaded without terminating existing connections.

**Note**: Reload does NOT disconnect active SSH sessions. Only new connections use new configuration.

## Security Considerations

### Recommended Settings (Defaults)

```yaml
ssh_password_authentication: false      # Keys only
ssh_pubkey_authentication: true         # Enable key auth
ssh_permit_root_login: prohibit-password  # Key-based root only
ssh_permit_empty_passwords: false       # No empty passwords
ssh_max_auth_tries: 3                   # Limit brute force
```

### First-Time Setup

For first-time VPS deployment with password access:

1. Initial deployment with password:

```bash
mise run vps:first-run
```

1. SSH keys land before the sshd reload (key tasks run before the sshd_config drop-in copy), so the operator's key is in place when password auth is disabled.

2. Subsequent runs enforce key-only authentication.

## Connection Timeout Logic

**ClientAliveInterval**: How often to check if client is alive
**ClientAliveCountMax**: How many failed checks before disconnect

Example scenarios:

**10-minute timeout (default):**

```yaml
ssh_client_alive_interval: 300
ssh_client_alive_count_max: 2
# = 300 * 2 = 600 seconds
```

**5-minute timeout:**

```yaml
ssh_client_alive_interval: 60
ssh_client_alive_count_max: 5
# = 60 * 5 = 300 seconds
```

**Disable timeout:**

```yaml
ssh_client_alive_interval: 0
ssh_client_alive_count_max: 0
```

## Tags

- `ssh`: whole role (validate + key deploy + sshd config)
- `ssh_keys`: authorized_keys deployment only (root + users)
- `ssh_config`: sshd hardening drop-in + socket activation handling
- `ssh_client_identity`: outbound client identity deployment (e.g. bastion)

## Dependencies

- **users** role: Creates user accounts and home directories. Must run **before** this role so `~/.ssh/authorized_keys` can be written for users with `ssh_keys: true`.

## Common Configurations

### Maximum Security

```yaml
ssh_password_authentication: false
ssh_pubkey_authentication: true
ssh_permit_root_login: "no"
ssh_max_auth_tries: 2
ssh_client_alive_interval: 180
ssh_client_alive_count_max: 2
```

### Development Environment

```yaml
ssh_password_authentication: true
ssh_permit_root_login: "yes"
ssh_max_auth_tries: 6
ssh_client_alive_interval: 600
ssh_client_alive_count_max: 10
```

### Production Standard

```yaml
ssh_password_authentication: false
ssh_pubkey_authentication: true
ssh_permit_root_login: "prohibit-password"
ssh_max_auth_tries: 3
ssh_client_alive_interval: 300
ssh_client_alive_count_max: 2
```

## Verification

### Check Configuration

```bash
# View deployed configuration
cat /etc/ssh/sshd_config.d/99-ansible.conf

# Test configuration validity
sshd -t

# Check SSH daemon status
systemctl status sshd
```

### Test Authentication

```bash
# Test key-based authentication
ssh -i ~/.ssh/id_rsa user@server

# Test password authentication (if enabled)
ssh user@server

# View authentication logs
tail -f /var/log/auth.log
```

## File Structure

```
/etc/ssh/sshd_config                      # Main SSH configuration (not modified)
/etc/ssh/sshd_config.d/                   # Drop-in configuration directory
/etc/ssh/sshd_config.d/99-ansible.conf    # Ansible-managed hardening config
/root/.ssh/authorized_keys                # Root keys (non-exclusive)
/root/.ssh/{ssh_client_identity.name}     # Client identity for outbound SSH (0600, only when ssh_client_identity set)
/home/{username}/.ssh/authorized_keys     # Per-user keys (exclusive, for users with ssh_keys: true)
```

## Notes

- Configuration is deployed via drop-in file
- Main sshd_config is never modified
- Changes validated before application
- Reload doesn't disconnect existing sessions
- Default settings are production-ready
- PAM is enabled by default for account management
- Root login defaults to key-only access
- Password authentication disabled by default
