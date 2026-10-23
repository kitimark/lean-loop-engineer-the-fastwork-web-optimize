#!/bin/sh
# The steps of the CircleCI pilot jobs (.circleci/config.yml), one place, each timed with scripts/span.sh into
# /tmp/fw/spans.jsonl (the .fw-console/timings.jsonl format). Glue only: no decision. The steps are ports of the GitHub
# twins (.github/workflows/premise-tests.yml, webkit-sim.yml, .github/actions/{setup-pnpm,gate-engine}).
#   sh .circleci/job.sh <step> [args]
#   steps: since <name> | toolchain | install <filters> | browser | test | verdict | cache-probe | cache-gate
#          sim-prepare | sim-boot | sim-run | sim-delete | finish
#          land-lean | land-setup | land-actionlint | land-fwcore | land-suites <leg> | land-engine <leg>   (the land lane, task land-lane-circleci)
#          lake-key | lake-probe | lake-gate   (the Lake cache of the land job, task circleci-lean-cache)
# Env (set by the job): FW_CI_JOB, FW_CI_CLASS, FW_CI_ENGINE (engine jobs), HS_VERSION and HS_SHA256 (chromium).
set -eu
cd "$(dirname "$0")/.."
fw=${FW_JOB_DIR:-/tmp/fw}
mkdir -p "$fw/artifacts" "$fw/ws"
export FW_TIMINGS_FILE=$fw/spans.jsonl
export RUNNER_TEMP=$fw
export PATH="$HOME/.fw-node/bin:$HOME/.elan/bin:$PATH"
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

# The pnpm cache is saved only when the lockfile changed. CircleCI has no "cache was restored" flag and no condition on save_cache,
# so the job keeps its own marker: ~/.fw-cache/lock-sha256 holds the sha256 of the pnpm-lock.yaml the saved store belongs to, and
# it is a cached path next to the store. cache-probe (right after restore_cache) says whether the restored marker names this
# lockfile; cache-gate (the last step before save_cache) halts the job when it does (`circleci-agent step halt`, documented in the
# configuration reference: the job ends as a success and save_cache never runs), else writes the marker so the save carries it.
cache_marker=$HOME/.fw-cache/lock-sha256
lock_sha() { node -p "require('crypto').createHash('sha256').update(require('fs').readFileSync('pnpm-lock.yaml')).digest('hex')"; }

cache_probe() {
  rm -f "$fw/cache-current"
  if [ -f "$cache_marker" ] && [ "$(cat "$cache_marker")" = "$(lock_sha)" ]; then
    : > "$fw/cache-current"
    echo "pnpm cache: the restored store belongs to this lockfile; no save at the end"
  else
    echo "pnpm cache: none restored for this lockfile; the job saves one at the end"
  fi
}

cache_gate() {
  if [ -f "$fw/cache-current" ]; then
    echo "pnpm cache: current, halting before save_cache"
    circleci-agent step halt
  else
    mkdir -p "$(dirname "$cache_marker")"
    lock_sha > "$cache_marker"
    echo "pnpm cache: marker written, save_cache follows"
  fi
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
    # bytes this job persisted to the workspace (the engine jobs only; the stop rule counts them, scripts/circleci.mjs). The cache
    # bytes are not measured here: the ledger reads them from the job steps API (what the save step actually uploaded).
    ws=0
    if [ -n "${FW_CI_ENGINE:-}" ]; then
      ws=$(( $(du -sk "$fw/ws" 2>/dev/null | cut -f1) * 1024 )) || ws=0
    fi
    node scripts/circleci.mjs timings --spans "$FW_TIMINGS_FILE" --out "$fw/artifacts/timings.json" --job "${FW_CI_JOB:-unknown}" \
      --class "${FW_CI_CLASS:-unknown}" --sha "${CIRCLE_SHA1:-}" --workspace-bytes "$ws" ${FW_CI_ENGINE:+--digest-from "$fw/artifacts/premises-$FW_CI_ENGINE"} || true
  fi
}

