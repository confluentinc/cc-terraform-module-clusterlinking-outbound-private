terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

module "networking" {
  source = "./networking"

  name_prefix                      = var.name_prefix
  resource_group_name              = var.azure_resource_group_name
  vnet_name                        = var.azure_vnet_name
  broker_subnet_id                 = var.azure_broker_subnet_id
  nat_subnet_cidr                  = var.azure_nat_subnet_cidr
  brokers                          = var.azure_kafka_brokers
  create_load_balancers            = var.create_load_balancers
  lb_frontend_ip_configuration_ids = var.azure_lb_frontend_ip_configuration_ids

  cc_gateway_subscription_id = var.cc_use_existing_egress_gateway ? (
    data.confluent_gateway.azure["main"].azure_egress_private_link_gateway[0].subscription
    ) : (
    confluent_gateway.azure["main"].azure_egress_private_link_gateway[0].subscription
  )
}

data "confluent_gateway" "azure" {
  for_each = { for key, value in var.cc_use_existing_egress_gateway ? [1] : [] : "main" => {} }
  id       = var.cc_egress_gateway_id

  environment {
    id = var.cc_env_id
  }
}

resource "confluent_gateway" "azure" {
  for_each     = { for key, value in !var.cc_use_existing_egress_gateway ? [1] : [] : "main" => {} }
  display_name = "${var.name_prefix}-gw-egress"
  environment {
    id = var.cc_env_id
  }
  azure_egress_private_link_gateway {
    region = var.azure_region
  }
}

resource "confluent_access_point" "azure" {
  for_each     = { for key, value in var.azure_kafka_brokers : "broker-${value.id}" => value }
  display_name = "${var.name_prefix}-broker-${each.value.id}-ap"

  environment {
    id = var.cc_env_id
  }
  gateway {
    id = var.cc_use_existing_egress_gateway ? data.confluent_gateway.azure["main"].id : confluent_gateway.azure["main"].id
  }

  azure_egress_private_link_endpoint {
    private_link_service_resource_id = module.networking.pls_resource_ids[each.key]
    # Empty for a Kafka (non-PaaS) egress PLS target; the provider requires the field present.
    private_link_subresource_name = ""
  }

  depends_on = [module.networking]
}

resource "confluent_dns_record" "azure" {
  for_each     = { for key, value in var.azure_kafka_brokers : "broker-${value.id}" => value }
  display_name = "${var.name_prefix}-broker-${each.value.id}-dns"
  domain       = each.value.host

  environment {
    id = var.cc_env_id
  }
  gateway {
    id = var.cc_use_existing_egress_gateway ? data.confluent_gateway.azure["main"].id : confluent_gateway.azure["main"].id
  }

  private_link_access_point {
    id = confluent_access_point.azure[each.key].id
  }
}
