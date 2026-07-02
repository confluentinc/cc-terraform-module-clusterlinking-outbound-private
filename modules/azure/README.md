# Azure — Cluster Linking outbound Private Link module

Azure submodule of
[`cc-terraform-module-clusterlinking-outbound-private`](https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private).
It provisions the **Azure** side of a Confluent Cloud Cluster Linking **outbound (egress)
Private Link** path to a self-managed Kafka cluster: per-broker Azure Load Balancers +
Private Link Services in front of the brokers, plus the Confluent Cloud egress gateway,
access points, and DNS records that connect to them.

This is the Azure counterpart to the AWS support at the repository root (see the top-level
README). Each cloud is a standalone entry module, so consumers configure only the provider
for the cloud they use — an Azure consumer references `//modules/azure` and never needs the
`aws` provider.

## How it works

```
broker VM NIC ──► LB backend pool ──► Azure LB ──► Private Link Service     (this module, customer side)
                                                          ▲
                                                          │ join via pls_resource_ids
Confluent access point ──► DNS record ────────────────────┘                 (this module, Confluent Cloud side)
```

Confluent Cloud initiates the connection **outbound** to your self-managed Kafka over the
Private Link Service. The actual cluster link (`confluent kafka link create`) is created
separately once this path is up.

## Requirements

| Provider | Version |
|---|---|
| `azurerm` | `~> 4.0` |
| `confluent` | `~> 2.0` |

## Prerequisites

This module provisions only the **Private Link plumbing** between an existing self-managed
Kafka cluster and Confluent Cloud. It does **not** create the Kafka clusters, VMs, VNet, or
resource group on either side. Before applying, the following must already exist.

### On the self-managed Kafka (Azure) side
- A **running Kafka cluster in an Azure VNet** — broker VMs already provisioned, each with a
  network interface that has a **single primary IP configuration** in the broker subnet.
- An existing **resource group, VNet, and broker subnet** (passed as `azure_resource_group_name`,
  `azure_vnet_name`, `azure_broker_subnet_id`).
- **Free address space in the VNet** for the dedicated PLS NAT subnet this module creates
  (`azure_nat_subnet_cidr`).
- Each broker **advertises a stable hostname** (`advertised.listeners`) matching the `host`
  value for that broker. The brokers must be able to **resolve their own advertised hostnames**
  (e.g. via real DNS) — otherwise inter-broker replication and clients break.
- A **reachable listener on the configured port** (`port`, default `9092`). The load balancer
  health probe and rule target this port. Security protocol/auth (PLAINTEXT, SASL, SSL) is your
  broker's listener choice and is configured later in the cluster-link config — this module is
  protocol-agnostic at the network layer.
- The broker **NSG allows inbound** to the broker port from the NAT subnet (which sits inside
  the VNet).
- In **turnkey mode** (`create_load_balancers = true`, the default), the broker NICs must **not
  already be behind another load balancer with a rule on the same port + protocol** — Azure
  forbids a NIC in two same-type LBs on the same backend port. If your brokers already sit
  behind a load balancer, use **bring-your-own-LB** mode instead (see below).

### On the Confluent Cloud side
- A **Confluent Cloud environment** and a **target cluster** that supports egress Private Link
  (`cc_env_id`, `cc_cluster_id`).
- Confluent Cloud cloud API key/secret for the `confluent` provider
  (`CONFLUENT_CLOUD_API_KEY` / `CONFLUENT_CLOUD_API_SECRET`).

### Out of scope (handled separately)
Creating the brokers/VMs/VNet/RG/subnet; configuring broker listeners; creating the **cluster
link and mirror topics** (a post-apply step via the Confluent CLI / `kafka-cluster-links` tooling).

## Usage

