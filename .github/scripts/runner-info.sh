#!/bin/sh
# Writes the facts that make a CI result a separate `platform` key: runner image, CPU count, kernel, tool versions.
#   sh .github/scripts/runner-info.sh <out.json>
# No secrets, no user names, no addresses. Run on a GitHub-hosted runner (Linux or macOS).
set -eu
out=${1:?usage: runner-info.sh <out.json>}
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)
docker_ncpu=null
if command -v docker >/dev/null 2>&1; then
  n=$(docker info --format '{{.NCPU}}' 2>/dev/null || true)
  case "$n" in ''|*[!0-9]*) ;; *) docker_ncpu=$n ;; esac
fi
node_v=$(command -v node >/dev/null 2>&1 && node --version || echo none)
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
{
  printf '{\n'
  printf ' "schema": "fw.ci-runner/1",\n'
  printf ' "workflow": %s,\n' "$(q "${GITHUB_WORKFLOW:-local}")"
  printf ' "job": %s,\n' "$(q "${GITHUB_JOB:-local}")"
  printf ' "runId": %s,\n' "$(q "${GITHUB_RUN_ID:-0}")"
  printf ' "runAttempt": %s,\n' "$(q "${GITHUB_RUN_ATTEMPT:-0}")"
  printf ' "sha": %s,\n' "$(q "${GITHUB_SHA:-none}")"
  printf ' "ref": %s,\n' "$(q "${GITHUB_REF:-none}")"
  printf ' "runnerOS": %s,\n' "$(q "${RUNNER_OS:-$(uname -s)}")"
  printf ' "runnerArch": %s,\n' "$(q "${RUNNER_ARCH:-$(uname -m)}")"
  printf ' "imageOS": %s,\n' "$(q "${ImageOS:-unknown}")"
  printf ' "imageVersion": %s,\n' "$(q "${ImageVersion:-unknown}")"
  printf ' "kernel": %s,\n' "$(q "$(uname -r)")"
  printf ' "cpus": %s,\n' "$cpus"
  printf ' "dockerNcpu": %s,\n' "$docker_ncpu"
  printf ' "node": %s\n' "$(q "$node_v")"
  printf '}\n'
} > "$out"
cat "$out"
