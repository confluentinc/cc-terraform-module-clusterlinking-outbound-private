# Confluent Cloud Terraform module for Private Linking external Kafka clusters

Confluent Cloud Cluster Linking provides byte-to-byte replication between two Apache Kafka clusters. This Terraform module configures private networking using Private Link (or the equivalent) so Cluster Linking can reach an external Kafka cluster to perform replication.

## Required providers 
| Provider                 | Version |
|--------------------------|---------|
| `hashicorp/aws`          | ~> 6.0  |
| `confluentinc/confluent` | ~> 2.0  |

## Included submodules 
| Module                     | Description                                                               |
|----------------------------|---------------------------------------------------------------------------|
| `./modules/aws/networking` | AWS Networking module to create necessary resources for AWS Private Link. |

## Input variables
> Note: cloud provider specific variables default to their null or unselected state. One and only one should be selected for the module to create resources correctly without issues. 

| Variable | Default | Type | Implied dependency | Desired exclusivity | Description |
|---|---|---|---|---|---|
| `name_prefix` | `""` | `string` |  |  | A prefix to add to the names of all resources |
| `cc_env_id` |  | `string` |  |  | The ID of the Confluent Environment where the target cluster is deployed |
| `cc_cluster_id` |  | `string` |  |  | The ID of the Confluent target cluster |
| `cc_use_existing_egress_gateway` | `false` | `bool` |  |  | Whether to use an existing egress gateway instead of creating a new one. |
| `cc_egress_gateway_id` | `""` | `string` | `cc_use_existing_egress_gateway` |  | The ID of an existing Confluent egress gateway to use if `cc_use_existing_egress_gateway` is true. |
| `use_aws` | `false` | `bool` |  | `use_azure`, `use_gcp` | Set module to create AWS specific resources |
| `aws_region` | `""` | `string` | `use_aws` |  | The AWS region where Kafka is deployed |
| `aws_vpc_id` | `""` | `string` | `use_aws` |  | The ID of the VPC where the Kafka cluster is deployed |
| `aws_enable_cross_region` | `false` | `bool` | `use_aws` |  | Enable VPC Endpoint Services and VPC Endpoints to be in different regions. ***Note: this is current in testing and should not be used yet*** |
| `aws_vpc_endpoint_service_additional_regions` | `[]` | `list(string)` | `aws_enable_cross_region` |  | A list of additional regions for the VPC Endpoint Service when aws_enable_cross_region is enabled. ***Note: this is current in testing and should not be used yet*** |
| `aws_kafka_brokers` | `[]` | `list(object({ id = string, subnet_id = string, endpoints = list(object({ host = string, port = number, ip = string })) }))` | `use_aws` |  | A list of Kafka brokers, which the object shape: `{ id, subnet_id, endpoints: [{ host, port, ip }] }` |
| `use_azure` | `false` | `bool` |  | `use_aws`, `use_gcp` | Set module to create Azure specific resources. ***Note: this is currently disabled*** |
| `use_gcp` | `false` | `bool` |  | `use_aws`, `use_azure` | Set module to create GCP specific resources. ***Note: this is currently disabled*** |

## Usage
Apache Kafka on AWS example
```hcl
module "cluster-linking-apache-kafka-aws-private-link" {
  source = "git::https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private.git"

  name_prefix = "oss-ak"

  use_aws    = true
  aws_region = "us-west-2"
  aws_vpc_id = "vpc-01234567891011120"
  aws_kafka_brokers = [
    {
      id        = "1"
      subnet_id = "subnet-0123456789101112a"
      endpoints = [
        {
          host = "b-1.kafka.acme.com"
          port = 9092
          ip   = "10.0.1.101"
        }
      ]
    },
    {
      id        = "2"
      subnet_id = "subnet-0123456789101112b"
      endpoints = [
        {
          host = "b-2.kafka.acme.com"
          port = 9092
          ip   = "10.0.2.102"
        }
      ]
    },
    {
      id        = "3"
      subnet_id = "subnet-0123456789101112c"
      endpoints = [
        {
          host = "b-3.kafka.acme.com"
          port = 9092
          ip   = "10.0.3.103"
        }
      ]
    }
  ]
  cc_env_id     = "env-012345"
  cc_cluster_id = "lkc-012345"
}
```

AWS MSK example
```hcl
module "cluster-linking-aws-msk-private-link" {
  source = "git::https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private.git"

  name_prefix = "msk"

  use_aws    = true
  aws_region = "us-west-2"
  aws_vpc_id = "vpc-01234567891011120"
  aws_kafka_brokers = [
    {
      id        = "1"
      subnet_id = "subnet-0123456789101112a"
      endpoints = [
        {
          host = "b-1.mskcluster.a1b2c3.c3.kafka.us-west-2.amazonaws.com"
          port = 9096
          ip   = "10.0.1.101"
        }
      ]
    },
    {
      id        = "2"
      subnet_id = "subnet-0123456789101112b"
      endpoints = [
        {
          host = "b-2.mskcluster.a1b2c3.c3.kafka.us-west-2.amazonaws.com"
          port = 9096
          ip   = "10.0.2.102"
        }
      ]
    },
    {
      id        = "3"
      subnet_id = "subnet-0123456789101112c"
      endpoints = [
        {
          host = "b-3.mskcluster.a1b2c3.c3.kafka.us-west-2.amazonaws.com"
          port = 9096
          ip   = "10.0.3.103"
        }
      ]
    }
  ]
  cc_env_id     = "env-012345"
  cc_cluster_id = "lkc-012345"
}
```

## Important caveats/gotcha's

## AWS
### VPC Endpoint Service and VPC Endpoint connection auto-rejection

Confluent Egress Access Points for AWS get *staged for deletion* when you destroy them. This means that Terraform marks the dependency as destroyed, allowing dependencies like VPC Endpoint Services to be ready for destruction in the eyes of Terraform's dependency graph. This will fail, however, because you cannot destroy a VPC Endpoint Service with existing VPC Endpoint connections. In order to get around this, this module uses a destroy-time provisioner to reject the connection for each VPC Endpoint Service, allowing it to gracefully destroy the services asynchronously. This destroy-time provisioner looks like the following: 

```hcl
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
```

This raises some inportant things to be aware of:
* This creates a dependency for whatever machine executes the Terraform to have an instance of the AWS CLI available to it
* This assumes that the machine that executes the AWS CLI command uses [credential files](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)

Since there is no elegant way to conditionally execute this provisioner with a user-supplied flag, it's being kept. If there's any key issues with using this in the module, please open an issue so it can be address and considered for removal. 
