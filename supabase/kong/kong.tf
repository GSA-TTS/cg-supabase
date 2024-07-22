data "external" "kongzip" {
  program     = ["/bin/sh", "prepare-kong.sh"]
  working_dir = path.module
  query = {
    kong_version = var.kong_version
    kong_config  = var.kong_config
  }
}

resource "cloudfoundry_app" "kong" {
  name             = var.name
  space            = var.space
  buildpacks       = ["https://github.com/cloudfoundry/apt-buildpack", "binary_buildpack"]
  path             = "${path.module}/${data.external.kongzip.result.path}"
  source_code_hash = filesha256("${path.module}/${data.external.kongzip.result.path}")
  timeout          = 180
  memory           = var.memory
  disk_quota       = 256
  instances        = var.instances
  strategy         = "rolling"
  command          = "./run.sh"
  environment = {
    KONG_PLUGINS = var.kong_plugins

    # TODO: Make these variable?
    KONG_NGINX_PROXY_PROXY_BUFFER_SIZE = "160k"
    KONG_NGINX_PROXY_PROXY_BUFFERS     = "64 160k"
  }
}
