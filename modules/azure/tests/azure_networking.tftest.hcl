# Mock both providers so plan runs without real cloud credentials.
mock_provider "azurerm" {
  mock_data "azurerm_network_interface" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/networkInterfaces/mock-nic"
      ip_configuration = [{ name = "ipconfig1" }]
    }
  }
}
mock_provider "confluent" {
  mock_resource "confluent_gateway" {
    defaults = {
      azure_egress_private_link_gateway = [{ region = "centralus", subscription = "00000000-0000-0000-0000-000000000000" }]
    }
  }
}

# Shared valid inputs (turnkey mode).
variables {
  name_prefix               = "test"
  cc_env_id                 = "env-test123"
  cc_cluster_id             = "lkc-test123"
  azure_region              = "centralus"
  azure_resource_group_name = "test-rg"
  azure_vnet_name           = "test-vnet"
  azure_broker_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/brokers"
  azure_nat_subnet_cidr     = "10.200.2.0/24"
  azure_kafka_brokers = [
    { id = "1", host = "broker-1.test.internal", nic_name = "broker-1-nic", port = 9092 },
    { id = "2", host = "broker-2.test.internal", nic_name = "broker-2-nic", port = 9092 },
  ]
  create_load_balancers                  = true
  azure_lb_frontend_ip_configuration_ids = {}
}

# 1. Turnkey mode plans and creates one LB per broker.
run "turnkey_creates_lbs" {
  command = plan
  assert {
    condition     = module.networking.lb_count == 2
    error_message = "Expected one LB per broker (2) in turnkey mode."
  }
}

# 2. Turnkey mode with a broker missing nic_name fails the variable validation.
run "turnkey_requires_nic_name" {
  command = plan
  variables {
    azure_kafka_brokers = [
      { id = "1", host = "broker-1.test.internal", port = 9092 }, # no nic_name
    ]
  }
  expect_failures = [var.create_load_balancers]
}

# 3. BYO-LB mode creates zero LBs and uses the supplied frontend IDs.
run "byo_lb_skips_lbs" {
  command = plan
  variables {
    create_load_balancers = false
    azure_kafka_brokers = [
      { id = "1", host = "broker-1.test.internal" },
      { id = "2", host = "broker-2.test.internal" },
    ]
    azure_lb_frontend_ip_configuration_ids = {
      "1" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/loadBalancers/lb-1/frontendIPConfigurations/frontend-1"
      "2" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/loadBalancers/lb-2/frontendIPConfigurations/frontend-2"
    }
  }
  assert {
    condition     = module.networking.lb_count == 0
    error_message = "Expected zero LBs in bring-your-own-LB mode."
  }
}

# 4. BYO-LB mode missing a frontend ID for a broker fails the variable validation.
run "byo_lb_requires_all_frontend_ids" {
  command = plan
  variables {
    create_load_balancers = false
    azure_kafka_brokers = [
      { id = "1", host = "broker-1.test.internal" },
      { id = "2", host = "broker-2.test.internal" },
    ]
    azure_lb_frontend_ip_configuration_ids = {
      "1" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/loadBalancers/lb-1/frontendIPConfigurations/frontend-1" # missing "2"
    }
  }
  expect_failures = [
    var.azure_lb_frontend_ip_configuration_ids,
  ]
}
