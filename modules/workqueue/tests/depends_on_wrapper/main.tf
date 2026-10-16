// Copyright 2026 Chainguard, Inc.
// SPDX-License-Identifier: Apache-2.0

// Test fixture: calls the module behind a module-level depends_on on a
// resource that is being created, as callers do.

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.21.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.21.0"
    }
    random = { source = "hashicorp/random" }
    null   = { source = "hashicorp/null" }
  }
}

provider "google" {}

provider "google-beta" {}

variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "regions" {
  type = any
}

variable "concurrent-work" {
  type = number
}

variable "reconciler-service" {
  type = any
}

variable "team" {
  type = string
}

variable "notification_channels" {
  type = list(string)
}

variable "project_number" {
  type    = string
  default = null
}

variable "resource_manager_tags" {
  type    = map(string)
  default = {}
}

resource "terraform_data" "dependency" {
  input = var.name
}

module "workqueue" {
  source = "../.."

  depends_on = [terraform_data.dependency]

  project_id            = var.project_id
  name                  = var.name
  regions               = var.regions
  concurrent-work       = var.concurrent-work
  reconciler-service    = var.reconciler-service
  team                  = var.team
  notification_channels = var.notification_channels

  project_number        = var.project_number
  resource_manager_tags = var.resource_manager_tags
}

output "tag_binding_parents" {
  value = module.workqueue.tag_binding_parents
}
