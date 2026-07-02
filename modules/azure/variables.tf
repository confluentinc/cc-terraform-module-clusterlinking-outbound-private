variable "name_prefix" {
  type        = string
  description = "A prefix to add to the names of all resources."
  default     = ""
}

variable "cc_env_id" {
  type        = string
  description = "The ID of the Confluent Environment where the target cluster is deployed."
  validation {
    condition     = length(regexall("^env-", var.cc_env_id)) > 0
    error_message = "The provided cc_env_id '${var.cc_env_id}' is not valid. It should start with 'env-'."
  }
}

variable "cc_cluster_id" {
  type        = string
  description = "The ID of the Confluent target cluster."
  validation {
    condition     = length(regexall("^lkc-", var.cc_cluster_id)) > 0
    error_message = "The provided cc_cluster_id '${var.cc_cluster_id}' is not valid. It should start with 'lkc-'."
  }
}

variable "cc_use_existing_egress_gateway" {
  type        = bool
  description = "Whether to use an existing egress gateway instead of creating a new one."
  default     = false
}

variable "cc_egress_gateway_id" {
  type        = string
  description = "The ID of an existing Confluent egress gateway to use if cc_use_existing_egress_gateway is true."
  default     = ""
  validation {
    condition     = length(regexall("^gw-", var.cc_egress_gateway_id)) > 0 || var.cc_egress_gateway_id == ""
    error_message = "The provided cc_egress_gateway_id '${var.cc_egress_gateway_id}' is not valid. It should start with 'gw-'."
  }
}

variable "azure_region" {
  type        = string
  description = "Azure region for the Gateway and networking resources, for example 'centralus'."
  default     = ""
}

variable "azure_resource_group_name" {
  type        = string
  description = "Name of the existing resource group containing the broker VMs."
  default     = ""
}

variable "azure_vnet_name" {
  type        = string
  description = "Name of the existing VNet containing the broker VMs."
  default     = ""
}

variable "azure_broker_subnet_id" {
  type        = string
  description = "Resource ID of the subnet containing the broker VMs. Used as the LB frontend subnet when create_load_balancers = true."
  default     = ""
}

variable "azure_nat_subnet_cidr" {
  type        = string
  description = "CIDR for the dedicated PLS NAT subnet the module creates in the VNet."
  default     = ""
}

variable "azure_kafka_brokers" {
  type = list(object({
    id       = string
    host     = string
    nic_name = optional(string)
    port     = optional(number, 9092)
  }))
  description = "List of Kafka brokers: { id, host, nic_name?, port? }. host must match advertised.listeners and bootstrap.servers."
  default     = []
}

variable "create_load_balancers" {
  type        = bool
  description = "When true (default) the module creates the per-broker LB + NIC-based backend association (turnkey). When false the customer supplies azure_lb_frontend_ip_configuration_ids (bring-your-own-LB)."
  default     = true
  validation {
    condition = !var.create_load_balancers || alltrue([
      for b in var.azure_kafka_brokers : b.nic_name != null
    ])
    error_message = "nic_name is required for every broker in azure_kafka_brokers when create_load_balancers = true."
  }
}

variable "azure_lb_frontend_ip_configuration_ids" {
  type        = map(string)
  description = "Map of broker id -> LB frontend IP configuration resource ID. Required when create_load_balancers = false."
  default     = {}
  validation {
    condition = var.create_load_balancers || alltrue([
      for b in var.azure_kafka_brokers : contains(keys(var.azure_lb_frontend_ip_configuration_ids), b.id)
    ])
    error_message = "azure_lb_frontend_ip_configuration_ids must contain an entry for every broker id when create_load_balancers = false."
  }
}
