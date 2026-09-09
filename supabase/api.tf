locals {
  api_url = "https://supabase${local.slug}.app.cloud.gov"

  api_username = "supabase"
  api_password = random_password.dashboard_password.result

  api_app_id = module.kong.app_id
  # Upstream Supabase Kong config reference:
  # https://github.com/supabase/supabase/blob/master/docker/volumes/api/kong.yml
  kong_config = <<-EOT
    _format_version: '2.1'
    _transform: true

    ###
    ### Consumers / Users
    ###
    consumers:
      - username: DASHBOARD
      - username: anon
        keyauth_credentials:
          - key: ${local.effective_anon_key}
      - username: service_role
        keyauth_credentials:
          - key: ${local.effective_service_role_key}

    ###
    ### Access Control List
    ###
    acls:
      - consumer: anon
        group: anon
      - consumer: service_role
        group: admin

    ###
    ### Dashboard credentials
    ###
    basicauth_credentials:
      - consumer: DASHBOARD
        username: ${local.api_username}
        password: ${local.api_password}

    ###
    ### API Routes
    ###
    services:
      ## Open Auth routes
      - name: auth-v1-open
        url: ${local.auth_url}/verify
        routes:
          - name: auth-v1-open
            strip_path: true
            paths:
              - /auth/v1/verify
        plugins:
          - name: cors
      - name: auth-v1-open-callback
        url: ${local.auth_url}/callback
        routes:
          - name: auth-v1-open-callback
            strip_path: true
            paths:
              - /auth/v1/callback
        plugins:
          - name: cors
      - name: auth-v1-open-authorize
        url: ${local.auth_url}/authorize
        routes:
          - name: auth-v1-open-authorize
            strip_path: true
            paths:
              - /auth/v1/authorize
        plugins:
          - name: cors

      ## Secure Auth routes
      - name: auth-v1
        _comment: 'GoTrue: /auth/v1/* -> ${local.auth_url}/*'
        url: ${local.auth_url}/
        routes:
          - name: auth-v1-all
            strip_path: true
            paths:
              - /auth/v1/
        plugins:
          - name: cors
          - name: key-auth
            config:
              hide_credentials: false
          - name: acl
            config:
              hide_groups_header: true
              allow:
                - admin
                - anon

      ## Secure REST routes
      - name: rest-v1
        _comment: 'PostgREST: /rest/v1/* -> ${local.rest_url}/*'
        url: ${local.rest_url}/
        routes:
          - name: rest-v1-all
            strip_path: true
            paths:
              - /rest/v1/
        plugins:
          - name: cors
          - name: key-auth
            config:
              hide_credentials: true
          - name: acl
            config:
              hide_groups_header: true
              allow:
                - admin
                - anon

      ## Secure GraphQL routes
      - name: graphql-v1
        _comment: 'PostgREST: /graphql/v1/* -> ${local.rest_url}/rpc/graphql'
        url: ${local.rest_url}/rpc/graphql
        routes:
          - name: graphql-v1-all
            strip_path: true
            paths:
              - /graphql/v1
        plugins:
          - name: cors
          - name: key-auth
            config:
              hide_credentials: true
          - name: request-transformer
            config:
              add:
                headers:
                  - Content-Profile:graphql_public
          - name: acl
            config:
              hide_groups_header: true
              allow:
                - admin
                - anon

      ## Realtime routes — disabled: cloud.gov CF containers lack IPv6 support
      ## and supabase/realtime hardcodes socket_opts: [:inet6] with no env override.
      ## Remove the comment markers below if deploying on a platform with IPv6.
      ## Storage routes: the storage server manages its own auth
      - name: storage-v1
        _comment: 'Storage: /storage/v1/* -> ${local.storage_url}/*'
        url: ${local.storage_url}/
        routes:
          - name: storage-v1-all
            strip_path: true
            paths:
              - /storage/v1/
        plugins:
          - name: cors

      ## Edge Functions routes — not deployed in this Terraform module.
      ## Requires a cloud.gov egress proxy for outbound HTTP requests from user code.
      ## Uncomment and set url to the CF internal route if deploying an edge functions app.
      # - name: functions-v1
      #   url: http://<functions-hostname>.apps.internal:<app-port>/
      #   routes:
      #     - name: functions-v1-all
      #       strip_path: true
      #       paths:
      #         - /functions/v1/
      #   plugins:
      #     - name: cors

      ## Analytics routes — not deployed in this Terraform module.
      ## Uncomment and set url to the CF internal route if deploying an analytics app.
      # - name: analytics-v1
      #   url: http://<analytics-hostname>.apps.internal:<app-port>/
      #   routes:
      #     - name: analytics-v1-all
      #       strip_path: true
      #       paths:
      #         - /analytics/v1/

      ## Secure Database routes
      - name: meta
        _comment: 'pg-meta: /pg/* -> ${local.meta_url}/*'
        url: ${local.meta_url}/
        routes:
          - name: meta-all
            strip_path: true
            paths:
              - /pg/
        plugins:
          - name: key-auth
            config:
              hide_credentials: false
          - name: acl
            config:
              hide_groups_header: true
              allow:
                - admin

      ## Protected Dashboard - catch all remaining routes
      - name: dashboard
        _comment: 'Studio: /* -> ${local.studio_url}/*'
        url: ${local.studio_url}/
        routes:
          - name: dashboard-all
            strip_path: true
            paths:
              - /
        plugins:
          - name: cors
          - name: basic-auth
            config:
              hide_credentials: true
    EOT

}

module "kong" {
  source     = "./kong"
  name       = local.api_app_name
  org_name   = local.cf_org_name
  space_name = local.cf_space_name
  instances  = var.api_instances
  memory     = var.api_memory

  kong_version = "3.7.1"
  kong_config  = local.kong_config
  kong_plugins = "request-transformer,cors,key-auth,acl,basic-auth"
}

# This is the main URL!
resource "cloudfoundry_route" "supabase-api" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.public.id
  host   = "supabase${local.slug}"
  destinations = [
    {
      app_id = module.kong.app_id
    }
  ]
}

resource "cloudfoundry_network_policy" "api-backends" {
  policies = [
    {
      source_app      = local.api_app_id
      destination_app = cloudfoundry_app.supabase-auth.id
      port            = "61443"
    },
    {
      source_app      = local.api_app_id
      destination_app = cloudfoundry_app.supabase-meta.id
      port            = "61443"
    },
    {
      source_app      = local.api_app_id
      destination_app = cloudfoundry_app.supabase-rest.id
      port            = "61443"
    },
    {
      source_app      = local.api_app_id
      destination_app = cloudfoundry_app.supabase-storage.id
      port            = "61443"
    },
    {
      source_app      = local.api_app_id
      destination_app = cloudfoundry_app.supabase-studio.id
      port            = "61443"
    }
  ]
}

# Auto-generated dashboard password for Kong basic-auth
resource "random_password" "dashboard_password" {
  length  = 24
  special = false
}