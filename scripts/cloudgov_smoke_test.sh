#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/cloudgov_smoke_test.sh

Deploys this Terraform root module to a cloud.gov space, verifies that the apps
start and key public endpoints respond, prints a PASS/FAIL report, and destroys
the deployment by default.

Prerequisites:
  - terraform, cf, and curl in PATH
  - cloud.gov access to the target org/space
  - either run `cf login -a https://api.fr.cloud.gov --sso` first, or set
    TF_VAR_cf_client_id/TF_VAR_cf_client_secret or TF_VAR_cf_user/TF_VAR_cf_password

Configuration:
  CG_ORG=<org>            Target cloud.gov org. Defaults to current `cf target` org.
  CG_SPACE=<space>        Target cloud.gov space. Defaults to current `cf target` space.
  CG_KEEP_DEPLOYMENT=1    Keep resources after the test. Default destroys them.
  CG_KEEP_ON_FAILURE=1    Keep resources after a failed test for manual inspection.
  CG_SKIP_APPLY=1         Reuse an existing deployment and only run checks.
  CG_TIMEOUT_SECONDS=900       App health polling timeout. Default: 900.
  CG_DATABASE_PLAN=micro-psql  RDS service plan. Default: micro-psql.
  CG_DATABASE_SERVICE_NAME=supabase-db  RDS service name. Default: supabase-db.
  CG_S3_PLAN=basic-sandbox     S3 service plan. Default: basic-sandbox.
  CG_S3_SERVICE_NAME=supabase-private-s3  S3 service name. Default: supabase-private-s3.
  CG_IMAGE_TAG=pr-<branch>     GHCR image tag to deploy. Defaults to current branch tag.
  CG_TF_LOG=DEBUG              Optional Terraform log level. Logs may contain secrets.

The generated var-file forces one instance per app and 896 MB total app memory
(256 MB Kong + 128 MB each for auth/meta/rest/storage/studio) to fit the default
1 GB cloud.gov sandbox quota. Terraform state and provider metadata are isolated
under .cloudgov-smoke.tfstate and .cloudgov-smoke.terraform and are deleted
after successful cleanup.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd terraform
require_cmd cf
require_cmd curl

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
var_file="$repo_root/.cloudgov-smoke.tfvars"
state_file="$repo_root/.cloudgov-smoke.tfstate"
data_dir="$repo_root/.cloudgov-smoke.terraform"
log_dir="$repo_root/.cloudgov-smoke-logs/$run_id"
report_file="$repo_root/.cloudgov-smoke-report.txt"
keep_deployment="${CG_KEEP_DEPLOYMENT:-0}"
keep_on_failure="${CG_KEEP_ON_FAILURE:-0}"
skip_apply="${CG_SKIP_APPLY:-0}"
timeout_seconds="${CG_TIMEOUT_SECONDS:-900}"
s3_plan="${CG_S3_PLAN:-basic-sandbox}"
database_plan="${CG_DATABASE_PLAN:-micro-psql}"
database_service_name="${CG_DATABASE_SERVICE_NAME:-supabase-db}"
s3_service_name="${CG_S3_SERVICE_NAME:-supabase-private-s3}"
default_image_tag="pr-$(git -C "$repo_root" branch --show-current | tr '/_' '--' | tr -cd '[:alnum:].-')"
image_tag="${CG_IMAGE_TAG:-$default_image_tag}"
created_database_service=0
created_s3_service=0
smoke_checks_passed=0

cf_target_field() {
  local label="$1"
  cf target | awk -F': *' -v label="$label" '$1 == label { print $2 }'
}

cf_org="${CG_ORG:-$(cf_target_field org)}"
cf_space="${CG_SPACE:-$(cf_target_field space)}"

if [[ -z "$cf_org" || -z "$cf_space" ]]; then
  echo "ERROR: set CG_ORG and CG_SPACE, or run cf target against the test org/space." >&2
  exit 1
fi

cf target -o "$cf_org" -s "$cf_space" >/dev/null

if [[ -z "${TF_VAR_cf_client_id:-}" && -z "${TF_VAR_cf_user:-}" && -z "${CF_ACCESS_TOKEN:-}" ]]; then
  cf_token="$(cf oauth-token 2>/dev/null || true)"
  if [[ -z "$cf_token" || "$cf_token" == "bearer" ]]; then
    echo "ERROR: no Terraform CF credentials found and cf oauth-token returned no token." >&2
    echo "Run cf login -a https://api.fr.cloud.gov --sso, or set TF_VAR_cf_client_id/TF_VAR_cf_client_secret." >&2
    exit 1
  fi
  export CF_ACCESS_TOKEN="$cf_token"
