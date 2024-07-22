variable "name" {
  type        = string
  description = "name of the Kong application in Cloud Foundry"
}

variable "space" {
  type        = string
  description = "the Cloud Foundry space in which to deploy"
}

variable "instances" {
  type        = number
  description = "the number of instances of the Kong application to run (default: 2)"
  default     = 2
}

variable "memory" {
  type        = string
  description = "the memory limit in megabytes for each Kong application instance (default: 256)"
  default     = "256"
}

variable "kong_version" {
  type        = string
  description = "Kong version to be deployed; see https://docs.konghq.com/gateway/latest/support-policy/#supported-versions"
  default     = "3.7.1"
}

variable "kong_plugins" {
  type        = string
  description = "Kong plugins to be included; see https://docs.konghq.com/gateway/3.7.x/reference/configuration/#plugins and https://docs.konghq.com/hub/?tier=free"
  default     = "bundled"
}

variable "kong_config" {
  type        = string
  description = "Kong configuration in YAML; see https://github.com/Kong/kong/blob/master/kong.conf.default"
}
