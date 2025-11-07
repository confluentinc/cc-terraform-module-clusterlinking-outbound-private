#
# Variables for naming resources.
#
variable "name_prefix" {
  type = string
  description = "A prefix to add to the names of all resources."
}

#
# Variables for Confluent specific external components.
#
variable "cc_gateway_principal_arns" {
  type        = list(string)
  description = "The ARNs of the Confluent Gateway principal(s), which are required when creating VPC Endpoint Services."
}

#
# Variables for configuring creating VPC Endpoint Services.
#
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
variable "aws_enable_cross_region" {
  type        = bool
  description = "Enabled VPC Endpoint Services and VPC Endpoints to be in different regions."
  default     = false  
}
variable "aws_vpc_endpoint_service_additional_regions" {
  type        = list(string)
  description = "A list of additional regions for the VPC Endpoint Service when cross-region is enabled."
  default     = []
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
  description = "A list of Kafka brokers, with the object shape: { id, subnet_id, endpoints: [{ host, port, ip }] }"
}