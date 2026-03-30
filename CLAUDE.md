# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Reconciler Architecture

Reconcilers follow a **Watch-Compare-Act** loop: observe current state, compute the delta against desired state, and take idempotent actions to close the gap. They are **level-based** — the workqueue holds keys, not events. Multiple events for the same resource collapse into a single reconciliation of its current state. Built on the [DriftlessAF](https://github.com/driftlessaf/go-driftlessaf) framework. See [README.md](./README.md) for the full architecture and Go implementation examples.

## Module Catalog

Before creating new reconciler infrastructure, consult [MODULES.md](./MODULES.md) for existing modules. The `regional-go-reconciler` module is the default starting point for any new reconciler. Use the meta-reconciler modules (github-metareconciler, github-metapathreconciler, linear-metareconciler) when standard event wiring is needed.

## Related Catalogs

- [terraform/MODULES.md](../../terraform/MODULES.md) — AWS, GCP, Kubernetes, and Chainguard private infrastructure modules
- [public/terraform-infra-common/MODULES.md](../terraform-infra-common/MODULES.md) — Cloud Run services, event-driven architecture, networking, observability, databases

## Build & Test Commands
- Run tests: `go test -race -timeout=5m ./...`
- Run single test: `go test -race -timeout=5m -run TestName ./path/to/package`
- Validate Terraform: `terraform init && terraform validate`
- Format Terraform: `terraform fmt`
