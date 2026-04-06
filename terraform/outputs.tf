output "lxc_resources" {
  description = "Created LXC containers"
  value = {
    for name, ct in proxmox_virtual_environment_container.lxc :
    name => {
      vm_id = ct.vm_id
    }
  }
}

output "vm_resources" {
  description = "Created VMs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => {
      vm_id = vm.vm_id
    }
  }
}
