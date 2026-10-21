# Arvan provider v0.6.4 is archived. Validate the plan against the live API before applying.
resource "arvan_iaas_abrak" "vm" {
  for_each = { for name, vm in var.machines : name => vm if vm.enabled }
  name = each.key
  region = var.region
  flavor = each.value.flavor
  disk_size = each.value.disk_size
  image {
    type = each.value.image_type
    name = each.value.image_name
  }
  networks = var.network_names
  security_groups = each.value.security_groups
  key_name = var.ssh_key_name
}
