output "pls_resource_ids" {
  description = "PLS resource IDs per broker, keyed broker-<id>."
  value       = { for k, pls in azurerm_private_link_service.brokers : k => pls.id }
}

output "lb_count" {
  description = "Number of per-broker load balancers created (0 in bring-your-own-LB mode). Used for testing."
  value       = length(azurerm_lb.brokers)
}
