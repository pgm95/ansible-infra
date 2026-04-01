# Docker Swarm Infrastructure

## Purpose

Bootstraps Docker Swarm clusters across heterogeneous infrastructure (LXC, VM, VPS). Stops at infrastructure layer - workloads managed in separate repo.

## Architecture Decisions

### Why Separate Playbook?

Swarm requires **cross-host orchestration** that doesn't fit the standard provision-per-host pattern:

1. Init node creates cluster and generates tokens
2. Tokens must be shared to other nodes before they can join
3. Managers must join before workers (Raft quorum)

Standard role inclusion can't handle this - needs dedicated orchestration playbook.

### Why Single Dynamic Group?

Considered 4 groups (swarm, swarm_managers, swarm_workers, swarm_init) but rejected:

- **Complexity**: More groups = more inventory management
- **Inflexibility**: Hard to change node roles
- **Redundancy**: Role/init are host properties, not group membership

Solution: Single `swarm` group populated at runtime, role differentiation via `docker_swarm_role` and `docker_swarm_init` variables.

### Why Serial Execution?

Swarm uses Raft consensus. Parallel node joins can cause:

- Split-brain during manager elections
- Token retrieval race conditions
- Inconsistent cluster state

All bootstrap operations run `serial: 1` for stability.

### Why Computed daemon.json?

Previous approach: Override entire `docker_daemon_config` dict per host.
Problem: Verbose, error-prone, hard to maintain defaults.

New approach: Individual variables → computed config with empty value filtering.

- Set `docker_mtu: 1230` → only MTU appears in daemon.json
- Defaults don't pollute config
- Easy per-host overrides

## Key Patterns

### Token Flow

```text
Init Node                    Localhost                    Join Nodes
    │                            │                            │
    ├─► docker_swarm init        │                            │
    ├─► retrieve tokens ─────────┼─► set_fact (delegate)      │
    │                            │                            │
    │                            ├─► hostvars['localhost']    │
    │                            │   .swarm_manager_token ────┼─► join
```

Tokens cached on localhost during play, available to all subsequent hosts via hostvars.

### Discovery Pattern

Discovery task scans `inventory/{env}/host_vars/lxc/*.yml`, `host_vars/vm/*.yml`, and `host_vars/*.yml` (static hosts like VPS) for `docker_swarm_enabled: true`, then:

**`ansible_host` Resolution** (three-tier fallback in `add_host`):

1. `item.config.ansible_host` — literal value from raw host_vars YAML
2. `hostvars[item.name].ansible_host` — from Ansible inventory (static hosts only, Jinja2 evaluated)
3. `item.name ~ '.' ~ proxmox_dns_domain` — DNS fallback for dynamic LXC/VM hosts

Tier 2 resolves static hosts (VPS) whose `ansible_host` is defined in `hosts.yml` with Jinja2 expressions (e.g., env var lookups). Only fires when `item.name in hostvars` — safe for dynamic hosts that don't exist yet.

Discovery then:

1. Validates exactly one `docker_swarm_init: true`
2. Validates at least one manager
3. Registers hosts to `swarm` group via `add_host`
4. Passes all swarm variables through

### Delegation Pattern

Node configuration (labels, availability) requires manager API access. Non-init nodes delegate to init node:

```yaml
delegate_to: "{{ _swarm_init_host }}"
```

`_swarm_init_host` set during discovery for all nodes.

## Networking

### Tailscale for Heterogeneous Clusters

Challenge: LXC/VM behind NAT can't directly reach VPS (or each other without hairpin NAT).

Possible Solution: Tailscale mesh network

- All nodes get Tailscale IPs (100.x.x.x)
- Set `docker_swarm_advertise_addr` to Tailscale IP
- Swarm traffic encrypted via WireGuard tunnel
- No port forwarding needed

### MTU Calculation

Tailscale uses MTU 1280 for maximum network compatibility (handles CGNAT, etc.):

```text
Tailscale:    1280
- VXLAN:       -50  → 1230
```

Set `docker_mtu: 1230` in each swarm node's **host_vars** (not in `playbooks/group_vars/swarm.yml` — the swarm playbook does not write daemon.json, so daemon config variables there have no effect).

For non-Tailscale setups, use `docker_mtu: 0` (auto).

### Swarm Ports (over Tailscale)