fi

export TF_DATA_DIR="$data_dir"
mkdir -p "$log_dir"

if [[ -n "${CG_TF_LOG:-}" ]]; then
  export TF_LOG="$CG_TF_LOG"
  export TF_LOG_PATH="$log_dir/terraform-debug.log"
fi

record() {
  printf '%s\n' "$*" | tee -a "$report_file"
}

: > "$report_file"

if ! cf marketplace -e aws-rds 2>/dev/null | tee "$log_dir/cf-marketplace-aws-rds.txt" | awk 'NR > 1 { print $1 }' | grep -Fxq "$database_plan"; then
  echo "ERROR: RDS service plan '$database_plan' is not visible in $cf_org / $cf_space." >&2
  echo "Run 'cf marketplace -e aws-rds' to list available plans, then set CG_DATABASE_PLAN=<plan>." >&2
  exit 1
fi

if ! cf marketplace -e s3 2>/dev/null | tee "$log_dir/cf-marketplace-s3.txt" | awk 'NR > 1 { print $1 }' | grep -Fxq "$s3_plan"; then
  echo "ERROR: S3 service plan '$s3_plan' is not visible in $cf_org / $cf_space." >&2
  echo "Run 'cf marketplace -e s3' to list available plans, then set CG_S3_PLAN=<plan>." >&2
  exit 1
fi

cf_service_exists() {
  cf service "$1" >/dev/null 2>&1
}

wait_for_service() {
  local service_name="$1"
  local deadline=$((SECONDS + timeout_seconds))
  local service_status

  while true; do
    service_status="$(cf service "$service_name" 2>&1 || true)"
    if grep -Eq 'status:[[:space:]]+create succeeded|create succeeded' <<<"$service_status"; then
      record "PASS service $service_name create succeeded"
      return 0
    fi

    if grep -Eq 'status:[[:space:]]+create failed|create failed' <<<"$service_status"; then
      record "FAIL service $service_name create failed"
      printf '%s\n' "$service_status" | tee -a "$report_file"
      return 1
    fi

    if (( SECONDS >= deadline )); then
      record "FAIL service $service_name did not finish creating within ${timeout_seconds}s"
      printf '%s\n' "$service_status" | tee -a "$report_file"
      return 1
    fi

    sleep 10
  done
}

wait_for_service_delete() {
  local service_name="$1"
  local deadline=$((SECONDS + timeout_seconds))

  while true; do
    if ! cf_service_exists "$service_name"; then
      record "PASS service $service_name deleted"
      return 0
    fi

    if (( SECONDS >= deadline )); then
      record "FAIL service $service_name did not delete within ${timeout_seconds}s"
      return 1
    fi

    sleep 10
  done
}

apps=(
  supabase-api
  supabase-auth
  supabase-meta
  supabase-rest
  supabase-storage
  supabase-studio
)

capture_cmd() {
  local name="$1"
  shift

  record "Capturing $name..."
  "$@" >"$log_dir/$name.txt" 2>&1 || true
}

collect_diagnostics() {
  record ""
  record "Collecting diagnostics in $log_dir..."
  capture_cmd "cf-target" cf target
  capture_cmd "cf-apps" cf apps
  capture_cmd "cf-services" cf services
  capture_cmd "cf-service-$database_service_name" cf service "$database_service_name"
  capture_cmd "cf-service-$s3_service_name" cf service "$s3_service_name"
  capture_cmd "cf-routes" cf routes
  capture_cmd "terraform-state-list" terraform -chdir="$repo_root" state list

  local app
  for app in "${apps[@]}"; do
    capture_cmd "cf-app-$app" cf app "$app"
    capture_cmd "cf-logs-recent-$app" cf logs "$app" --recent
    capture_cmd "cf-events-$app" cf events "$app"
  done

  record "Diagnostics captured under: $log_dir"
}

