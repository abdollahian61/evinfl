variable "arvan_api_key" {
  type = string
  sensitive = true
}
variable "region" { type = string }
variable "network_names" {
  type = list(string)
  description = "Existing Arvan network names. Verify private network assignment in plan."
}
variable "ssh_key_name" {
  type = string
  default = null
}
variable "machines" {
  description = "Approved flavor IDs and image names must be supplied per machine. Provider flavors are not vCPU/RAM integers."
  type = map(object({
    flavor = string
    image_type = string
    image_name = string
    disk_size = number
    security_groups = list(string)
    enabled = bool
  }))
}
