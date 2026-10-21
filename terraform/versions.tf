terraform {
  required_version = ">= 1.5.0"
  required_providers {
    arvan = {
      source = "arvancloud/arvan"
      version = "= 0.6.4"
    }
  }
}
provider "arvan" {
  api_key = var.arvan_api_key
}
