#!/bin/sh
# The steps of the CircleCI pilot jobs (.circleci/config.yml), one place, each timed with scripts/span.sh into
# /tmp/fw/spans.jsonl (the .fw-console/timings.jsonl format). Glue only: no decision. The steps are ports of the GitHub
# twins (.github/workflows/premise-tests.yml, webkit-sim.yml, .github/actions/{setup-pnpm,gate-engine}).
#   sh .circleci/job.sh <step> [args]
#   steps: since <name> | toolchain | install <filters> | browser | test | verdict
#          sim-prepare | sim-boot | sim-run | sim-delete | finish
# Env (set by the job): FW_CI_JOB, FW_CI_CLASS, FW_CI_ENGINE (engine jobs), HS_VERSION and HS_SHA256 (chromium).
set -eu
cd "$(dirname "$0")/.."
fw=/tmp/fw
mkdir -p "$fw/artifacts" "$fw/ws"
export FW_TIMINGS_FILE=$fw/spans.jsonl
export RUNNER_TEMP=$fw
export PATH="$HOME/.fw-node/bin:$PATH"
. scripts/span.sh
tool="circleci/${FW_CI_JOB:-unknown}"
self=$PWD/.circleci/job.sh
# T <step> <cmd...>: time the command, run by a fresh `sh job.sh run` so that set -e holds inside it (errexit is off inside the
# condition of the `if` in span, which would let a failed command in a function go unnoticed).
T() { _step=$1; shift; span "$tool" "$_step" sh "$self" run "$@"; }

# A span for a step CircleCI runs itself: from the time the `mark` command saved to now.
since() {
  s=$(( $(cat "$fw/mark") / 1000000 ))
  _span_now
  printf '{"tool":"%s","step":"%s","startMs":%s,"durMs":%s,"exit":0,"commit":"%s","load":%s,"host":"%s"}\n' \
    "$tool" "$1" "$s" "$((_t - s))" "$_span_commit" "$_span_load" "$_span_host" >> "$FW_TIMINGS_FILE"
}

install_pnpm() {
  corepack enable
  pnpm --version
}

install_deps() {  # <filters, space separated>: pnpm install --frozen-lockfile for the workspace filters
  args=""
  for f in $1; do args="$args --filter $f"; done
  # shellcheck disable=SC2086
  pnpm install --frozen-lockfile $args
}

engine_libs() {
  cd packages/gate-breakpoints
  case "$FW_CI_ENGINE" in
    chromium) pnpm exec playwright-core install-deps chromium-headless-shell ;;
    playwright-webkit) pnpm exec playwright-core install-deps webkit ;;
  esac
}

engine_browser() {
  case "$FW_CI_ENGINE" in
    chromium)
      # Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor; the headless shell's sandbox needs them.
      sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
      dir=$fw/hs
      mkdir -p "$dir"
      zip=$fw/hs.zip
      curl -fsSL --retry 10 --retry-all-errors --retry-delay 3 -o "$zip" \
        "https://cdn.playwright.dev/builds/cft/${HS_VERSION}/linux-arm64/chrome-headless-shell-linux-arm64.zip"
      echo "${HS_SHA256}  $zip" | sha256sum -c -
      unzip -q "$zip" -d "$dir"
      chmod +x "$dir/chrome-headless-shell-linux-arm64/chrome-headless-shell"
      echo "export CHROME_PATH=$dir/chrome-headless-shell-linux-arm64/chrome-headless-shell" > "$fw/env.sh"
      "$dir/chrome-headless-shell-linux-arm64/chrome-headless-shell" --version
      ;;
    playwright-webkit)
      (cd packages/gate-breakpoints && pnpm exec playwright-core install webkit)
      : > "$fw/env.sh"
      ;;
  esac
}

