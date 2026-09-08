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
  CG_SKIP_APPLY=1         Reuse an existing deployment and only run checks.
  CG_TIMEOUT_SECONDS=900  App health polling timeout. Default: 900.
  CG_S3_PLAN=basic-sandbox  S3 service plan. Default: basic-sandbox.

The generated var-file forces one instance per app and 896 MB total app memory
(256 MB Kong + 128 MB each for auth/meta/rest/storage/studio) to fit the default
1 GB cloud.gov sandbox quota. Terraform state and provider metadata are isolated
under .cloudgov-smoke.tfstate and .cloudgov-smoke.terraform.
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
var_file="$repo_root/.cloudgov-smoke.tfvars"
state_file="$repo_root/.cloudgov-smoke.tfstate"
data_dir="$repo_root/.cloudgov-smoke.terraform"
report_file="$repo_root/.cloudgov-smoke-report.txt"
keep_deployment="${CG_KEEP_DEPLOYMENT:-0}"
skip_apply="${CG_SKIP_APPLY:-0}"
timeout_seconds="${CG_TIMEOUT_SECONDS:-900}"
s3_plan="${CG_S3_PLAN:-basic-sandbox}"

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

if ! cf marketplace -s s3 2>/dev/null | grep -Eq "(^|[[:space:],])${s3_plan}([[:space:],]|$)"; then
  echo "ERROR: S3 service plan '$s3_plan' is not visible in $cf_org / $cf_space." >&2
  echo "Run 'cf marketplace -s s3' to list available plans, then set CG_S3_PLAN=<plan>." >&2
  exit 1
fi

cat > "$var_file" <<VARS
cf_org_name   = "$cf_org"
cf_space_name = "$cf_space"
database_plan = "micro-psql"
s3_plan_name  = "$s3_plan"

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

cleanup() {
  local status=$?
  if [[ "$skip_apply" != "1" && "$keep_deployment" != "1" ]]; then
    echo "Destroying smoke-test deployment..."
    terraform -chdir="$repo_root" destroy -auto-approve -var-file="$var_file" || true
  elif [[ "$keep_deployment" == "1" ]]; then
    echo "Keeping smoke-test deployment because CG_KEEP_DEPLOYMENT=1."
    echo "Temporary var-file: $var_file"
    echo "Temporary state: $state_file"
  fi
  exit "$status"
}
trap cleanup EXIT

record() {
  printf '%s\n' "$*" | tee -a "$report_file"
}

: > "$report_file"
record "cloud.gov Supabase smoke test"
record "Org: $cf_org"
record "Space: $cf_space"
record "S3 plan: $s3_plan"
record "Sandbox-safe app memory: 896 MB total"
record ""

if [[ "$skip_apply" != "1" ]]; then
  record "Running terraform init..."
  terraform -chdir="$repo_root" init -reconfigure -backend-config="path=$state_file"

  record "Running terraform apply..."
  terraform -chdir="$repo_root" apply -auto-approve -var-file="$var_file"
else
  record "Skipping terraform apply because CG_SKIP_APPLY=1."
fi

apps=(
  supabase-api
  supabase-auth
  supabase-meta
  supabase-rest
  supabase-storage
  supabase-studio
)

deadline=$((SECONDS + timeout_seconds))
for app in "${apps[@]}"; do
  record "Waiting for $app to report STARTED..."
  while true; do
    app_status="$(cf app "$app" 2>&1 || true)"
    if grep -Eq '^requested state:[[:space:]]+started' <<<"$app_status" && grep -Eq '^instances:[[:space:]]+[1-9][0-9]*/[1-9][0-9]*' <<<"$app_status"; then
      record "PASS app $app STARTED"
      break
    fi

    if (( SECONDS >= deadline )); then
      record "FAIL app $app did not start within ${timeout_seconds}s"
      printf '%s\n' "$app_status" | tee -a "$report_file"
      exit 1
    fi

    sleep 10
  done
done

api_url="$(terraform -chdir="$repo_root" output -raw api_url)"
dashboard_username="$(terraform -chdir="$repo_root" output -raw dashboard_username)"
dashboard_password="$(terraform -chdir="$repo_root" output -raw dashboard_password)"

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
check_http "Kong gateway" "$api_url/" '^(200|301|302|401|404)$'
check_http "Studio through Kong basic-auth" "$api_url/" '^200$' --user "$dashboard_username:$dashboard_password"
check_http "Auth health through Kong" "$api_url/auth/v1/health" '^(200|401|404)$' --header 'apikey: smoke-test'
check_http "REST route through Kong" "$api_url/rest/v1/" '^(200|401|404)$' --header 'apikey: smoke-test'

record ""
record "PASS cloud.gov Supabase smoke test completed"
record "Report: $report_file"