| Port | Protocol | Purpose |
| ------ | ---------- | --------- |
| 2377 | TCP | Cluster management |
| 7946 | TCP/UDP | Node communication |
| 4789 | UDP | Overlay network (VXLAN) |

All flow over Tailscale tunnel when `advertise_addr` is Tailscale IP.

### VXLAN Security (Public IP Exposure)

**Problem**: Docker Swarm binds VXLAN (port 4789/UDP) to `0.0.0.0` regardless of `--data-path-addr`. On nodes with public IPs, this exposes the overlay network to the internet.

```bash
# Example: nerd1 with public IP 107.172.6.154
ss -ulnp | grep 4789
UNCONN 0 0  0.0.0.0:4789  0.0.0.0:*   # Exposed on public IP!
```

**Official Docker stance**: `--data-path-addr` is informational only; firewall rules are required.

**Solution**: The `docker_swarm_vxlan_interface` variable creates an iptables rule to restrict VXLAN:

```yaml
# inventory/{env}/host_vars/vps/nerd1.yml
docker_swarm_vxlan_interface: tailscale0  # Only allow VXLAN on Tailscale
```

This creates:

```bash
iptables -A INPUT ! -i tailscale0 -p udp --dport 4789 -j DROP
```

**Automatic handling**:

- Installs `iptables-persistent` when restriction is enabled
- Rule saved to `/etc/iptables/rules.v4` (survives reboot)
- Only applies to hosts with `docker_swarm_vxlan_interface` set

**When to use**: Any swarm node with a public IP where overlay traffic should only flow over VPN/Tailscale.

## Recent Fixes (2026-01)

### Stale Swarm and Background Join Handling (2026-02)

**Problem**: Nodes with leftover swarm state from previous clusters fail with "already part of a swarm". Docker's join also frequently times out over Tailscale ("Timeout was reached before node joined"), with the join continuing in the background.

**Solution**: The join block in `swarm.yml` uses `ignore_errors` with structured recovery:

1. **Attempt join** — single attempt, no retries (retries cause "already part of a swarm" conflicts when background joins are in progress)
2. **Stale swarm recovery** — if "already part of a swarm", force leave via CLI (`docker swarm leave --force`), pause 5s, retry join
3. **Background join polling** — if "Timeout was reached", poll `docker_swarm_info` with `failed_when: false` until `docker_swarm_active` is true (the `docker_swarm_info` module errors on non-manager nodes but still returns the active flag)
4. **Verify** — assert that one of the three paths succeeded

**Key insight**: Don't use `retries` on the join task. The first attempt starts a background join; subsequent retries see this as "already part of a swarm" and fail, making recovery harder.

### LXC Physical MTU and Tailscale (2026-02)

**Problem**: LXC containers with `lxc_net_mtu: "1230"` (intended for Docker VXLAN) break Tailscale's WireGuard tunnel. The physical eth0 MTU (1230) is too small for Tailscale packets (1280) + WireGuard overhead (~80 bytes). Raft gRPC connections silently fail with "failed to retrieve remote root CA certificate" / "context deadline exceeded".

**Symptom**: Tailscale pings work, TCP connects work, even TLS handshakes work (small segments), but Docker Swarm join times out. `docker node ls` on the manager never shows the LXC node.

**Fix**: `lxc_net_mtu` must be `""` (bridge default 1500) when Tailscale runs inside the container. Docker's overlay MTU (1230) is set via `docker_mtu` in daemon.json, not on the physical interface.

**Diagnosis**: `ping -M do -s 1252 <peer_ts_ip>` — 100% loss confirms the physical MTU is too small.

### Race Condition: Tailscale Route Convergence

**Problem**: Join fails with "could not connect to prospective new cluster member using its advertised address" because Tailscale peer routes may not be fully converged when Ansible attempts the join.

**Solution**: Pre-flight connectivity checks before join:

1. Forward check: Joining node → manager:2377 (60s timeout)
2. Reverse check: Init node → joining node:22 (delegated, 60s timeout)
3. Join retry logic: 3 attempts, 30s delay between retries

### Reset/Bootstrap Task Collision

**Problem**: `--tags reset` runs both reset AND bootstrap tasks because `include_role` doesn't propagate tag filters to included tasks.

**Solution**: Variable-based control flow instead of tags:

