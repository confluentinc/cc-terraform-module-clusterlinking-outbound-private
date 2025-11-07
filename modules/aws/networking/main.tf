data "aws_vpc" "main" {
  id = var.aws_vpc_id
}

#
# Each Kafka broker will needs its own VPC Endpoint Service, and therefore a 
# NLB. This Security Group is configured to allow access to the specific 
# broker listener ports based on the configuration of the cluster. 
#
resource "aws_security_group" "main" {
  name   = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}kafka_vpces_nlb_sg"
  vpc_id = data.aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}kafka_vpces_nlb_sg"
    description = "Security Group for VPC Endpoint Services for Kafka brokers managed by Terraform"
  }
}
resource "aws_security_group_rule" "listeners" {
  for_each          = { for key, value in toset(flatten([for broker in var.aws_kafka_brokers : [for endpoint in broker.endpoints : { port = endpoint.port }]])) : "${value.port}" => value }
  type              = "ingress"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.main.id
}

#
# Each broker in the cluster needs its own NLB and VPC Endpoint Service. 
# This is because NLB's are not "Kafka aware", meaning they doen't know 
# Kafka partition assignments or leadership, and therefore cannot 
# intelligently route requests. 
#
resource "aws_lb" "brokers" {
  for_each                         = { for key, value in var.aws_kafka_brokers : "broker-${value.id}" => value }
  name                             = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}broker-${each.value.id}-vpces-nlb"
  load_balancer_type               = "network"
  subnets                          = var.aws_enable_cross_region ? [for value in [for broker in var.aws_kafka_brokers : broker.subnet_id] : value] : [each.value.subnet_id]
  security_groups                  = [aws_security_group.main.id]
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true
  internal                         = true
  idle_timeout                     = 60
  tags = {
    Name        = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}broker-${each.value.id}-vpces-nlb"
    Description = "Network Load Balancer for VPC Endpoint Service for Kafka broker ${each.value.id} managed by Terraform"
  }
}

resource "aws_lb_target_group" "brokers" {
  for_each = { for key, value in flatten([for broker in var.aws_kafka_brokers : [for endpoint in broker.endpoints : { id = broker.id, port = endpoint.port }]]) : "broker-${value.id}-port-${value.port}" => value }
  # Name needs to be clamped to <=32 characters, dropped the prefix
  name        = "broker-${each.value.id}-port-${each.value.port}-vpces-nlb-tg"
  vpc_id      = data.aws_vpc.main.id
  port        = each.value.port
  protocol    = "TCP"
  target_type = "ip"

  tags = {
    Name        = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}broker-${each.value.id}-port-${each.value.port}-vpces-nlb-tg"
    Description = "Target Group for VPC Endpoint Service for Kafka broker ${each.value.id}s ${each.value.port} listener managed by Terraform"
  }
}

resource "aws_lb_target_group_attachment" "brokers" {
  for_each         = { for key, value in flatten([for broker in var.aws_kafka_brokers : [for endpoint in broker.endpoints : { id = broker.id, ip = endpoint.ip, port = endpoint.port }]]) : "broker-${value.id}-port-${value.port}" => value }
  target_group_arn = aws_lb_target_group.brokers[each.key].arn
  target_id        = each.value.ip
  port             = each.value.port
}

resource "aws_lb_listener" "brokers" {
  for_each          = { for key, value in flatten([for broker in var.aws_kafka_brokers : [for endpoint in broker.endpoints : { id = broker.id, port = endpoint.port }]]) : "broker-${value.id}-port-${value.port}" => value }
  load_balancer_arn = aws_lb.brokers["broker-${each.value.id}"].arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.brokers[each.key].arn
  }
}

#
# Each VPC Endpoint Service maps to a single NLB, which maps to a single 
# broker in the cluster. VPC Endpoints can be attached to each VPC Endpoint 
# Service to enable private connectivity to the brokers and a simple Route53 
# Private Hosted Zone can be used to map each VPC Endpoint to their 
# corresponding broker endpoint. 
#
resource "aws_vpc_endpoint_service" "brokers" {
  for_each                   = { for key, value in var.aws_kafka_brokers : "broker-${value.id}" => value }
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.brokers[each.key].arn]
  allowed_principals         = var.cc_gateway_principal_arns
  supported_regions = var.aws_enable_cross_region ? setunion([var.aws_region], toset(var.aws_vpc_endpoint_service_additional_regions)) : [var.aws_region]

  tags = {
    Name        = "${var.name_prefix != "" ? "${var.name_prefix}-" : ""}broker-${each.value.id}-vpces"
    Description = "VPC Endpoint Service for Kafka broker ${each.value.id} managed by Terraform"
  }
  # At cleanup time, the APIs mark resources for deletion, but do not delete them, so 
  # the next resource deletion fails. This local-exec provisioner forces the deletion of any
  # connections before the resource itself is deleted. This might not be necessary in the future.
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
    VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoint-connections --region  ${self.region} --filters "Name=service-id,Values=${self.id}" --query "VpcEndpointConnections[].VpcEndpointId" --output text | tr '\t' ',')
    
    # Only run 'reject' if the VPC_ENDPOINTS variable is not empty
    if [ -n "$VPC_ENDPOINTS" ]; then
      aws ec2 reject-vpc-endpoint-connections --region ${self.region} --service-id ${self.id} --vpc-endpoint-ids $VPC_ENDPOINTS
    fi
    EOT
  }
}

