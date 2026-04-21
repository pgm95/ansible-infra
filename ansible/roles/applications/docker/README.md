# Docker Role

Installs Docker CE with comprehensive daemon configuration and swarm mode support.

## Features

- Official Docker CE repository (Debian/Ubuntu)
- Multi-architecture support (amd64/arm64)
- Computed daemon.json from individual variables
- Swarm mode orchestration support
- Prometheus metrics endpoint
- Registry mirrors and insecure registries
- Custom MTU, DNS, and network configuration
- AMD GPU runtime (opt-in via `docker_gpu_enabled`)

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
| `docker_containerd_root` | `""` | Containerd root directory (empty = default). Set when `docker_data_root` is on a separate disk. |
| `docker_storage_driver` | `""` | Storage driver (empty = auto) |

### Networking

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_mtu` | `0` | Network MTU (0 = auto; reduce for tunneled networks) |
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

### Daemon Runtime Behavior

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
| `docker_node_generic_resources` | `[]` | Generic resources for Swarm scheduling |

### Runtime

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_runtimes` | `{}` | Additional OCI runtimes for daemon.json |
| `docker_default_runtime` | `""` | Default runtime name (empty = runc) |
| `docker_cdi_enabled` | `false` | Enable Container Device Interface feature |

### GPU (AMD)

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `docker_gpu_enabled` | `false` | Install AMD container runtime and enable CDI |

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

`daemon.json` is built internally from the individual settings above. Empty/default values are filtered out:

```yaml
# Setting these variables:
docker_mtu: 1280
docker_log_max_size: "100m"

# Produces daemon.json:
{
  "mtu": 1280,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true
}
```

## Swarm + Tailscale

`docker_mtu` is the **transport** MTU (the interface the overlay rides on), not the overlay MTU. Docker subtracts the VXLAN 50-byte overhead itself, so `docker_mtu: 1280` (Tailscale's MTU) yields a 1230-byte overlay MTU. Setting `docker_mtu: 1230` double-counts the subtraction and produces a broken 1180 overlay.

Set daemon config in each node's host_vars — the swarm playbook does not write daemon.json, so variables in swarm group_vars have no effect on it:

```yaml
# host_vars/swarm-node.yml
docker_enabled: true
docker_mtu: 1280  # Tailscale interface MTU; Docker derives overlay (1230)
docker_swarm_enabled: true
docker_swarm_role: manager
docker_swarm_advertise_addr: "100.64.0.1"  # Tailscale IP
```

## GPU Support (AMD)

Setting `docker_gpu_enabled: true` on a host:

- Installs `amd-container-toolkit` from the official AMD repo.
- Generates `/etc/cdi/amd.json` via `amd-ctk cdi generate`.
- Registers `amd-container-runtime` as the daemon's default runtime and enables the CDI feature.

Services access the GPU by setting `AMD_VISIBLE_DEVICES=all` in their environment and placing on a node with a matching label (e.g. `node.labels.gpu == true`). No device entries, no volume mounts, no `group_add` needed — the runtime handles device injection.

Swarm `generic_resources` are not used for GPU scheduling: on hardware without a GPU UUID the AMD runtime misinterprets the `DOCKER_RESOURCE_*` env var injected by swarm and declines to attach devices. Use a label-based placement constraint instead.

For LXC containers, GPU device passthrough (`/dev/dri/*`, `/dev/kfd`) and the `gid` on those device files are set by Terraform in `locals.tf`.

## Dependencies

- `community.docker` collection (for swarm tasks)
- `python3-docker` on the target host (auto-installed by the swarm tasks)

## Notes

- `live-restore` is automatically disabled when `docker_swarm_enabled: true`.
- `docker_metrics_enabled: true` forces `experimental: true` in daemon.json (required by dockerd for the metrics endpoint).
- The AMD Container Toolkit apt suite is auto-resolved from the host distribution. Supported: Debian 12/13, Ubuntu 22.04/24.04. Debian 12 and Ubuntu 22.04 use the `jammy` suite; Debian 13 and Ubuntu 24.04 use `noble`.
- The role does not declare its own tag. To target its tasks selectively, wrap the role in a play with `tags: [docker]`.