- Reset play passes `_swarm_reset_mode: true`
- All bootstrap blocks check `not _swarm_reset_mode | default(false)`
- Reset block checks `_swarm_reset_mode | default(false)`

### Variable Precedence Override (Resolved 2026-02)

**Problem**: Host-specific variables from `add_host` were overwritten by `group_vars/swarm.yml` when loaded via `vars_files` (play-level precedence > inventory-level).

**Solution**: Removed `vars_files: ../inventory/group_vars/swarm.yml` from bootstrap and reset plays entirely. The file (now at `playbooks/group_vars/swarm.yml`) is auto-loaded at playbook level via the `swarm: {}` group, where it has lower precedence than `add_host` variables. Host-specific overrides now win as intended.

**Key insight**: The same file loaded via `vars_files` (play-level) has higher precedence than when auto-loaded via inventory group membership. Removing the explicit `vars_files` reference is the fix, not changing the file's contents.

**Further evolution (env separation)**: All `vars_files` blocks referencing `../vault.yml` were removed from swarm plays. Vault secrets are now auto-loaded via `inventory/{env}/group_vars/all/vault.yml`. Shared group_vars moved to `playbooks/group_vars/` (auto-loaded by Ansible from the playbook directory).

### Jinja2 Length Filter on Non-Strings

**Problem**: `docker_swarm_advertise_addr | length > 0` fails silently when variable is empty or has unexpected type.

**Solution**: Use robust fallback pattern:

```yaml
_advertise_addr: "{{ docker_swarm_advertise_addr | default('') | string or ansible_default_ipv4.address }}"
```

## Constraints

### Dynamic Discovery Limitations

The `discover_swarm.yml` task reads host_vars from `inventory/{env}/host_vars/{lxc,vm,vps}/` as raw YAML - Jinja2 templates are NOT evaluated. Variables like `docker_swarm_advertise_addr` must use **literal values**, not template references:

```yaml
# WRONG - template not evaluated during discovery
docker_swarm_advertise_addr: "{{ tailscale_ip }}"

# CORRECT - literal value
docker_swarm_advertise_addr: 100.88.0.1
```

### Init Node Ordering

Discovery sorts hosts so init node is registered first. Without this, `serial: 1` would process hosts in file discovery order, causing join failures (non-init nodes try to join before init creates cluster).

### WAN/Tailscale Timeout

Default Docker API timeout is too short for WAN connections. The `docker_swarm_timeout` variable (default: 120s) provides adequate time for Raft handshakes over Tailscale.

```yaml
docker_swarm_timeout: 120  # Increase for high-latency links
```

### VXLAN Interface Restriction

The `docker_swarm_vxlan_interface` variable restricts overlay traffic to a specific interface. Required for nodes with public IPs:

```yaml
docker_swarm_vxlan_interface: tailscale0  # Only on VPS nodes with public IP
```

**Note**: Variable must be passed through `discover_swarm.yml` via `add_host` since swarm uses dynamic inventory. Discovery reads from `inventory/{env}/host_vars/`.

### LXC Requirements

Docker in LXC requires:

- `lxc_feature_nesting: true` (mandatory)
- `lxc_feature_keyctl: true` (for secrets)
- Schema enforces: swarm_enabled → nesting enabled

### live-restore Incompatibility

Docker's live-restore feature conflicts with Swarm (causes split-brain on daemon restart). Automatically disabled:

```yaml
docker_daemon_config:
  live-restore: "{{ false if docker_swarm_enabled else docker_live_restore }}"
```

### Raft Tuning

Default Raft settings work for most cases. Tune for high-latency links:

- `docker_swarm_election_tick`: Increase for WAN (default: 10)
- `docker_swarm_heartbeat_tick`: Keep low (default: 1)

Rule: election_tick >= 10 * heartbeat_tick

## Files

| File | Role |
| ------ | ------ |
| `playbooks/swarm.yml` | 5-play orchestration |
| `playbooks/tasks/discover_swarm.yml` | Host discovery + validation |
| `roles/applications/docker/tasks/swarm.yml` | Init/join/leave operations |
| `roles/applications/docker/defaults/main.yml` | All variables + computed daemon.json |
| `playbooks/group_vars/swarm.yml` | Swarm-wide shared defaults (MTU, tokens) |

## Usage

```bash
# Bootstrap cluster
mise run swarm:deploy

# Check status
mise run swarm:status

# Remove nodes (destructive)
mise run swarm:reset    # DESTRUCTIVE
```

