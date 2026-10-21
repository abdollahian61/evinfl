# Arvan provider v0.6.4 is archived. Validate the plan against the live API before applying.
locals {
  enabled_machines = { for name, vm in var.machines : name => vm if vm.enabled }
  # Most service VMs expect a second, empty data disk at /dev/sdb (see vms/*/vars.yml).
  data_disks = { for name, vm in local.enabled_machines : name => vm if vm.data_disk_size > 0 }
}

resource "arvan_iaas_abrak" "vm" {
  for_each        = local.enabled_machines
  name            = each.key
  region          = var.region
  flavor          = each.value.flavor
  disk_size       = each.value.disk_size
  networks        = var.network_names
  security_groups = each.value.security_groups
  # The provider sends key_name only together with ssh_key = true.
  ssh_key  = var.ssh_key_name != null
  key_name = var.ssh_key_name

  image {
    type = each.value.image_type
    name = each.value.image_name
  }
}

resource "arvan_iaas_volume" "data" {
  for_each    = local.data_disks
  name        = "${each.key}-data"
  region      = var.region
  size        = each.value.data_disk_size
  description = "Data disk for ${each.key}; formatted only by the data_disk Ansible role."
}

resource "arvan_iaas_volume_attach" "data" {
  for_each    = local.data_disks
  region      = var.region
  abrak_uuid  = arvan_iaas_abrak.vm[each.key].id
  volume_uuid = arvan_iaas_volume.data[each.key].id
}
