#!/bin/sh

# Exit if any step fails
set -e

popdir=$(pwd)
eval "$(jq -r '@sh 
       "KONG_VERSION=\(.kong_version) 
        KONG_CONFIG=\(.kong_config)
       "')"

# Portable mktemp construct so this will work everywhere
# https://unix.stackexchange.com/a/84980
tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')

# Grab a copy of the zip file for the specified ref
# https://github.com/GSA-TTS/cg-logshipper/archive/refs/heads/main.zip
# curl -s -L https://github.com/GSA-TTS/cg-logshipper/archive/"${GITREF}".zip --output "${tmpdir}/logshipper-dist.zip"
cp "${popdir}"/app/* "${tmpdir}"

# Replace the KONG_VERSION
KONG_VERSION=${KONG_VERSION} envsubst < "${popdir}"/app/apt.yml > "${tmpdir}/apt.yml"

# Put the config in place
echo "${KONG_CONFIG}" > "${tmpdir}/kong-config.yml"

# To deterministically create the same .zip file every time, we want to set the
# same timestamp no matter when the files were actually created. So we set
# them to the time of the last commit. We do this in a subshell so that it won't
# be fatal if (for some reason) this is run outside of a git checkout. See blog
# post about this topic and solution here:
# https://zerostride.medium.com/building-deterministic-zip-files-with-built-in-commands-741275116a19
cd "${popdir}"
git config --global --add safe.directory /github/workspace && \
  find "${tmpdir}" -exec touch -t "$(git ls-files -z "${popdir}" | \
  xargs -0 -I{} -- git log -1 --date=format:"%Y%m%d%H%M" --format="%ad" {} | \
  sort -r | head -n 1)" {} + && \
  git config --global --unset safe.directory /github/workspace

# Make the app package
cd "${tmpdir}" && zip -r -o -X "${popdir}/app.zip" ./ > /dev/null

# Tell Terraform where to find it
cat << EOF
{ "path": "app.zip" }
EOF
