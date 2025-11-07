#
# Variables for naming resources.
#
variable "name_prefix" {
  type        = string
  description = "A prefix to add to the names of all resources."
  default     = ""
}

#
# Variables for configuring Confluent Cloud networking and plugging them
# into the external network.
#
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
  type = bool
  description = "Whether to use an existing egress gateway instead of creating a new one."
  default = false
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

#
# Variables for configuring the external network as an AWS VPC.
#
variable "use_aws" {
  type        = bool
  description = "Set module to create AWS specific resources."
  default     = false
}
variable "aws_region" {
  type        = string
  description = "The AWS region where Kafka is deployed."
  default     = ""
}
variable "aws_vpc_id" {
  type        = string
  description = "The ID of the VPC where the Kafka cluster is deployed."
  default     = ""

  validation {
    condition     = length(regexall("^vpc-", var.aws_vpc_id)) > 0
    error_message = "The provided aws_vpc_id '${var.aws_vpc_id}' is not valid. It should start with 'vpc-'."
  }
}
#
# Cross-region isn't supported yet, but might be enabled in the future, avoid using
# these variables for now
#
variable "aws_enable_cross_region" {
  type        = bool
  description = "Enable VPC Endpoint Services and VPC Endpoints to be in different regions."
  default     = false  
}
variable "aws_vpc_endpoint_service_additional_regions" {
  type        = list(string)
  description = "A list of additional regions for the VPC Endpoint Service when aws_enable_cross_region is enabled."
  default     = []
}
variable "aws_kafka_brokers" {
  type = list(object({
    id        = string
    subnet_id = string
    endpoints = list(object({
      host = string
      port = number
      ip   = string
    }))
  }))
  description = "A list of Kafka brokers, with the object shape: { id, subnet_id, endpoints: [{ host, port, ip }] }"
  default     = []
}

#
# Variables for configuring the external network as an Azure VNet. 
# - This doesn't yet have any affect, and is here for future use.
#
variable "use_azure" {
  type        = bool
  description = "Set module to create Azure specific resources."
  default     = false
}

#
# Variables for configuring the external network as a GCP VPC.
# - This doesn't yet have any affect, and is here for future use.
#
variable "use_gcp" {
  type        = bool
  description = "Set module to create GCP specific resources."
  default     = false
}

