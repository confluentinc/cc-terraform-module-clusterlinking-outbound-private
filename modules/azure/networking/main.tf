locals {
  broker_map = { for b in var.brokers : "broker-${b.id}" => b }
  lb_map     = var.create_load_balancers ? local.broker_map : {}
}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Dedicated NAT subnet for PLS (always created). Network policies MUST be off.
resource "azurerm_subnet" "nat" {
  name                                          = "${var.name_prefix}-nat"
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = var.vnet_name
  address_prefixes                              = [var.nat_subnet_cidr]
  private_link_service_network_policies_enabled = false
}

# --- Per-broker LB chain (turnkey mode only) ---
resource "azurerm_lb" "brokers" {
  for_each            = local.lb_map
  name                = "${var.name_prefix}-${each.key}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "${each.key}-frontend"
    subnet_id                     = var.broker_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "brokers" {
  for_each        = local.lb_map
  name            = "${each.key}-backend"
  loadbalancer_id = azurerm_lb.brokers[each.key].id
}

data "azurerm_network_interface" "brokers" {
  for_each            = local.lb_map
  name                = each.value.nic_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_interface_backend_address_pool_association" "brokers" {
  for_each             = local.lb_map
  network_interface_id = data.azurerm_network_interface.brokers[each.key].id
  # Assumes a single (primary) IP configuration per broker NIC; standard for OSK broker VMs.
  ip_configuration_name   = data.azurerm_network_interface.brokers[each.key].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.brokers[each.key].id
}

resource "azurerm_lb_probe" "brokers" {
  for_each            = local.lb_map
  name                = "${each.key}-probe"
  loadbalancer_id     = azurerm_lb.brokers[each.key].id
  protocol            = "Tcp"
  port                = each.value.port
  interval_in_seconds = 15
}

resource "azurerm_lb_rule" "brokers" {
  for_each                       = local.lb_map
  name                           = "${each.key}-rule"
  loadbalancer_id                = azurerm_lb.brokers[each.key].id
  protocol                       = "Tcp"
  frontend_port                  = each.value.port
  backend_port                   = each.value.port
  frontend_ip_configuration_name = "${each.key}-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.brokers[each.key].id]
  probe_id                       = azurerm_lb_probe.brokers[each.key].id
  disable_outbound_snat          = true
}

# --- Per-broker Private Link Service (always created). ---
resource "azurerm_private_link_service" "brokers" {
  for_each            = local.broker_map
  name                = "${var.name_prefix}-${each.key}-pls"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = var.resource_group_name

  load_balancer_frontend_ip_configuration_ids = [
    var.create_load_balancers
    ? azurerm_lb.brokers[each.key].frontend_ip_configuration[0].id
    : var.lb_frontend_ip_configuration_ids[each.value.id]
  ]

  nat_ip_configuration {
    name                       = "${each.key}-nat"
    primary                    = true
    subnet_id                  = azurerm_subnet.nat.id
    private_ip_address_version = "IPv4"
  }

  auto_approval_subscription_ids = [var.cc_gateway_subscription_id]
  visibility_subscription_ids    = [var.cc_gateway_subscription_id]
}
