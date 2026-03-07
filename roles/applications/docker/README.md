# Docker Role

Installs Docker CE with comprehensive daemon configuration, swarm mode support, and user management.

## Features

- Official Docker CE repository (Debian/Ubuntu)
- Multi-architecture support (amd64/arm64)
- Computed daemon.json from individual variables
- Swarm mode orchestration support
- Prometheus metrics endpoint
- Registry mirrors and insecure registries
- Custom MTU, DNS, and network configuration
- Automatic user group membership

## Requirements

- Debian or Ubuntu based system
- Root or sudo access

## Quick Start

```yaml
# host_vars/myhost.yml
docker_enabled: true
```

## Variables

### Core

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_enabled` | `false` | Enable Docker installation |
| `docker_data_root` | `/var/lib/docker` | Docker data directory |
| `docker_storage_driver` | `""` | Storage driver (empty = auto) |

### Networking

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_mtu` | `0` | Network MTU (0 = auto, 1230 for Tailscale) |
| `docker_bridge_ip` | `""` | Custom docker0 bridge IP (CIDR) |
| `docker_dns_servers` | `[]` | Container DNS servers |
| `docker_dns_search` | `[]` | DNS search domains |
| `docker_iptables_enabled` | `true` | Enable iptables rules |
| `docker_ipv6_enabled` | `false` | Enable IPv6 |

### Logging

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_log_driver` | `json-file` | Logging driver |
| `docker_log_max_size` | `50m` | Max log file size |
| `docker_log_max_file` | `3` | Max log files to retain |
| `docker_log_compress` | `false` | Compress rotated logs |

### Runtime

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_live_restore` | `true` | Keep containers during daemon restart |
| `docker_userland_proxy` | `true` | Userland proxy for loopback |

### Registry

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_registry_mirrors` | `[]` | Registry mirror URLs |
| `docker_insecure_registries` | `[]` | Insecure registry hosts |

### Metrics

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_metrics_enabled` | `false` | Enable Prometheus endpoint |
| `docker_metrics_addr` | `127.0.0.1:9323` | Metrics listen address |
| `docker_node_generic_resources` | `[]` | Non-GPU generic resources for Swarm scheduling |

### GPU

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_gpu_enabled` | `false` | Deploy DRM udev rules + auto-register `gpu=1` generic resource |

### Swarm Mode

Swarm orchestration is handled by `playbooks/swarm.yml`, not this role directly. These variables define the node's swarm configuration:

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_swarm_enabled` | `false` | Enable swarm mode |
| `docker_swarm_role` | `worker` | Node role: manager/worker |
| `docker_swarm_init` | `false` | Initialize new cluster (first manager only) |
| `docker_swarm_advertise_addr` | `""` | Advertise address (Tailscale IP recommended) |
| `docker_swarm_labels` | `{}` | Node placement labels |

See `defaults/main.yml` for complete swarm variable list.

## Computed daemon.json

The `docker_daemon_config` variable is built from individual settings. Empty/default values are automatically filtered out:

```yaml
# Setting these variables:
docker_mtu: 1230
docker_log_max_size: "100m"

# Produces daemon.json:
{
  "mtu": 1230,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true
}
```

Override entirely in host_vars if custom structure needed.

## Swarm + Tailscale

For heterogeneous clusters across NAT boundaries:

```yaml
# group_vars/swarm.yml (applied automatically)
docker_mtu: 1230  # Tailscale 1280 - VXLAN 50

# host_vars/swarm-node.yml
docker_enabled: true
docker_swarm_enabled: true
docker_swarm_role: manager
docker_swarm_advertise_addr: "100.64.0.1"  # Tailscale IP
```

## GPU Support

For Docker Swarm nodes with GPU passthrough, set `docker_gpu_enabled: true`. This handles both:

- **Udev rules**: Deploys `/etc/udev/rules.d/99-dri.rules` to set permissive DRM device permissions (`MODE="0666"`)
- **Swarm scheduling**: Auto-appends `gpu=1` to `node-generic-resources` in daemon.json

Do not add `"gpu=1"` to `docker_node_generic_resources` directly — use `docker_gpu_enabled` instead.

```yaml
# host_vars/gpu-node.yml
docker_enabled: true
docker_gpu_enabled: true
```

For LXC containers, ensure GPU device passthrough is also enabled (`lxc_device_vaapi`, `lxc_device_kfd`).

## Dependencies

None.

## Tags

- `docker` - All Docker tasks

## Notes

- `live-restore` is automatically disabled when `docker_swarm_enabled: true`
- Root user excluded from group management
- Data directory created only if non-default path specified