cleanup() {
  local status=$?
  local cleanup_status=0
  local keep_after_failure=0

  if (( status != 0 )); then
    collect_diagnostics
    if [[ "$keep_on_failure" == "1" ]]; then
      keep_after_failure=1
    fi
  fi

  if [[ "$skip_apply" != "1" && "$keep_deployment" != "1" && "$keep_after_failure" != "1" ]]; then
    echo "Destroying smoke-test deployment..."
    if ! terraform -chdir="$repo_root" destroy -auto-approve -var-file="$var_file" 2>&1 | tee "$log_dir/terraform-destroy.log"; then
      cleanup_status=1
    fi
    if [[ "$created_s3_service" == "1" ]]; then
      if ! cf delete-service "$s3_service_name" -f 2>&1 | tee "$log_dir/cf-delete-service-$s3_service_name.log"; then
        cleanup_status=1
      elif ! wait_for_service_delete "$s3_service_name"; then
        cleanup_status=1
      fi
    fi
    if [[ "$created_database_service" == "1" ]]; then
      if ! cf delete-service "$database_service_name" -f 2>&1 | tee "$log_dir/cf-delete-service-$database_service_name.log"; then
        cleanup_status=1
      elif ! wait_for_service_delete "$database_service_name"; then
        cleanup_status=1
      fi
    fi
  elif [[ "$keep_deployment" == "1" || "$keep_after_failure" == "1" ]]; then
    echo "Keeping smoke-test deployment for manual inspection."
    echo "Temporary var-file: $var_file"
    echo "Temporary state: $state_file"
    echo "WARNING: retained Terraform state contains sensitive credentials."
  fi

  if (( status == 0 && cleanup_status != 0 )); then
    echo "ERROR: smoke checks passed, but cleanup failed. See $log_dir." >&2
    exit "$cleanup_status"
  fi

  if (( status == 0 )) && [[ "$keep_deployment" != "1" ]]; then
    rm -f "$var_file" "$state_file" "$state_file.backup"
    rm -rf "$data_dir"
  fi

  if (( status == 0 && smoke_checks_passed == 1 )); then
    record ""
    record "PASS cloud.gov Supabase smoke test completed"
    record "Report: $report_file"
  fi

  exit "$status"
}
trap cleanup EXIT

if cf_service_exists "$database_service_name"; then
  record "Reusing existing RDS service $database_service_name."
elif [[ "$skip_apply" != "1" ]]; then
  record "Creating RDS service $database_service_name with plan $database_plan using cf CLI..."
  cf create-service aws-rds "$database_plan" "$database_service_name" 2>&1 | tee "$log_dir/cf-create-service-$database_service_name.log"
  created_database_service=1
else
  record "Skipping RDS service creation because CG_SKIP_APPLY=1."
fi
if cf_service_exists "$database_service_name"; then
  wait_for_service "$database_service_name"
fi

if cf_service_exists "$s3_service_name"; then
  record "Reusing existing S3 service $s3_service_name."
elif [[ "$skip_apply" != "1" ]]; then
  record "Creating S3 service $s3_service_name with plan $s3_plan using cf CLI..."
  cf create-service s3 "$s3_plan" "$s3_service_name" 2>&1 | tee "$log_dir/cf-create-service-$s3_service_name.log"
  created_s3_service=1
else
  record "Skipping S3 service creation because CG_SKIP_APPLY=1."
fi
if cf_service_exists "$s3_service_name"; then
  wait_for_service "$s3_service_name"
fi

cat > "$var_file" <<VARS
cf_org_name   = "$cf_org"
cf_space_name = "$cf_space"
database_plan = "$database_plan"
s3_plan_name  = "$s3_plan"
image_tag     = "$image_tag"
database_service_instance_name = "$database_service_name"
s3_service_instance_name       = "$s3_service_name"

api_instances     = 1
api_memory        = "256M"
auth_instances    = 1
auth_memory       = "128M"
meta_instances    = 1
meta_memory       = "128M"
rest_instances    = 1
rest_memory       = "128M"
storage_instances = 1
storage_memory    = "128M"
studio_instances  = 1
studio_memory     = "128M"
VARS

record "cloud.gov Supabase smoke test"
record "Org: $cf_org"
record "Space: $cf_space"
record "RDS service: $database_service_name ($database_plan)"
record "S3 service: $s3_service_name ($s3_plan)"
record "Image tag: $image_tag"
record "Sandbox-safe app memory: 896 MB total"
record ""

