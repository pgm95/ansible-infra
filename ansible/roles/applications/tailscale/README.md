# Tailscale Role

Comprehensive Tailscale VPN installation and configuration with OAuth support, custom IP assignment via API, Linux networking optimizations, and optional SSH binding to Tailnet.

## Features

- OAuth client key authentication (no manual login required)
- Custom Tailscale IP assignment via API
- Linux networking optimizations (IP forwarding, UDP buffer tuning)
- Optional SSH binding to Tailscale network only
- Tag-based ACL support for OAuth keys
- Automatic device registration with retry logic
- Connection status verification
- Organized task structure for maintainability

## Requirements

- Debian/Ubuntu based system
- Tailscale OAuth client key or auth key
- (Optional) Tailscale API key for custom IP assignment
- Root or sudo access

## Role Variables

### Core Configuration

**tailscale_enabled** (boolean, default: `false`)
Master switch to enable Tailscale installation and configuration.

### Package Configuration

**tailscale_state** (string, default: `latest`)
Package installation state (present, latest).

**tailscale_release_stability** (string, default: `stable`)
Tailscale release channel (stable, unstable).

### OAuth Configuration

Both credential variables are OAuth client credentials (`tskey-client-*`), differing only by scope.
Define in `group_vars` or `host_vars` -- can use env var lookups, plaintext, or the same
OAuth client if it has both scopes.

**tailscale_oauth_authkeys** (string, REQUIRED)
OAuth client credential with `auth_keys` scope for device enrollment.

**tailscale_oauth_devices** (string, default: `""`)
OAuth client credential with `devices` write scope for custom IP assignment.
Required when `tailscale_ip` is set. Can be the same credential as `tailscale_oauth_authkeys`.

**tailscale_tags** (list, REQUIRED for OAuth)
ACL tags for the device when using OAuth keys.
Example: `['server', 'vps']`

**tailscale_oauth_ephemeral** (boolean, default: `false`)
Delete device when it goes offline.

**tailscale_oauth_preauthorized** (boolean, default: `false`)
Pre-authorize device (skip approval step).

### Custom IP Configuration

**tailscale_ip** (string, default: `""`)
Custom Tailscale IP address to assign. Can also be set via `{HOSTNAME}_TS_IP` environment variable.

**tailscale_device_registration_delay** (integer, default: `5`)
Seconds to wait before checking device registration.

**tailscale_device_registration_retries** (integer, default: `6`)
Number of retries for device registration lookup.

**tailscale_api_timeout** (integer, default: `30`)
API request timeout in seconds.

### Connection Configuration

**tailscale_hostname** (string, auto-set)
Device hostname in Tailnet (defaults to server hostname).

**tailscale_args** (string, default: `""`)
Additional Tailscale up arguments.
Example: `"--accept-routes --ssh"`

**tailscale_up_skip** (boolean, default: `false`)
Skip running `tailscale up` command.

**tailscale_up_timeout** (integer, default: `120`)
Timeout for `tailscale up` command in seconds.

### SSH Binding Configuration

**tailscale_bind_ssh** (boolean, default: `false`)
Restrict SSH access to Tailnet and localhost only.

**WARNING**: When enabled, SSH becomes dependent on Tailscale availability. Ensure recovery access via console.

### Debugging

**tailscale_verbose** (boolean, default: `false`)
Enable verbose output for troubleshooting.

**tailscale_insecurely_log_authkey** (boolean, default: `false`)
Log auth keys (insecure, only for debugging).

## Task Organization

The role is organized into separate task files:

- **load_config.yml**: Variable loading and normalization
- **validate.yml**: Configuration validation
- **install.yml**: Tailscale installation via artis3n.tailscale
- **linux_optimizations.yml**: IP forwarding and UDP optimizations
- **api_configuration.yml**: Custom IP assignment via API
- **ssh_binding.yml**: SSH binding to Tailscale network (optional)
- **status.yml**: Connection status display

## Workflow

### Basic Installation with OAuth

1. Create an OAuth client with `auth_keys` write scope

2. Map the credential in group_vars or host_vars:

```yaml
# group_vars or host_vars
tailscale_oauth_authkeys: "{{ lookup('env', 'TS_OAUTH_KEY') }}"
```

1. Enable in host_vars:

```yaml
tailscale_enabled: true
tailscale_tags: ['server']
```

1. Run playbook:

```bash
mise run vps:deploy
```

### Custom IP Assignment

1. Create an OAuth client with `devices` write scope

2. Map credentials in group_vars or host_vars:

```yaml
# Single OAuth client with both scopes
tailscale_oauth_authkeys: "{{ lookup('env', 'TS_OAUTH_KEY') }}"
tailscale_oauth_devices: "{{ lookup('env', 'TS_OAUTH_KEY') }}"
```

1. Enable with custom IP in host_vars:

```yaml
tailscale_enabled: true
tailscale_tags: ['server']
tailscale_ip: "100.88.0.10"
```

### SSH Binding to Tailnet

1. Enable SSH binding:

```yaml
tailscale_enabled: true
tailscale_bind_ssh: true
tailscale_tags: ['server']
```

1. Ensure console recovery access is available

2. SSH will only accept connections from:
   - Tailnet IPs (100.x.x.x)
   - Localhost (127.0.0.1)

### Linux Optimizations

Automatically applied when Tailscale is enabled:

**IP Forwarding:**

- `net.ipv4.ip_forward = 1`
- `net.ipv6.conf.all.forwarding = 1`

**UDP Buffer Tuning:**

- `net.core.rmem_max = 7500000`
- `net.core.wmem_max = 7500000`

Applied via `/etc/sysctl.d/99-tailscale.conf`

## Device Registration

The role uses API-based device registration with retry logic:

1. Install and connect Tailscale
2. Wait for registration delay
3. Query API for device by hostname
4. Retry up to N times if not found
5. Extract device ID for IP assignment

## SSH Binding Behavior

When `tailscale_bind_ssh: true`:

1. Creates `/etc/ssh/sshd_config.d/01-tailscale-binding.conf`
2. Sets `ListenAddress` directives for:
   - Tailscale IP (100.x.x.x)
   - Localhost (127.0.0.1)
3. Validates configuration with `sshd -t`
4. Reloads SSH daemon

## Tags

- `tailscale`: All Tailscale-related tasks
- `vpn`: VPN installation and configuration

## Dependencies

This role uses the `artis3n.tailscale` collection for installation.

## Handler Behavior

**Reload sshd**: Triggered when SSH binding configuration is modified. SSH daemon is reloaded to apply changes.

## Directory Structure

```
/etc/sysctl.d/99-tailscale.conf              # Linux networking optimizations
/etc/ssh/sshd_config.d/01-tailscale-binding.conf  # SSH binding (if enabled)
```

## Environment Variables

The role supports environment variable fallback for custom IP:

- `{HOSTNAME}_TS_IP`: Custom Tailscale IP for host (fallback when `tailscale_ip` is not set)

## Security Considerations

- OAuth keys are not logged by default
- API keys are loaded from environment variables
- SSH binding restricts access to Tailnet only
- IP forwarding is enabled for subnet routing capabilities
- UDP buffer tuning improves VPN performance

## Validation

The role validates:

- OAuth keys have required tags
- Custom IPs are in valid Tailscale range (100.64.0.0/10)
- Device registration succeeds
- SSH configuration is valid before reload

## Notes

- Device hostname in Tailnet matches server hostname
- Custom IP assignment requires Tailscale API key
- SSH binding requires console recovery access
- Linux optimizations improve VPN performance
- OAuth keys eliminate manual login requirements
- Tags are required for OAuth authentication
