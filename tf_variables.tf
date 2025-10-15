#
# Variables for naming resources.
#
variable "name_prefix" {
  type = string
  description = "A prefix to add to the names of all resources."
}

#
# Variables for configuring the external network as an AWS VPC.
#
variable "use_aws" {
  type = bool
}
variable "aws_region" {
  type        = string
  description = "The AWS region where everything is deployed."
}
variable "aws_vpc_id" {
  type        = string
  description = "The ID of the VPC where the Kafka cluster is deployed."

  validation {
    condition = length(regexall("^vpc-", var.aws_vpc_id)) > 0
    error_message = "The provided aws_vpc_id '${var.aws_vpc_id}' is not valid. It should start with 'vpc-'."
  }
}
variable "aws_kafka_brokers" {
  type = list(object({
    id = string
    subnet_id = string
    endpoints = list(object({
      host = string
      port = number
      ip  = string
    }))
  }))
  description = "A list of Kafka brokers, which the object shape: { id, subnet_id, endpoints: [{ dns, port, ip }] }"
}

#
# Variables for configuring Confluent Cloud networking and plugging them
# into the external network.
#
variable "cc_env_id" {
  type        = string
  description = "The ID of the Confluent Environment where the target cluster is deployed."

  validation {
    condition = length(regexall("^env-", var.cc_env_id)) > 0
    error_message = "The provided cc_end_id '${var.cc_env_id}' is not valid. It should start with 'env-'."
  }
}

variable "cc_cluster_id" {
  type        = string
  description = "The ID of the Confluent target cluster."

  validation {
    condition = length(regexall("^lkc-", var.cc_cluster_id)) > 0
    error_message = "The provided cc_cluster_id '${var.cc_cluster_id}' is not valid. It should start with 'lkc-'."
  }
}

