variable "arvan_api_key" {
  type      = string
  sensitive = true
}

variable "region" {
  type = string
}

variable "network_names" {
  type        = list(string)
  description = "Existing Arvan network names. Verify private network assignment in plan."
}

variable "ssh_key_name" {
  type        = string
  default     = null
  description = "Existing Arvan SSH key name. Null creates password-only VMs (not recommended)."
}

variable "machines" {
  description = "Approved flavor IDs and image names must be supplied per machine. Provider flavors are not vCPU/RAM integers."
  type = map(object({
    flavor          = string
    image_type      = string
    image_name      = string
    disk_size       = number
    data_disk_size  = optional(number, 0)
    security_groups = list(string)
    enabled         = bool
  }))

  validation {
    condition     = alltrue([for vm in values(var.machines) : vm.data_disk_size >= 0 && vm.disk_size > 0])
    error_message = "disk_size must be positive and data_disk_size must be zero or positive."
  }
}
