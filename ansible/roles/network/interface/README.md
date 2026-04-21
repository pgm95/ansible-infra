# Network Interface Role

Configures network interface settings with support for static IP or DHCP. Designed for edge cases where manual network configuration is required.

## Features

- Static IP configuration
- DHCP configuration
- Automatic interface name resolution
- Configuration backup before changes
- Network service restart on changes
- Templates for both static and DHCP modes

## Requirements

- Debian/Ubuntu based system
- Root or sudo access
- /etc/network/interfaces support

## Role Variables

### Core Configuration

**net_iface_configure** (boolean, default: `false`)
Master switch to enable network interface configuration.

**WARNING**: Most VPS providers configure networking automatically. Only enable this if you need to override provider configuration.

**net_iface_name** (string, default: `""`)
Interface name to configure. Use `"auto"` or leave empty to default to `eth0`.

**net_iface_mode** (string, default: `""`)
Configuration mode: `static` or `dhcp`.

### Static IP Configuration

**net_iface_address** (string, default: `""`)
Static IP address for the interface.

**net_iface_netmask** (string, default: `"255.255.255.0"`)
Network mask for static configuration.

**net_iface_gateway** (string, default: `""`)
Default gateway for static configuration.

**NOTE**: DNS configuration is managed by the `network/dns` and `network/ntp` roles, not this role.

## Workflow

### Static IP Setup

1. Enable in host_vars:

```yaml
net_iface_configure: true
net_iface_mode: static
net_iface_name: eth0
net_iface_address: 192.168.1.100
net_iface_netmask: 255.255.255.0
net_iface_gateway: 192.168.1.1
```

1. Run playbook:

```bash
mise run vps:deploy --tags network
```

### DHCP Configuration

1. Enable in host_vars:

```yaml
net_iface_configure: true
net_iface_mode: dhcp
net_iface_name: eth0
```

1. Run playbook:

```bash
mise run vps:deploy --tags network
```

## Template Behavior

### Static Mode

Generates `/etc/network/interfaces` with:

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
```

### DHCP Mode

Generates `/etc/network/interfaces` with:

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

## Interface Name Resolution

If `net_iface_name` is:

- `"auto"`: Defaults to `eth0`
- Empty string: Defaults to `eth0`
- Specific name: Uses that name

This ensures consistent behavior across different configurations.

## DNS Configuration

This role only configures IP address, netmask, and gateway. DNS resolver configuration is handled by the `network/dns` and `network/ntp` roles.

To configure DNS:

```yaml
net_dns_configure: true
net_dns_servers:
  - 1.1.1.1
  - 8.8.8.8
```

## Handler Behavior

**Restart networking**: Triggered when `/etc/network/interfaces` is modified. Network service is restarted to apply configuration changes.

**WARNING**: Network restart may cause brief connection interruption.

## Configuration Backup

Ansible automatically backs up `/etc/network/interfaces` before modification. Backups have timestamp suffixes and can be used for rollback.

## Tags

- `network`: Network interface configuration tasks

## Dependencies

- **network_services** role: For DNS configuration (recommended to use together)

## Use Cases

### When to Use This Role

- Bare metal servers requiring static IP
- VPS with custom network requirements
- Test environments with specific networking needs
- Systems where provider automation is unavailable

### When NOT to Use This Role

- Most VPS environments (providers handle networking)
- Cloud instances with provider-managed networking
- Systems using systemd-networkd instead of /etc/network/interfaces
- Environments where network configuration changes are risky

## Safety Considerations

- Always have console access before modifying network configuration
- Test changes in non-production first
- Keep backup of working configuration
- Network restart causes brief connection loss
- Invalid configuration may require console recovery

## File Structure

```
/etc/network/interfaces           # Network configuration
/etc/network/interfaces.backup    # Automatic backup
```

## Common Issues

**Lost connection after applying**: Configuration may be incorrect. Use console access to restore backup configuration.

**Gateway not reachable**: Verify gateway IP is correct and on same subnet as interface address.

**No network after restart**: Check template syntax and interface name. Restore from backup if needed.

## Notes

- This role is disabled by default (net_iface_configure: false)
- Most modern VPS providers handle networking automatically
- DNS configuration requires the network/dns and network/ntp roles
- Templates support both IPv4 static and DHCP modes
- Configuration validation happens during network restart
- Failed configuration may require console access to fix