engine_test() {
  # shellcheck disable=SC1091
  . "$fw/env.sh"
  (cd packages/premise-tests && node src/run.mjs --engine "$FW_CI_ENGINE" --out out)
  mkdir -p "$fw/ws/premise-results/premises-$FW_CI_ENGINE" "$fw/artifacts/premises-$FW_CI_ENGINE"
  cp packages/premise-tests/out/*.json "$fw/ws/premise-results/premises-$FW_CI_ENGINE/"
  cp packages/premise-tests/out/*.json "$fw/artifacts/premises-$FW_CI_ENGINE/"
}

run_verdict() {  # the twin of the verdict job: red = a finding or a lint error; the log is kept as an artifact
  set +e
  pnpm fw premises --results "$fw/ws/premise-results" > "$fw/artifacts/premises-verdict.txt" 2>&1
  rc=$?
  cat "$fw/artifacts/premises-verdict.txt"
  return "$rc"
}

sim_prepare() {
  sh .github/scripts/check-simulator.sh --create
  node .github/scripts/verify-snapshot.mjs
  brew install ios-webkit-debug-proxy
  command -v ios_webkit_debug_proxy
  mkdir -p "$fw/artifacts"
  sh .github/scripts/runner-info.sh "$fw/artifacts/runner.json"
  { sw_vers; xcodebuild -version; xcrun simctl list runtimes; brew list --versions ios-webkit-debug-proxy; } | tee "$fw/artifacts/tools.txt"
}

sim_boot() {
  xcrun simctl shutdown all || true
  udid=$(cat "$fw/fw-sim-udid.txt")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
}

sim_run() {  # one VM (v1), one session, the original arm: the same command as the GitHub job with sessions 1
  export FW_SNAPSHOT_SITE=$PWD/snapshot/site
  cd packages/measure-webkit
  mkdir -p out
  set +e
  # node's own exit status (the GitHub twin takes it through pipefail): the output goes to files, never through a pipe
  node src/cli.mjs determinism --runs 2 --keep --out out/v1-session-1.json > out/v1-session-1.md 2> out/v1-session-1.log
  rc=$?
  cat out/v1-session-1.md
  tail -n 40 out/v1-session-1.log
  { uptime; xcrun simctl list devices booted; ps -axo pid,pcpu,rss,comm | sort -k2 -nr | head -15; } > out/v1-host.txt 2>&1
  cp out/v1-* "$fw/artifacts/" 2>/dev/null
  return "$rc"
}

sim_delete() {
  xcrun simctl shutdown all || true
  xcrun simctl delete "${FW_SIM_NAME:-fw-iphone-27}" || true
}

finish() {  # timings.json beside the result files; the spans are kept even when the helper cannot run
  cp "$FW_TIMINGS_FILE" "$fw/artifacts/spans.jsonl" 2>/dev/null || true
  if command -v node >/dev/null 2>&1; then
    # bytes this job saved to the CircleCI cache and workspace (the engine jobs only; the stop rule counts them, scripts/circleci.mjs)
    cache=0; ws=0
    if [ -n "${FW_CI_ENGINE:-}" ]; then
      cache=$(( $(du -sk "$HOME/.local/share/pnpm/store" 2>/dev/null | cut -f1) * 1024 )) || cache=0
      ws=$(( $(du -sk "$fw/ws" 2>/dev/null | cut -f1) * 1024 )) || ws=0
    fi
    node scripts/circleci.mjs timings --spans "$FW_TIMINGS_FILE" --out "$fw/artifacts/timings.json" --job "${FW_CI_JOB:-unknown}" \
      --class "${FW_CI_CLASS:-unknown}" --sha "${CIRCLE_SHA1:-}" --cache-bytes "$cache" --workspace-bytes "$ws" ${FW_CI_ENGINE:+--digest-from "$fw/artifacts/premises-$FW_CI_ENGINE"} || true
  fi
}

cmd=${1:?usage: job.sh <step> [args]}
shift
case "$cmd" in
  run) "$@" ;;
  since) since "$1" ;;
  toolchain) T node sh .circleci/node-install.sh; T pnpm install_pnpm ;;
  install) T "deps install" install_deps "$1" ;;
  browser) T "system libraries" engine_libs; T "browser install" engine_browser ;;
  test) T test engine_test ;;
  verdict) T "fw premises" run_verdict ;;
  sim-prepare) T "runtime, snapshot, proxy" sim_prepare ;;
  sim-boot) T "simulator boot" sim_boot ;;
  sim-run) T "determinism session" sim_run ;;
  sim-delete) T "simulator delete" sim_delete ;;
  finish) finish ;;
  *) echo "job.sh: unknown step $cmd" >&2; exit 64 ;;
esac
