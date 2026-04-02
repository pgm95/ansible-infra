# Docker Swarm

Rules and constraints for Docker Swarm cluster automation.

## Architecture

Swarm uses a dedicated 5-play playbook (`swarm.yml`) because cross-host orchestration doesn't fit the standard provision-per-host pattern.

- **Serial execution**: All bootstrap operations run `serial: 1` for Raft consensus safety.
- **Single dynamic group**: Role differentiation via `docker_swarm_role` and `docker_swarm_init`, not group membership.
- **Init node first**: Discovery sorts hosts so init node is registered first.

## MTU Rules

- **Never** set `lxc_net_mtu` below 1400 on containers running Tailscale.
- `docker_mtu: 1230` belongs in daemon.json (via `docker_mtu` variable), not on the physical interface.
- `lxc_net_mtu` must be `""` (bridge default 1500) when Tailscale runs inside the container.

### MTU Stack

```
Application (Docker Swarm Raft/gRPC)
    ↓ up to 1280 bytes
tailscale0 (MTU 1280)
    ↓ + ~80 bytes WireGuard overhead = ~1360 bytes
eth0 (physical MTU must be >= 1360)
    ↓
Proxmox bridge
```

### Diagnosis

```bash
# Inside LXC: test path MTU to Tailscale peer
ping -c 1 -M do -s 1252 <peer_ts_ip>   # 1252 + 28 = 1280 total
# 100% loss = physical MTU too small for Tailscale
```

**Symptom**: Tailscale pings work (small ICMP), but gRPC/TLS connections fail. Docker Swarm join times out.

## Discovery

Discovery uses `include_vars` + `delegate_facts: true` to load host_vars, matching the `discover_definitions.yml` pattern. Jinja2 templates in host_vars (including `lookup('env', ...)`) are evaluated normally — variables are lazily resolved when referenced in tasks.

### `ansible_host` Resolution (Two-Tier Fallback)

1. `hostvars[item.name].ansible_host` — from host_vars or static inventory (Jinja2-evaluated)
2. `item.name ~ '.' ~ proxmox_dns_domain` — DNS fallback for dynamic LXC/VM hosts

## Token Flow

```
Init Node → docker_swarm init → retrieve tokens + cluster ID
    → delegate set_fact to localhost
    → hostvars['localhost'].swarm_manager_token → join nodes
    → hostvars['localhost'].swarm_cluster_id → stale detection
```

Tokens and cluster ID cached on localhost during play, available to all subsequent hosts via hostvars.

## VXLAN Security

Docker Swarm binds VXLAN (port 4789/UDP) to `0.0.0.0` regardless of `--data-path-addr`. On nodes with public IPs, this exposes the overlay network.

```yaml
# Required for any swarm node with a public IP
docker_swarm_vxlan_interface: tailscale0
```

Creates: `iptables -A INPUT ! -i tailscale0 -p udp --dport 4789 -j DROP`

- Installs `iptables-persistent` automatically.
- Rule saved to `/etc/iptables/rules.v4` (survives reboot).
- Variable loaded via `include_vars` + `delegate_facts` during discovery (no explicit passthrough needed).

## Variable Precedence Trap

**Do not reintroduce `vars_files` in swarm plays.** The same file loaded via `vars_files` (play-level) has higher precedence than when auto-loaded via inventory group membership. Host-specific `add_host` variables would be silently overwritten.

Shared group_vars at `playbooks/group_vars/swarm.yml` are auto-loaded at playbook level where `add_host` wins.

## Reset Ordering

Reset uses three role-sequenced plays (not hostname-dependent), all with `ignore_unreachable: true`:

1. Workers
2. Non-init managers
3. Init node — before leaving, removes any `Down` nodes from the cluster (demotes managers first, then force-removes)

`ignore_unreachable` ensures reset completes even when nodes have been destroyed (e.g., LXC/VM purged before swarm reset). Unreachable hosts are skipped without failing the play.

## Join Handling

- **No retries** on the join task itself — first attempt starts a background join; retries cause "already part of a swarm" conflicts.
- **Stale swarm recovery (join-time)**: If "already part of a swarm", force leave (`docker swarm leave --force`), pause 5s, retry.
- **Stale cluster detection (post-join)**: Compares node's cluster ID (`_swarm_info.swarm_facts.ID`) with the init node's (`hostvars['localhost'].swarm_cluster_id`). If mismatched and the node was **already active at check time** (`_swarm_info.docker_swarm_active`), force-leaves and resets `_swarm_active: false` so the join block runs. Only triggers for nodes that were in a swarm before the play started — never for freshly-joined nodes.
- **Background join polling**: If "Timeout was reached", poll `docker_swarm_info` until `docker_swarm_active` is true.

## Computed daemon.json

Individual variables → computed config with empty value filtering. No full-dict override needed. `live-restore` automatically disabled when `docker_swarm_enabled` is true (conflicts with Raft).

**daemon.json is written during provisioning** (`lxc:deploy`/`vm:deploy`/`vps:deploy`), not during `swarm:deploy`. Variables that feed `docker_daemon_config` (e.g., `docker_mtu`, `docker_dns_servers`, `docker_dns_search`) must be set in **host_vars**, not `playbooks/group_vars/swarm.yml`. The swarm playbook only handles cluster orchestration — it never writes daemon.json, so daemon config variables in swarm group_vars have no effect.

## Constraints

| Constraint | Details |
|------------|---------|
| LXC nesting | `lxc_feature_nesting: true` required for Docker |
| LXC keyctl | `lxc_feature_keyctl: true` required for Swarm secrets |
| Swarm timeout | `docker_swarm_timeout: 120` for WAN/Tailscale links |
| Raft tuning | `election_tick >= 10 * heartbeat_tick` (defaults: 30/3 for WAN) |
| Init-must-be-manager | Runtime assertion catches VPS hosts without JSON Schema |
| Hostname != inventory | Warning only — inventory hostnames may differ from system hostnames (unified inventory). Node operations use `ansible_hostname` (system) |

## Key Files

| File | Purpose |
|------|---------|
| `playbooks/swarm.yml` | Multi-play orchestration |
| `playbooks/tasks/discover_swarm.yml` | Host discovery + validation |
| `roles/applications/docker/tasks/swarm.yml` | Init/join/leave operations |
| `roles/applications/docker/defaults/main.yml` | All variables + computed daemon.json |
| `playbooks/group_vars/swarm.yml` | Swarm-wide shared defaults |
