# Hostname Role

Configures system hostname and FQDN with proper /etc/hosts management for VPS environments with static public IPs. Ensures clean resolution without conflicting entries.

## Features

- System hostname configuration
- FQDN with domain suffix support
- Clean /etc/hosts management for VPS with static IPs
- Removal of problematic 127.0.1.1 entries
- IPv6 localhost configuration
- Public IP mapping to FQDN
- Automatic primary IP detection
- Backup of /etc/hostname before changes

## Requirements

- Debian/Ubuntu based system
- Root or sudo access
- Static public IP (for VPS environments)

## Role Variables

### Feature Control

**hostname_configure** (boolean, default: `false`)
Master switch to enable/disable hostname configuration. Set to `true` in host_vars to activate the role.

### Core Configuration

**hostname** (string, default: `{{ inventory_hostname }}`)
System hostname (short name without domain).

**hostname_default** (string, default: `{{ inventory_hostname }}`)
Fallback hostname if not explicitly defined.

**hostname_domain_suffix** (string, default: `""`)
Domain suffix for FQDN construction.

**fqdn** (string, auto-generated)
Fully Qualified Domain Name, automatically constructed as `{{ hostname }}.{{ hostname_domain_suffix }}`.

## Workflow

### Basic Hostname Setup

1. Define in host_vars:

```yaml
hostname_configure: true    # Enable the role
hostname: server1
hostname_domain_suffix: example.com
```

1. Run playbook:

```bash
task vps:deploy -- --tags hostname
```

Result:

- Hostname: `server1`
- FQDN: `server1.example.com`
- /etc/hosts: `203.0.113.10 server1.example.com server1`

### Without Domain Suffix

```yaml
hostname: server1
hostname_domain_suffix: ""
```

Result:

- Hostname: `server1`
- FQDN: `server1`
- /etc/hosts: `203.0.113.10 server1`

## /etc/hosts Management

The role enforces a clean /etc/hosts structure for VPS with static public IPs:

### Cleanup Operations

1. **Remove 127.0.1.1 entries**: Not needed for VPS with static public IP
2. **Remove conflicting public IP entries**: All existing lines with the public IP are removed
3. **Remove 127.0.x.x hostname entries**: Except localhost

### Final Structure

```text
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
203.0.113.10 server1.example.com server1
```

### Why This Approach?

For VPS with static public IPs:

- System should resolve its FQDN to the public IP, not 127.0.1.1
- Clean /etc/hosts prevents resolution conflicts
- Localhost remains on 127.0.0.1 for local services
- FQDN on public IP enables proper external communication

## IP Detection

Primary IP is automatically detected using:

1. `ansible_default_ipv4.address` (preferred)
2. `ansible_all_ipv4_addresses[0]` (fallback)

This ensures the correct public IP is used in /etc/hosts.

## Hostname vs FQDN

**Hostname**: Short name without domain

- Example: `server1`
- Set via: `hostname` command and `/etc/hostname`

**FQDN**: Fully Qualified Domain Name

- Example: `server1.example.com`
- Mapped in: `/etc/hosts`

Both point to the same public IP in /etc/hosts.

## Configuration Examples

### VPS with Domain

```yaml
hostname: web01
hostname_domain_suffix: prod.company.com
```

Results in:

- `/etc/hostname`: `web01`
- `/etc/hosts`: `203.0.113.10 web01.prod.company.com web01`

### VPS without Domain

```yaml
hostname: vps-instance
hostname_domain_suffix: ""
```

Results in:

- `/etc/hostname`: `vps-instance`
- `/etc/hosts`: `203.0.113.10 vps-instance`

### LXC Container with DHCP

```yaml
hostname: container1
hostname_domain_suffix: lxc.arpa
```

Results in:

- `/etc/hostname`: `container1`
- `/etc/hosts`: `192.168.1.100 container1.lxc.arpa container1`

## Tags

- `always`: Variable initialization tasks run with all tag selections

## Dependencies

None. This is a standalone role that can be used independently.

## Handler Behavior

No handlers. Hostname changes take effect immediately via the hostname command.

## File Backup

`/etc/hostname` is backed up before modification. Ansible creates automatic backups with timestamp suffixes.

## Notes

- Hostname changes take effect immediately (no reboot required)
- /etc/hosts is cleaned before adding correct entries
- IPv6 localhost entries are always preserved
- This role is VPS-optimized (static public IP assumption)
- For dynamic environments, different /etc/hosts logic may be needed
- FQDN is automatically derived from hostname and domain suffix
- If hostname is undefined, inventory_hostname is used
