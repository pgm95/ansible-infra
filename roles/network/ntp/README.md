# NTP Configuration Role

Manages NTP (Network Time Protocol) time synchronization using systemd-timesyncd with drop-in configuration files.

## Features

- **Drop-in configuration**: Uses `/etc/systemd/timesyncd.conf.d/` for clean separation
- **Cloud-init compatible**: Drop-in files coexist with cloud-init base configuration
- **Multiple NTP servers**: Configure multiple NTP servers for redundancy
- **Validation**: Prevents empty NTP server lists
- **Idempotent**: Safe to run multiple times

## Requirements

- Debian-based system (tested on Debian 12/13)
- systemd-timesyncd (installed by default on Debian)

## Role Variables

### Feature Control

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `net_ntp_configure` | boolean | `false` | Enable/disable NTP configuration |

### NTP Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `net_ntp_servers` | list | `[]` | NTP server hostnames/IPs (required if enabled) |

## NTP Server Selection

Consider using:

- **pool.ntp.org**: Global NTP pool (default)
- **time.nist.gov**: NIST time servers (US)
- **time.cloudflare.com**: Cloudflare NTP (global, anycast)
- **time.google.com**: Google Public NTP
- Local NTP servers for air-gapped environments

## Example Configurations

### Basic Configuration (group_vars/vps.yml)

```yaml
# Enable NTP configuration
net_ntp_configure: true

# NTP servers (multiple for redundancy)
net_ntp_servers:
  - pool.ntp.org
  - time.nist.gov
  - time.cloudflare.com
```

### Custom NTP Servers (host_vars)

```yaml
net_ntp_configure: true
net_ntp_servers:
  - 10.10.10.1          # Local NTP server
  - time.cloudflare.com # Fallback
```

### Regional NTP Pool

```yaml
net_ntp_configure: true
net_ntp_servers:
  - 0.us.pool.ntp.org
  - 1.us.pool.ntp.org
  - 2.us.pool.ntp.org
```

## Usage in Playbooks

```yaml
roles:
  - role: network/ntp
    tags: [network, ntp]
```

## Tags

- `network` - Network-related roles
- `ntp` - NTP-specific tasks

## Handlers

- `Restart systemd-timesyncd` - Restarts time synchronization service

## Dependencies

None

## Validation

The role validates:

- `net_ntp_servers` is defined and non-empty when `net_ntp_configure` is true
- Fails with clear error message if validation fails

## Drop-In File Approach

The role creates `/etc/systemd/timesyncd.conf.d/99-ansible.conf` which:

- Takes precedence over `/etc/systemd/timesyncd.conf`
- Coexists with cloud-init configurations
- Is cleanly managed and easy to remove
- Follows systemd best practices

## Verification

After applying the role, verify time synchronization:

```bash
# Check service status
systemctl status systemd-timesyncd

# View time sync status
timedatectl status

# Show NTP servers in use
timedatectl show-timesync --all
```

## Cloud-Init Compatibility

The drop-in file approach is fully compatible with cloud-init. Cloud-init's base timesyncd configuration remains intact, and the drop-in file supplements or overrides specific settings.

## Migration from network_services Role

If migrating from the old `network_services` role:

```yaml
# Old variables (deprecated)
network_services_configure_ntp: true
network_services_ntp_servers:
  - pool.ntp.org

# New variables
net_ntp_configure: true
net_ntp_servers:
  - pool.ntp.org
```

## Troubleshooting

### Time not synchronizing

```bash
# Restart service
systemctl restart systemd-timesyncd

# Check logs
journalctl -u systemd-timesyncd -f
```

### Verify NTP servers are reachable

```bash
# Check connectivity
nc -vz pool.ntp.org 123

# Or use ntpdate (if installed)
ntpdate -q pool.ntp.org
```

## License

MIT

## Author

homeops infrastructure automation
