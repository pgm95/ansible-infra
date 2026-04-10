# Tailscale Role

Installs and configures Tailscale via the `artis3n.tailscale` collection. Authenticates exclusively with OAuth client credentials (`tskey-client-*`), assigns custom IPs via the Tailscale API, applies Linux networking optimizations, and optionally binds SSH to the Tailnet.

## Requirements

- Debian-based system with systemd
- Tailscale OAuth client credential(s) -- see Authentication below

## Authentication

This role uses **OAuth client credentials** (`tskey-client-*`) for all authentication. It does not use auth keys (`tskey-auth-*`) or personal API keys.

Two OAuth scopes are involved, configured via separate variables that can point to the same credential if it has both scopes:

| Variable | Scope | Purpose | Required |
|----------|-------|---------|----------|
| `tailscale_oauth_authkeys` | `auth_keys` (write) | Device enrollment (`tailscale up`) | Yes |
| `tailscale_oauth_devices` | `devices` (write) | Custom IP assignment via API | Only when `tailscale_ip` is set |

OAuth clients require tags for ACL enforcement, configured via `tailscale_tags`.

### How It Works

1. The enrollment credential is passed to the upstream `artis3n.tailscale.machine` role, which detects the `tskey-client-` prefix and handles the OAuth exchange internally.
2. If a custom IP is requested, the devices credential is exchanged for a short-lived Bearer token via `POST /api/v2/oauth/token`, then used to assign the IP via `POST /api/v2/device/{id}/ip`.

## Role Variables

### General

**tailscale_enabled** (boolean, default: `false`)
Enable Tailscale installation and configuration.

**tailscale_state** (string, default: `latest`)
Package state (`present`, `latest`).

**tailscale_release_stability** (string, default: `stable`)
Release channel (`stable`, `unstable`).

### OAuth

**tailscale_oauth_authkeys** (string, REQUIRED)
OAuth client credential with `auth_keys` scope.

**tailscale_oauth_devices** (string, default: `""`)
OAuth client credential with `devices` write scope. Can be the same credential as above.

**tailscale_tags** (list, REQUIRED)
ACL tags for the device (e.g., `['server', 'vps']`).

**tailscale_oauth_ephemeral** (boolean, default: `false`)
Auto-remove device when it goes offline.

**tailscale_oauth_preauthorized** (boolean, default: `false`)
Skip manual authorization in admin console.

### Custom IP

**tailscale_ip** (string, default: `""`)
Custom Tailscale IP to assign. Must be in the CGNAT range (`100.64.0.0/10`). Falls back to `{HOSTNAME}_TS_IP` env var.

**tailscale_device_registration_delay** (integer, default: `5`)
Seconds to wait after enrollment before querying device status.

**tailscale_device_registration_retries** (integer, default: `6`)
Retries for device registration check.

**tailscale_api_timeout** (integer, default: `30`)
API request timeout in seconds.

### Connection

**tailscale_hostname** (string, auto-set)
Device hostname in the tailnet. Defaults to the system hostname.

**tailscale_args** (string, default: `""`)
Additional `tailscale up` arguments (e.g., `"--accept-routes --ssh"`).

**tailscale_up_skip** (boolean, default: `false`)
Skip the `tailscale up` command.

**tailscale_up_timeout** (integer, default: `120`)
Timeout for `tailscale up` in seconds.

### SSH Binding

**tailscale_bind_ssh** (boolean, default: `false`)
Restrict SSH to Tailnet IP + localhost only. Creates `/etc/ssh/sshd_config.d/01-tailscale-binding.conf`.

**WARNING**: Locks out non-Tailscale SSH access. Ensure console recovery access is available.

### Debugging

**tailscale_verbose** (boolean, default: `false`)
Verbose output from the upstream role.

**tailscale_insecurely_log_authkey** (boolean, default: `false`)
Log credentials in output. For debugging only.

## Task Structure

| File | Purpose |
|------|---------|
| `load_config.yml` | Variable normalization |
| `validate.yml` | Pre-deployment validation |
| `install.yml` | Enrollment via `artis3n.tailscale.machine` |
| `linux_optimizations.yml` | IP forwarding, UDP buffer tuning |
| `api_configuration.yml` | Custom IP assignment via API |
| `ssh_binding.yml` | SSH binding to Tailnet |
| `status.yml` | Connection status display |

## Validation

Pre-deployment checks include:

- OAuth credential is present and non-empty
- Tags are defined (required for OAuth)
- Devices token format is valid (when provided)
- Custom IP is in valid CGNAT range and not in reserved blocks
- Custom IP is not already assigned to another device on the tailnet

## Dependencies

`artis3n.tailscale` collection (defined in `ansible/requirements.yml`).
