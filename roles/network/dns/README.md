# DNS Configuration Role

Manages DNS resolver configuration across different DNS management systems using systemd-resolved, resolvconf, or direct /etc/resolv.conf modification.

## Features

- **Multi-backend support**: systemd-resolved (drop-in files), resolvconf, or direct /etc/resolv.conf
- **Automatic detection**: Detects and uses the appropriate DNS management system
- **Drop-in configuration**: Uses `/etc/systemd/resolved.conf.d/` for systemd-resolved (cloud-init compatible)
- **Search domain support**: Configure DNS search domains
- **Validation**: Prevents empty DNS server lists
- **Idempotent**: Safe to run multiple times

## Requirements

- Debian-based system (tested on Debian 12/13)
- systemd-resolved, resolvconf, or standard /etc/resolv.conf

## Role Variables

### Feature Control

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `net_dns_configure` | boolean | `false` | Enable/disable DNS configuration |

### DNS Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `net_dns_servers` | list | `[]` | DNS server IP addresses (required if enabled) |
| `net_dns_search` | list | `[]` | DNS search domains (optional) |

### Advanced Options

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `net_dns_stub_resolver` | boolean | `false` | Enable systemd-resolved stub resolver (127.0.0.53) |
| `net_dns_mdns` | boolean | `false` | Enable multicast DNS (mDNS) |
| `net_dns_llmnr` | boolean | `false` | Enable Link-Local Multicast Name Resolution |

## DNS Management Methods

The role automatically detects and uses the appropriate method:

1. **systemd-resolved** (preferred): Uses drop-in file `/etc/systemd/resolved.conf.d/99-ansible.conf`
2. **resolvconf**: Writes to `/etc/resolvconf/resolv.conf.d/head` for priority DNS
3. **Direct**: Modifies `/etc/resolv.conf` directly as fallback

## Example Configurations

### Basic Configuration (group_vars/vps.yml)

```yaml
# Enable DNS configuration
net_dns_configure: true

# DNS servers
net_dns_servers:
  - 1.1.1.1
  - 9.9.9.9

# Optional search domains
net_dns_search: []
```

### Advanced Configuration (host_vars)

```yaml
net_dns_configure: true
net_dns_servers:
  - 10.10.10.1  # Local DNS
  - 1.1.1.1     # Cloudflare fallback
net_dns_search:
  - home.arpa
  - local

# Advanced systemd-resolved options
net_dns_stub_resolver: false  # Disable stub resolver
net_dns_mdns: false           # Disable mDNS
net_dns_llmnr: false          # Disable LLMNR
```

## Usage in Playbooks

```yaml
roles:
  - role: network/dns
    tags: [network, dns]
```

## Tags

- `network` - Network-related roles
- `dns` - DNS-specific tasks

## Handlers

- `Restart systemd-resolved` - Restarts systemd-resolved service
- `Update resolvconf` - Regenerates resolv.conf via resolvconf

## Dependencies

None

## Validation

The role validates:

- `net_dns_servers` is defined and non-empty when `net_dns_configure` is true
- Fails with clear error message if validation fails

## Cloud-Init Compatibility

The drop-in file approach (`/etc/systemd/resolved.conf.d/`) is fully compatible with cloud-init. Drop-in files take precedence over cloud-init's base configuration without conflicts.

## Migration from network_services Role

If migrating from the old `network_services` role:

```yaml
# Old variables (deprecated)
network_services_configure_dns: true
network_services_dns_servers: [1.1.1.1]
network_services_dns_search: []

# New variables
net_dns_configure: true
net_dns_servers: [1.1.1.1]
net_dns_search: []
```

## License

MIT

## Author

homeops infrastructure automation
