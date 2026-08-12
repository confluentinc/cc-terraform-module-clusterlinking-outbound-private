output "pls_resource_ids" {
  description = "PLS resource IDs per broker (Azure)."
  value       = module.networking.pls_resource_ids
}

output "gateway_id" {
  description = "Confluent egress gateway ID (Azure)."
  value       = var.cc_use_existing_egress_gateway ? data.confluent_gateway.azure["main"].id : confluent_gateway.azure["main"].id
}

output "access_point_ids" {
  description = "Confluent access point IDs per broker (Azure)."
  value       = { for k, ap in confluent_access_point.azure : k => ap.id }
}

output "dns_record_ids" {
  description = "Confluent DNS record IDs per broker (Azure)."
  value       = { for k, dns in confluent_dns_record.azure : k => dns.id }
}
