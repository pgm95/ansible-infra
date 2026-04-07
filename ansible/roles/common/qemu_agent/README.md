# QEMU Guest Agent Role

Automatically detects and installs QEMU Guest Agent on compatible QEMU/KVM virtual machines. Enables enhanced host-guest communication and management capabilities.

## Features

- Automatic QEMU/KVM virtualization detection
- virtio guest agent port availability check
- Conditional installation (only on compatible VMs)
- Automatic service enablement
- Graceful failure handling (doesn't block deployment)
- Zero configuration required

## Requirements

- QEMU/KVM virtual machine
- virtio guest agent port available
- Debian/Ubuntu based system
- Root or sudo access

## Role Variables

### Core Configuration

**qemu_agent_enabled** (boolean, default: `false`)
Master switch to enable QEMU guest agent auto-detection and installation.

## How It Works

The role performs three checks before installation:

1. **Virtualization Detection**: Checks if `ansible_facts.virtualization_type` is `kvm` or `qemu`
2. **Port Availability**: Verifies `/dev/virtio-ports/org.qemu.guest_agent.0` exists
3. **Installation**: Only installs if both checks pass

If any check fails, installation is skipped silently.

## Workflow

### Basic Installation

1. Enable in group_vars or host_vars:

```yaml
qemu_agent_enabled: true
```

1. Run playbook:

```bash
task vps:deploy -- --tags qemu,vm
```

### Automatic Detection

The role automatically skips installation if:

- System is not a QEMU/KVM VM
- virtio guest agent port is not available
- VM is not configured with guest agent support

No manual configuration needed.

## Guest Agent Capabilities

Once installed, QEMU guest agent enables:

**VM Management:**

- Clean shutdown and restart
- File system quiescing for snapshots
- Guest IP address reporting

**Information Gathering:**

- OS information
- File system details
- Network configuration

**File Operations:**

- File read/write from host
- File system freeze/thaw

## Hypervisor Configuration

For the guest agent to work, the VM must be configured with:

**QEMU/KVM:**

```bash
-device virtio-serial
-chardev socket,path=/var/lib/qemu/guest-agent.sock,server,nowait,id=qga0
-device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0
```

**Proxmox VE:**
Enable in VM options:

```
QEMU Guest Agent: Yes
```

**Libvirt XML:**

```xml
<channel type='unix'>
  <source mode='bind'/>
  <target type='virtio' name='org.qemu.guest_agent.0'/>
</channel>
```

## Service Management

**Service Name**: `qemu-guest-agent`

**Commands:**

```bash
# Check status
systemctl status qemu-guest-agent

# Restart service
systemctl restart qemu-guest-agent

# View logs
journalctl -u qemu-guest-agent
```

## Detection Logic

```
qemu_agent_enabled == true
    ↓
Is virtualization_type in [kvm, qemu]?
    ↓ Yes
Does /dev/virtio-ports/org.qemu.guest_agent.0 exist?
    ↓ Yes
Install qemu-guest-agent package
    ↓
Enable and start service
```

## Failure Handling

The role uses `failed_when: false` for service start. This means:

- Installation completes even if service fails to start
- Deployment continues to other roles
- Useful when VM lacks proper guest agent channel

Check logs if service fails:

```bash
journalctl -u qemu-guest-agent -n 50
```

## Tags

- `qemu`: QEMU guest agent installation
- `vm`: Virtual machine configuration

## Dependencies

None. This is a standalone role that can be used independently.

## Use Cases

### When to Enable

- Running VMs on QEMU/KVM hypervisor
- Using Proxmox VE for VM management
- Need clean snapshot capabilities
- Want guest IP reporting to hypervisor
- Running multiple VMs with standardized management

### When to Disable

- Bare metal servers
- Non-QEMU virtualization (VMware, VirtualBox, etc.)
- Containers (LXC, Docker)
- Systems where guest agent is not supported

## Verification

### Check Installation

```bash
# Verify package installed
dpkg -l | grep qemu-guest-agent

# Check service status
systemctl status qemu-guest-agent

# Verify port exists
ls -la /dev/virtio-ports/org.qemu.guest_agent.0
```

### Test from Hypervisor

**Proxmox:**

```bash
qm agent <vmid> ping
qm agent <vmid> get-osinfo
qm agent <vmid> network-get-interfaces
```

**virsh:**

```bash
virsh qemu-agent-command <vm-name> '{"execute":"guest-ping"}'
virsh qemu-agent-command <vm-name> '{"execute":"guest-info"}'
```

## Common Issues

**Service fails to start:**

- VM lacks virtio guest agent channel
- Channel not configured in hypervisor
- Permission issues with socket

**Package not installed:**

- Not running on QEMU/KVM
- virtio port not available
- qemu_agent_enabled is false

**Agent not responding from hypervisor:**

- Service not running: `systemctl start qemu-guest-agent`
- Wrong channel configuration in VM
- Firewall blocking communication

## File Structure

```
/dev/virtio-ports/org.qemu.guest_agent.0    # Guest agent communication port
/etc/systemd/system/qemu-guest-agent.service # Service unit file
```

## Notes

- Installation is conditional and automatic
- No configuration required beyond enabling the role
- Service failures don't block deployment
- Compatible with Proxmox VE out of the box
- Detection logic prevents installation on incompatible systems
- Guest agent communication is secure (local virtio channel)
- No network exposure
- Minimal resource usage