```hcl
provider "azurerm" {
  features {}
  subscription_id = "<subscription-with-broker-vms>"
}

provider "confluent" {
  cloud_api_key    = var.cc_api_key
  cloud_api_secret = var.cc_api_secret
}

module "cluster-linking-azure-private-link" {
  source = "git::https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private.git//modules/azure"

  name_prefix = "osk"

  azure_region              = "centralus"
  azure_resource_group_name = "my-kafka-rg"     # existing RG with the broker VMs
  azure_vnet_name           = "my-kafka-vnet"   # existing VNet
  azure_broker_subnet_id    = "/subscriptions/.../subnets/brokers" # LB frontend subnet
  azure_nat_subnet_cidr     = "10.0.250.0/24"   # NEW subnet this module creates for the PLS NAT

  azure_kafka_brokers = [
    { id = "1", host = "broker-1.mykafka.example.com", nic_name = "broker-1-vm-nic", port = 9092 },
    { id = "2", host = "broker-2.mykafka.example.com", nic_name = "broker-2-vm-nic", port = 9092 },
    { id = "3", host = "broker-3.mykafka.example.com", nic_name = "broker-3-vm-nic", port = 9092 },
  ]

  cc_env_id     = "env-012345"
  cc_cluster_id = "lkc-012345"
}
```

### Bring-your-own load balancer

By default (`create_load_balancers = true`) the module creates the per-broker LB and wires
each broker VM's NIC into the backend pool (turnkey). If you already manage your own load
balancers, set `create_load_balancers = false` and supply the frontend IP configuration IDs:

```hcl
  create_load_balancers = false
  azure_lb_frontend_ip_configuration_ids = {
    "1" = "/subscriptions/.../loadBalancers/lb-1/frontendIPConfigurations/frontend-1"
    "2" = "/subscriptions/.../loadBalancers/lb-2/frontendIPConfigurations/frontend-2"
    "3" = "/subscriptions/.../loadBalancers/lb-3/frontendIPConfigurations/frontend-3"
  }
```

### Reusing an existing egress gateway

Confluent Cloud allows only **one** `AzureEgressPrivateLink` gateway per environment per
region. To attach to an existing one instead of creating a new gateway:

```hcl
  cc_use_existing_egress_gateway = true
  cc_egress_gateway_id           = "gw-xxxxxx"
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | `string` | `""` | Prefix for all resource names. |
| `cc_env_id` | `string` | — | Confluent Cloud environment ID (`env-...`). |
| `cc_cluster_id` | `string` | — | Target Confluent cluster ID (`lkc-...`). |
| `azure_region` | `string` | `""` | Azure region for the gateway and networking. |
| `azure_resource_group_name` | `string` | `""` | Existing resource group with the broker VMs. |
| `azure_vnet_name` | `string` | `""` | Existing VNet with the broker VMs. |
| `azure_broker_subnet_id` | `string` | `""` | Subnet ID used as the LB frontend subnet. |
| `azure_nat_subnet_cidr` | `string` | `""` | CIDR for the dedicated PLS NAT subnet this module creates. |
| `azure_kafka_brokers` | `list(object)` | `[]` | `{ id, host, nic_name?, port? }` per broker. `host` must match `advertised.listeners`. `nic_name` required when `create_load_balancers = true`. |
| `create_load_balancers` | `bool` | `true` | Turnkey (module owns the LBs) vs bring-your-own-LB. |
| `azure_lb_frontend_ip_configuration_ids` | `map(string)` | `{}` | Broker id → frontend IP config ID. Required when `create_load_balancers = false`. |
| `cc_use_existing_egress_gateway` | `bool` | `false` | Reuse an existing egress gateway instead of creating one. |
| `cc_egress_gateway_id` | `string` | `""` | Existing gateway ID (`gw-...`) when reusing. |

## Outputs

| Name | Description |
|---|---|
| `pls_resource_ids` | Private Link Service resource IDs per broker. |
| `gateway_id` | Confluent egress gateway ID. |
| `access_point_ids` | Confluent access point IDs per broker. |
| `dns_record_ids` | Confluent DNS record IDs per broker. |

## Testing

```sh
cd modules/azure
terraform init
terraform test    # mock-provider tests, creates no real resources
```

## Teardown note

Deleting a Confluent access point leaves the Azure PLS private-endpoint connection lingering
in an `Approved` state for several minutes, which makes `terraform destroy` fail on the PLS.
If you hit this, reject the connection manually and retry:

```sh
az network private-link-service connection delete --name <conn> --service-name <pls> -g <rg>
```
