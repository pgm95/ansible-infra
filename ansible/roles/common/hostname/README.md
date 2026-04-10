# Hostname Role

Configures system hostname and `/etc/hosts` for VPS environments with static public IPs. Sets the hostname via `ansible.builtin.hostname` (systemd strategy) and templates `/etc/hosts` with the primary IP mapped to the hostname.

## Requirements

- Debian-based system with systemd
- Static public IP

## Role Variables

### Feature Control

**hostname_configure** (boolean, default: `false`)
Enable/disable hostname configuration. The playbook gates the role with `when: hostname_configure`.

### Core Configuration

**hostname** (string, optional)
System hostname. Falls back to `inventory_hostname` when undefined.

**hostname_domain_suffix** (string, default: `""`)
Domain suffix for FQDN construction. When non-empty, FQDN is computed as `{hostname}.{hostname_domain_suffix}`. When empty, no FQDN is set and only the bare hostname appears in `/etc/hosts`.

## How It Works

1. **Resolve**: Sets `hostname` from host_vars or falls back to `inventory_hostname`. Computes `fqdn` if a domain suffix is configured.
2. **Validate**: Asserts hostname is non-empty and primary IP was detected.
3. **Set hostname**: Calls `ansible.builtin.hostname`, which persists to `/etc/hostname` via systemd.
4. **Template /etc/hosts**: Maps the detected primary IP to the hostname (and FQDN if defined).

### Resulting /etc/hosts

With FQDN:

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain ip6-localhost ip6-loopback
203.0.113.10 server1.example.com server1
```

Without FQDN (no domain suffix):

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain ip6-localhost ip6-loopback
203.0.113.10 server1
```

## IP Detection

Primary IP is detected from gathered facts:

1. `ansible_facts.default_ipv4.address` (preferred)
2. First entry in `ansible_facts.all_ipv4_addresses` (fallback)

Validation fails with an actionable message if neither is available.

## Example

```yaml
# host_vars/swarm-vps.yml
hostname_configure: true
hostname: "{{ lookup('env', 'VPS_HOSTNAME') }}"
```

## Tags

- `always`: Variable resolution tasks run with all tag selections

## Dependencies

None.
