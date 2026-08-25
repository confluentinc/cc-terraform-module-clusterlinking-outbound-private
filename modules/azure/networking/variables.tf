terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_name" { type = string }
variable "broker_subnet_id" { type = string }
variable "nat_subnet_cidr" { type = string }

variable "brokers" {
  type = list(object({
    id       = string
    host     = string
    nic_name = optional(string)
    port     = optional(number, 9092)
  }))
}

variable "create_load_balancers" { type = bool }
variable "lb_frontend_ip_configuration_ids" {
  type    = map(string)
  default = {}
}
variable "cc_gateway_subscription_id" { type = string }
