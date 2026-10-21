output "inventory_nodes" {
  description = "Raw address lists from Arvan; generator selects only RFC1918 IPv4 and fails on ambiguity."
  value = {
    for name, vm in arvan_iaas_abrak.vm :
    name => {
      id             = vm.id
      addresses      = vm.addresses
      data_volume_id = try(arvan_iaas_volume.data[name].id, null)
    }
  }
}
