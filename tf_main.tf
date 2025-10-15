#
# AWS specific networking resources to create VPC Endpoint Services
#
module "aws_networking" {
	source = "./modules/aws/networking"
	for_each = { for key, value in var.use_aws ? [1] : [] : "main" => {} }

	name_prefix = var.name_prefix

	cc_gateway_principal_arns = confluent_gateway.aws["main"].aws_egress_private_link_gateway[*].principal_arn

	aws_region = var.aws_region
	aws_vpc_id = var.aws_vpc_id
	aws_kafka_brokers = var.aws_kafka_brokers	
}

#
# AWS specific copies of Confluent Cloud resources
#
resource "confluent_gateway" "aws" {
	for_each = { for key, value in var.use_aws ? [1] : [] : "main" => {} }
  display_name = "${var.name_prefix}-gw-egress"
  environment {
    id = var.cc_env_id
  }
  aws_egress_private_link_gateway {
    region = var.aws_region
  }
}
resource "confluent_access_point" "aws" {
	for_each = { for key, value in var.use_aws ? var.aws_kafka_brokers : [] : "broker-${value.id}" => value }
	display_name = "${var.name_prefix}-broker-${each.value.id}-ap"

	environment {
		id = var.cc_env_id
	}

	gateway {
		id = confluent_gateway.aws["main"].id
	}

	aws_egress_private_link_endpoint {
		vpc_endpoint_service_name = module.aws_networking["main"].vpc_endpoint_service_names[each.key]

		# Whether or not to provide endpoints in multiple zones, which is not 
		# necessary for the strategy employed here.
		enable_high_availability  = false
	}
}
resource "confluent_dns_record" "aws" {
	for_each = { for key, value in var.use_aws ? flatten([for broker in var.aws_kafka_brokers : [for endpoint in broker.endpoints : { id = broker.id, host = endpoint.host }]]) : [] : "broker-${value.id}" => value }
	display_name = "${var.name_prefix}-broker-${each.value.id}-dns"
	domain = each.value.host

	environment {
		id = var.cc_env_id
	}

	gateway {
		id = confluent_gateway.aws["main"].id
	}

	private_link_access_point {
		id = confluent_access_point.aws[each.key].id
	}
}