# ---- the land lane (task land-lane-circleci): the twin of .github/workflows/land.yml, one job per leg ----------------------------
# Same entry as GitHub: `pnpm fw checks --affected --base <base> --tier remote --leg <leg>`, then, in an engine leg whose selection holds
# the preview browser suite, that suite on the leg's engine. The job writes lane.json ({leg, sha, digest, engine, rc}): the sha of the
# change under test and the `LANE digest=` line, the same two facts the GitHub twin prints in its `lane: sha=.. digest=..` step name.
# The pins below equal the ones of .github/actions/setup-lean (scripts/circleci.test.mjs checks it).
ELAN_VERSION=v4.2.4
ELAN_SHA256=05febd124d84ebf994b2e7479922a5650b1e950c17ae3bd1ddd776b65bb72bf9

land_lean() {  # elan from the pinned release (sha256 checked), then the toolchain named in lean/lean-toolchain
  test "$(uname -m)" = aarch64
  dir=$fw/elan-dl
  mkdir -p "$dir"
  curl -fsSL --retry 5 --retry-all-errors -o "$dir/elan.tgz" \
    "https://github.com/leanprover/elan/releases/download/${ELAN_VERSION}/elan-aarch64-unknown-linux-gnu.tar.gz"
  echo "${ELAN_SHA256}  $dir/elan.tgz" | sha256sum -c -
  tar -xzf "$dir/elan.tgz" -C "$dir"
  "$dir/elan-init" -y --no-modify-path --default-toolchain none
  tc=$(cat lean/lean-toolchain)
  ok=0
  for i in 1 2 3 4 5; do
    if elan toolchain install "$tc"; then ok=1; break; fi
    echo "elan toolchain install failed (attempt $i)"; sleep $((i * 5))
  done
  test "$ok" = 1
  (cd lean && lean --version && lake --version)
}

land_actionlint() {
  mkdir -p "$HOME/.fw-node/bin"
  curl -fsSL -o "$fw/actionlint.tgz" "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz"
  echo "325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6  $fw/actionlint.tgz" | sha256sum -c -
  tar -xzf "$fw/actionlint.tgz" -C "$HOME/.fw-node/bin" actionlint
  actionlint -version | head -1
  command -v shellcheck >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y shellcheck; }
}
land_setup() {  # main is the pushed commit's first parent (.github/scripts/land-base.sh); the commit identity the temp repos of the tests need
  git branch -f main "$(sh .github/scripts/land-base.sh main)"
  git config --global user.name land-lane
  git config --global user.email land-lane
}

# The Lake cache of the land job (task circleci-lean-cache), keyed like .github/actions/setup-lean: the exact key is toolchain +
# Lake manifest + the Lean sources, the restore key is the toolchain + manifest prefix. CircleCI `checksum` hashes one file, so
# lake-key writes the hash strings that the config's key template reads. Nothing else is decided here: whether to save is the
# marker below, the same trick as the pnpm cache (cache_probe / cache_gate): ~/.fw-lake/key holds the exact key the saved cache
# belongs to; a restore of the exact key leaves a marker equal to the current key and the job halts before save_cache. The cache
# is the Lake artifact cache (LAKE_CACHE_DIR, enableArtifactCache in lean/lakefile.toml), on the same file system as lean/.lake so
# Lake can hard-link the artifacts back.
lake_dir=$HOME/.fw-lake
export LAKE_CACHE_DIR=$lake_dir/cache
lake_marker=$lake_dir/key

