variable "namespace" {
  type = string
}

variable "ko_platforms" {
  description = "Platforms for images built by the ko provider."
  type        = list(string)
  default     = ["linux/amd64"]
}

variable "name" {
  type = string
}

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time."
  type        = number
}

variable "batch-size" {
  description = "Optional cap on how much work to launch per dispatcher pass. Defaults to the concurrent work value when unset."
  type        = number
  default     = null
}

variable "reconciler-service" {
  description = "The address of the k8s service to push keys to."
  type        = string
}