if [[ "$skip_apply" != "1" ]]; then
  record "Running terraform init..."
  terraform -chdir="$repo_root" init -reconfigure -backend-config="path=$state_file" 2>&1 | tee "$log_dir/terraform-init.log"

  # Older smoke-test runs let Terraform create backing services. The current
  # smoke test pre-creates them with cf CLI to avoid a provider crash, so remove
  # any stale managed-service resources from this isolated state before apply.
  state_entries="$(terraform -chdir="$repo_root" state list 2>/dev/null || true)"
  for state_address in \
    'module.supabase.module.database[0].cloudfoundry_service_instance.rds' \
    'module.supabase.module.database.cloudfoundry_service_instance.rds' \
    'module.supabase.module.s3-private[0].cloudfoundry_service_instance.bucket' \
    'module.supabase.module.s3-private.cloudfoundry_service_instance.bucket'; do
    if grep -Fxq "$state_address" <<<"$state_entries"; then
      terraform -chdir="$repo_root" state rm "$state_address" >>"$log_dir/terraform-state-rm-managed-services.log" 2>&1
    fi
  done

  record "Running terraform apply..."
  terraform -chdir="$repo_root" apply -auto-approve -var-file="$var_file" 2>&1 | tee "$log_dir/terraform-apply.log"
else
  record "Skipping terraform apply because CG_SKIP_APPLY=1."
fi

deadline=$((SECONDS + timeout_seconds))
for app in "${apps[@]}"; do
  record "Waiting for $app to report STARTED..."
  while true; do
    app_status="$(cf app "$app" 2>&1 || true)"
    if grep -Eq '^requested state:[[:space:]]+started' <<<"$app_status" && grep -Eq '^instances:[[:space:]]+[1-9][0-9]*/[1-9][0-9]*' <<<"$app_status"; then
      record "PASS app $app STARTED"
      break
    fi

    if grep -Eiq 'crashed|crash' <<<"$app_status"; then
      recent_logs="$(cf logs "$app" --recent 2>&1 || true)"
      if grep -Fq 'exec format error' <<<"$recent_logs"; then
        record "FAIL app $app crashed with exec format error. The deployed image likely does not match cloud.gov's amd64 runtime architecture; rebuild and publish the multi-arch image tag."
        printf '%s\n' "$app_status" | tee -a "$report_file"
        printf '%s\n' "$recent_logs" >"$log_dir/cf-logs-recent-$app-exec-format-error.txt"
        exit 1
      fi
      if grep -Fq "scandir './migrations/tenant'" <<<"$recent_logs"; then
        record "FAIL app $app crashed because storage-api could not find ./migrations/tenant. The app must start from /app so relative migration paths resolve."
        printf '%s\n' "$app_status" | tee -a "$report_file"
        printf '%s\n' "$recent_logs" >"$log_dir/cf-logs-recent-$app-missing-storage-migrations.txt"
        exit 1
      fi
    fi

    if (( SECONDS >= deadline )); then
      recent_logs="$(cf logs "$app" --recent 2>&1 || true)"
      record "FAIL app $app did not start within ${timeout_seconds}s"
      if grep -Eq 'Listening on port 8080' <<<"$recent_logs" && grep -Eq 'failed to make TCP connection to .*:3000' <<<"$recent_logs"; then
        record "FAIL app $app is listening on 8080, but Cloud Foundry is health-checking port 3000. Rebuild and publish the scanned image so its Docker metadata exposes port 8080."
      fi
      printf '%s\n' "$app_status" | tee -a "$report_file"
      printf '%s\n' "$recent_logs" >"$log_dir/cf-logs-recent-$app-timeout.txt"
      exit 1
    fi

    sleep 10
  done
done

api_url="$(terraform -chdir="$repo_root" output -raw api_url)"
dashboard_username="$(terraform -chdir="$repo_root" output -raw dashboard_username)"
dashboard_password="$(terraform -chdir="$repo_root" output -raw dashboard_password)"
anon_key="$(terraform -chdir="$repo_root" output -raw anon_key)"

check_http() {
  local label="$1"
  local url="$2"
  local expected_regex="$3"
  shift 3

  local status
  status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@" "$url")"
  if [[ "$status" =~ $expected_regex ]]; then
    record "PASS $label HTTP $status"
  else
    record "FAIL $label HTTP $status (expected $expected_regex)"
    exit 1
  fi
}

record ""
record "Checking public endpoints at $api_url..."
check_http "Kong gateway" "$api_url/" '^401$'
# Studio may redirect unauthenticated browser flows after Kong basic-auth succeeds.
check_http "Studio through Kong basic-auth" "$api_url/" '^(200|301|302|303|307|308)$' --user "$dashboard_username:$dashboard_password"
check_http "Auth health through Kong" "$api_url/auth/v1/health" '^200$' --header "apikey: $anon_key"
check_http "REST route through Kong" "$api_url/rest/v1/" '^(200|300|404)$' --header "apikey: $anon_key" --header "Authorization: Bearer $anon_key"
check_http "Storage status through Kong" "$api_url/storage/v1/status" '^200$'

smoke_checks_passed=1