## Gotchas

1. **~~`vars_files` overrides `add_host` variables~~** (Resolved 2026-02): Fixed by removing `vars_files` from bootstrap/reset plays. Shared group_vars now live at `playbooks/group_vars/` (auto-loaded by Ansible) where `add_host` wins.

2. **Block tags don't filter internal tasks**: Tagging a block doesn't create an implicit tag filter for tasks inside. Use `when` conditions with control variables instead.

3. **YAML IP address parsing**: `100.88.0.3` parses as string (multiple dots), but always quote IPs in host_vars for safety.

4. **Delegated task variable context**: When delegating with `delegate_to`, variables are evaluated in the context of the *delegating* host, not the delegate target.

5. **`include_role` vs `import_role` tags**: `include_role` is dynamic and doesn't inherit tag context from `--tags`. Tags must be handled inside the role.

## Limitations

- **No automatic Tailscale wait**: The connectivity checks use fixed timeouts, not Tailscale status detection
- **Single init node only**: No support for promoting a node to init or multi-init failover
- **No rolling updates**: All nodes process serially; no blue-green or canary patterns

## Can Be Improved

1. **Tailscale status integration**: Check `tailscale status --json` for peer connectivity before join attempts instead of blind wait_for
2. **Dynamic timeout scaling**: Adjust timeouts based on geographic distance or measured latency
3. **Idempotent token storage**: Auto-persist tokens to vault after init for truly idempotent reruns
4. **Health check post-join**: Verify Raft quorum health after each manager join, not just at end
5. **Graceful degradation**: On join failure, optionally continue with remaining nodes instead of hard fail
6. **Token display security**: Truncate tokens in debug output (currently gated behind verbosity: 1 but could leak to CI logs)

## Hardening (2026-02)

Systematic analysis and fixes applied to docker role and swarm config:

### Security

- **VXLAN public IP warning**: `swarm.yml` now warns (always visible, no verbosity gate) when a node has a non-private IP and `docker_swarm_vxlan_interface` is empty. Detects RFC1918, CGNAT, loopback, and link-local ranges.
- **Listen address derives from advertise address**: `docker_swarm_listen_addr` defaults to `advertise_addr:2377` when `docker_swarm_advertise_addr` is set. Falls back to `0.0.0.0:2377` only when no advertise address is configured. Applied in role defaults and discovery passthrough.
- **Hostname validation**: Assertion before node label/availability operations verifies `ansible_hostname == inventory_hostname`. Prevents silent misapplication if system hostname diverges from what Docker registered at join time.

### Validation

- **Init-must-be-manager**: Discovery validates that the node with `docker_swarm_init: true` also has `docker_swarm_role: manager`. Both LXC and VM schemas already had this as a JSON Schema conditional; the runtime assertion catches VPS hosts (no schema).
- **`docker_swarm_timeout` passthrough**: Added to `add_host` block in discovery and to `playbooks/group_vars/swarm.yml` for visibility.

### Architecture

- **Reset ordering**: Replaced single play with `order: reverse_sorted` (hostname-dependent) with three role-sequenced plays: workers → non-init managers → init node. Ordering is now in play structure, not hostname coincidence.
- **Advertise address deduplication**: Single `set_fact` for `_advertise_addr` after state facts (with `tags: [always]`), replacing three identical computations in init/existing/join blocks.
- **Discovery single-parse**: Host_vars files are parsed once into `_all_host_configs`, then filtered by `docker_swarm_enabled` via `selectattr`. Previously each file was parsed twice (once in `when`, once in `set_fact`).

### Quality

- **Structured status output**: `swarm:status` mise task uses `ANSIBLE_STDOUT_CALLBACK=json` + `jq` instead of fragile `grep`/`sed` pipeline.
- **Apt cache optimization**: `cache_valid_time: 3600` on `python3-docker` installation to skip redundant cache refreshes on idempotent runs.
- **Raft tick documentation**: Schema descriptions for `election_tick` and `heartbeat_tick` now note that role defaults (10/1) are overridden to 30/3 in `playbooks/group_vars/swarm.yml` for WAN/Tailscale latency.

## Scope

**In scope**: Cluster bootstrap, node management, daemon config, networking
**Out of scope**: Stacks, services, secrets, registries, monitoring, ingress
