# Confluent Cloud Terraform module for Private Linking external Kafka clusters

Confluent Cloud Cluster Linking provides byte-to-byte replication between two Apache Kafka clusters. This Terraform module configures private networking using Private Link (or the equivalent) so Cluster Linking can reach an external Kafka cluster to perform replication.

## Modules in this repo

There is **one entry point per cloud**, each with its own interface and documentation — pick the one matching your source Kafka's cloud:

| Cloud | Entry point (`source`) | Documentation |
|-------|------------------------|---------------|
| AWS   | repository root — `git::https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private.git`               | [`modules/aws/README.md`](./modules/aws/README.md)     |
| Azure | `modules/azure` — `git::https://github.com/confluentinc/cc-terraform-module-clusterlinking-outbound-private.git//modules/azure` | [`modules/azure/README.md`](./modules/azure/README.md) |

Each module's README documents its required providers, inputs/outputs, usage examples, and cloud-specific gotchas. The AWS module is the repository **root** module (consumed with no `//` subpath); Azure is a nested entry module.
