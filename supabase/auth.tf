locals {
  # TODO: Parameterize which image to use, with this as the default
  auth_image             = "supabase/gotrue"
  # auth_image             = "ghcr.io/gsa-tts/cg-supabase/auth"
  auth_image_tag         = "v2.151.0"
  # auth_image_tag         = "scanned"
  auth_app_name          = "supabase-auth"
  auth_url               = "https://${cloudfoundry_route.supabase-auth.endpoint}:61443"
  auth_connection_string = "${cloudfoundry_service_key.auth.credentials.uri}?sslmode=require"
}

resource "cloudfoundry_route" "supabase-auth" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-auth${local.slug}"
}

resource "cloudfoundry_service_key" "auth" {
  name             = "auth"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "auth" {
  name = "${local.auth_image}:${local.auth_image_tag}"
}

# resource "cloudfoundry_app" "supabase-auth" {
#   name         = local.auth_app_name
#   space        = data.cloudfoundry_space.apps.id
#   docker_image = "${local.auth_image}@${data.docker_registry_image.auth.sha256_digest}"
#   timeout      = 180
#   memory       = var.auth_memory
#   disk_quota   = 256
#   instances    = var.auth_instances
#   strategy     = "rolling"
#   routes {
#     route = cloudfoundry_route.supabase-auth.id
#   }

#   environment = {
#     # TODO: Move the secrets into a bound UPSI, and parse them out of
#     # VCAP_SERVICES with jq at startup

#     GOTRUE_API_HOST = "0.0.0.0"
#     GOTRUE_API_PORT = "8080"
#     API_EXTERNAL_URL = "${local.api_url}"

#     GOTRUE_DB_DRIVER = "postgres"
#     # GOTRUE_DB_DATABASE_URL = postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}

#     # GOTRUE_SITE_URL = ${SITE_URL}
#     # GOTRUE_URI_ALLOW_LIST = ${ADDITIONAL_REDIRECT_URLS}
#     # GOTRUE_DISABLE_SIGNUP = ${DISABLE_SIGNUP}

#     # GOTRUE_JWT_ADMIN_ROLES = service_role
#     # GOTRUE_JWT_AUD = authenticated
#     # GOTRUE_JWT_DEFAULT_GROUP_NAME = authenticated
#     # GOTRUE_JWT_EXP = ${JWT_EXPIRY}
#     # GOTRUE_JWT_SECRET = ${JWT_SECRET}

#     # GOTRUE_EXTERNAL_EMAIL_ENABLED = ${ENABLE_EMAIL_SIGNUP}
#     # GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED = ${ENABLE_ANONYMOUS_USERS}
#     # GOTRUE_MAILER_AUTOCONFIRM = ${ENABLE_EMAIL_AUTOCONFIRM}
#     # # GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED = true
#     # # GOTRUE_SMTP_MAX_FREQUENCY = 1s
#     # GOTRUE_SMTP_ADMIN_EMAIL = ${SMTP_ADMIN_EMAIL}
#     # GOTRUE_SMTP_HOST = ${SMTP_HOST}
#     # GOTRUE_SMTP_PORT = ${SMTP_PORT}
#     # GOTRUE_SMTP_USER = ${SMTP_USER}
#     # GOTRUE_SMTP_PASS = ${SMTP_PASS}
#     # GOTRUE_SMTP_SENDER_NAME = ${SMTP_SENDER_NAME}
#     # GOTRUE_MAILER_URLPATHS_INVITE = ${MAILER_URLPATHS_INVITE}
#     # GOTRUE_MAILER_URLPATHS_CONFIRMATION = ${MAILER_URLPATHS_CONFIRMATION}
#     # GOTRUE_MAILER_URLPATHS_RECOVERY = ${MAILER_URLPATHS_RECOVERY}
#     # GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE = ${MAILER_URLPATHS_EMAIL_CHANGE}

#     # GOTRUE_EXTERNAL_PHONE_ENABLED = ${ENABLE_PHONE_SIGNUP}
#     # GOTRUE_SMS_AUTOCONFIRM = ${ENABLE_PHONE_AUTOCONFIRM}

#     # # Uncomment to enable custom access token hook. You'll need to create a public.custom_access_token_hook function and grant necessary permissions.
#     # # See: https://supabase.com/docs/guides/auth/auth-hooks#hook-custom-access-token for details
#     # # GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_ENABLED = "true"
#     # # GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI = "pg-functions://postgres/public/custom_access_token_hook"

#     # # GOTRUE_HOOK_MFA_VERIFICATION_ATTEMPT_ENABLED ="true"
#     # # GOTRUE_HOOK_MFA_VERIFICATION_ATTEMPT_URI = "pg-functions://postgres/public/mfa_verification_attempt"

#     # # GOTRUE_HOOK_PASSWORD_VERIFICATION_ATTEMPT_ENABLED = "true"
#     # # GOTRUE_HOOK_PASSWORD_VERIFICATION_ATTEMPT_URI = "pg-functions://postgres/public/password_verification_attempt"
#   }
# }
