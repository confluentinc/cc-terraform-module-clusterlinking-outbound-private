output "vpc_endpoint_service_names" {
	value = { for key, value in aws_vpc_endpoint_service.brokers : key => value.service_name }
}