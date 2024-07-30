locals {
  api_url = "https://${cloudfoundry_route.supabase-api.endpoint}"

  # TODO: Generate these; using static strings to match the docker-compose
  # case until everything's working.
  api_username = "supabase"
  api_password = "this_password_is_insecure_and_should_be_updated"

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
          - key: ${var.anon_key}
      - username: service_role
        keyauth_credentials:
          - key: ${var.service_role_key}

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

      ## Secure Realtime routes
      - name: realtime-v1-ws
        _comment: 'Realtime: /realtime/v1/* -> ws://realtime:4000/socket/*'
        url: http://realtime-dev.supabase-realtime:4000/socket
        protocol: ws
        routes:
          - name: realtime-v1-ws
            strip_path: true
            paths:
              - /realtime/v1/
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
      - name: realtime-v1-rest
        _comment: 'Realtime: /realtime/v1/* -> ws://realtime:4000/socket/*'
        url: http://realtime-dev.supabase-realtime:4000/api
        protocol: http
        routes:
          - name: realtime-v1-rest
            strip_path: true
            paths:
              - /realtime/v1/api
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

      ## Edge Functions routes
      - name: functions-v1
        _comment: 'Edge Functions: /functions/v1/* -> http://functions:9000/*'
        url: http://functions:9000/
        routes:
          - name: functions-v1-all
            strip_path: true
            paths:
              - /functions/v1/
        plugins:
          - name: cors

      ## Analytics routes
      - name: analytics-v1
        _comment: 'Analytics: /analytics/v1/* -> http://logflare:4000/*'
        url: http://analytics:4000/
        routes:
          - name: analytics-v1-all
            strip_path: true
            paths:
              - /analytics/v1/

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
  source    = "./kong"
  name      = local.api_app_name
  space     = data.cloudfoundry_space.space.id
  instances = var.api_instances
  memory    = var.api_memory

  kong_version = "3.7.1"
  kong_config  = local.kong_config
  kong_plugins = "request-transformer,cors,key-auth,acl,basic-auth"
}

# This is the main URL!
resource "cloudfoundry_route" "supabase-api" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.public.id
  hostname = "supabase${local.slug}"
  target {
    app = module.kong.app_id
  }
}

resource "cloudfoundry_network_policy" "api-backends" {
  # policy {
  #   source_app      = local.api_app_id
  #   destination_app = cloudfoundry_app.supabase-auth.id
  #   port            = "61443"
  # }
  policy {
    source_app      = local.api_app_id
    destination_app = cloudfoundry_app.supabase-meta.id
    port            = "61443"
  }
  policy {
    source_app      = local.api_app_id
    destination_app = cloudfoundry_app.supabase-rest.id
    port            = "61443"
  }
  policy {
    source_app      = local.api_app_id
    destination_app = cloudfoundry_app.supabase-storage.id
    port            = "61443"
  }
  policy {
    source_app      = local.api_app_id
    destination_app = cloudfoundry_app.supabase-studio.id
    port            = "61443"
  }
}  