lake_key() {  # the hash strings of the cache key; tm = toolchain + manifest, src = the Lean sources (the file list setup-lean hashes)
  tm=$(cat lean/lean-toolchain lean/lake-manifest.json | sha256sum | cut -d' ' -f1)
  src=$({ ls lean/lakefile.toml lean/*.lean; git ls-files lean/Fw lean/FwTest; } | sort -u | xargs sha256sum | sha256sum | cut -d' ' -f1)
  # a pipe in $(...) hides a failed sha256sum (sh has no pipefail): an empty or short string would be a key shared by every tree
  for h in "$tm" "$src"; do test "${#h}" -eq 64 || { echo "lake key: not a sha256 hex string: '$h'" >&2; return 1; }; done
  printf '%s\n' "$tm" > "$fw/lake-tm.key"
  printf '%s\n' "$src" > "$fw/lake-src.key"
  printf '%s-%s\n' "$tm" "$src" > "$fw/lake-full.key"
  mkdir -p "$LAKE_CACHE_DIR"
  echo "lake key: toolchain+manifest $(echo "$tm" | cut -c1-8), sources $(echo "$src" | cut -c1-8)"
}

lake_probe() {  # right after restore_cache: does the restored marker name this exact key?
  rm -f "$fw/lake-current"
  mkdir -p "$LAKE_CACHE_DIR"
  if [ -f "$lake_marker" ] && [ "$(cat "$lake_marker")" = "$(cat "$fw/lake-full.key")" ]; then
    : > "$fw/lake-current"
    echo "lake cache: the exact key was restored; no save at the end"
  elif [ -f "$lake_marker" ]; then
    echo "lake cache: an older entry (same toolchain and manifest) was restored; the job saves the new key at the end"
  else
    echo "lake cache: nothing restored; the job saves one at the end"
  fi
}

lake_gate() {  # last step before save_cache: halt when the exact key was restored, else write the marker for the save
  if [ -f "$fw/lake-current" ]; then
    echo "lake cache: current, halting before save_cache"
    circleci-agent step halt
  else
    mkdir -p "$lake_dir"
    cp "$fw/lake-full.key" "$lake_marker"
    echo "lake cache: marker written, save_cache follows; $(du -sk "$lake_dir" | cut -f1) KiB on disk"
  fi
}

land_fwcore() { (cd lean && lake build fwcore); }

land_suites() {  # <leg>
  leg=$1
  base=$(sh .github/scripts/land-base.sh base)
  sha=$(sh .github/scripts/land-base.sh rev)
  set +e
  pnpm fw checks --affected --base "$base" --tier remote --leg "$leg" > "$fw/land.log" 2>&1
  rc=$?
  set -e
  cat "$fw/land.log"
  digest=$(sed -n 's/^LANE digest=//p' "$fw/land.log" | head -n1)
  engine=$(sed -n 's/^LANE leg=.* engine=\([a-z]*\) .*/\1/p' "$fw/land.log" | head -n1)
  mkdir -p "$fw/artifacts"
  printf '{"leg":"%s","sha":"%s","digest":"%s","engine":"%s","rc":%s}\n' "$leg" "$sha" "$digest" "$engine" "$rc" > "$fw/artifacts/lane.json"
  echo "$engine" > "$fw/land-engine"
  grep -E '^(VERDICT|TIMING|checks:|LANE)' "$fw/land.log" > "$fw/artifacts/land-summary.txt" || true
  return "$rc"
}

land_engine() {  # <leg>: the preview browser suite, only when the suites step said the selection holds it
  leg=$1
  [ "$(cat "$fw/land-engine" 2>/dev/null)" = true ] || { echo "no browser suite in this selection"; return 0; }
  # Each in a subshell: engine_libs does `cd packages/gate-breakpoints`, and the cd must not outlive it (the suite below runs from the root;
  # the first live run of this step failed with exit 2 on `cd packages/e2e-preview`).
  (FW_CI_ENGINE=$leg; export FW_CI_ENGINE; engine_libs)
  (FW_CI_ENGINE=$leg; export FW_CI_ENGINE; engine_browser)
  # shellcheck disable=SC1091
  . "$fw/env.sh"
  (cd packages/e2e-preview && node src/run.mjs --engine "$leg" --out out)
  mkdir -p "$fw/artifacts/land-preview-e2e-$leg"
  cp packages/e2e-preview/out/*.json "$fw/artifacts/land-preview-e2e-$leg/" 2>/dev/null || true
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
  land-lean) T "lean toolchain" land_lean ;;
  land-setup) T "main ref and identity" land_setup ;;
  land-actionlint) T "actionlint" land_actionlint ;;
  land-fwcore) T "fwcore build" land_fwcore ;;
  land-suites) T "suites" land_suites "$1" ;;
  land-engine) T "browser suite" land_engine "$1" ;;
  lake-key) T "lake key" lake_key ;;
  lake-probe) lake_probe ;;
  lake-gate) lake_gate ;;
  cache-probe) cache_probe ;;
  cache-gate) cache_gate ;;
  finish) finish ;;
  *) echo "job.sh: unknown step $cmd" >&2; exit 64 ;;
esac
