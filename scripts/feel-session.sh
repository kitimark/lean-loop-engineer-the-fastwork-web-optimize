#!/bin/sh
# feel-session.sh: start the captured phone feel session of 2026-10-30 (research/notes/2026/10-30-feel-session-2-prep.md).
#   sh scripts/feel-session.sh [--seed N] [--date YYYY-MM-DD] [--build] [--plan]
# Run only after the user said yes to a feel session. In order it
#   1. prints the plan (arm count, visit count, estimate, commands) and checks that every arm is built (--build builds
#      the missing ones from apps/site; --plan stops here and touches no phone),
#   2. probes the phone read-only (devicectl list/lockState, idevice_id -l); if it is not ready it prints what to ask the
#      user and exits 3, changing no setting,
#   3. starts `feel start` (capture on, pin Serious, --fresh, seed) in the background in its own process group, log in
#      .local/phone/<date>-feel2-start.log, and waits up to 300 s for the control server (a failed start prints the log
#      tail and the user-side ask, exit 1).
# It never runs `feel next`: the lead opens each arm. Exit: 0 running, 1 start failed, 2 usage, 3 phone not ready, 4 arms missing.
set -eu
seed=""; date=$(date +%Y-%m-%d); build=0; plan_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) seed=${2:?--seed needs a whole number}; shift 2 ;;
    --date) date=${2:?--date needs YYYY-MM-DD}; shift 2 ;;
    --build) build=1; shift ;;
    --plan) plan_only=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "feel-session: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$date" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "feel-session: --date must be YYYY-MM-DD" >&2; exit 2 ;; esac
# Without --seed the seed is the day number: a new blind order each day, never the one default of an earlier session.
[ -n "$seed" ] || seed=$(( $(date +%s) / 86400 ))
case "$seed" in ''|*[!0-9]*) echo "feel-session: --seed must be a whole number" >&2; exit 2 ;; esac

top=$(cd "$(dirname "$0")/.." && pwd -P)
main=${FEEL_MAIN:-$(cd "$top/packages/measure-webkit" && node -e "import('./src/device-raw-dir.mjs').then((m) => console.log(m.mainCheckout()))")}
dir=".local/phone/$date-feel2"
site="../../apps/site/dist/aot"
log="$main/.local/phone/$date-feel2-start.log"
# FEEL_CLI, FEEL_MAIN, FEEL_WAIT_S and FEEL_POLL_S exist for test/feel-session.test.mjs (a stub CLI); the defaults are the real ones.
cli=${FEEL_CLI:-"node src/device-cli.mjs"}
wait_s=${FEEL_WAIT_S:-300}
poll_s=${FEEL_POLL_S:-5}
cd "$top/packages/measure-webkit"

mkdir -p "$main/.local/phone"
rc=0
$cli feel plan --seed "$seed" --dir "$dir" --site "$site" || rc=$?
if [ "$rc" -eq 4 ] && [ "$build" -eq 1 ]; then
  echo "feel-session: building the missing arms (a local build, not a measurement)"
  cmd=$($cli feel build-cmd)
  (cd "$top/apps/site" && eval "$cmd") > "$main/.local/phone/$date-feel2-build.log" 2>&1 || { echo "feel-session: the build failed, see .local/phone/$date-feel2-build.log" >&2; exit 4; }
  rc=0
  out=$($cli feel plan --seed "$seed" --dir "$dir" --site "$site") || rc=$?
  echo "$out" | tail -1
fi
[ "$rc" -eq 0 ] || { [ "$rc" -eq 4 ] && echo "feel-session: arms missing; run the build above or pass --build" >&2; exit "$rc"; }
[ "$plan_only" -eq 0 ] || { echo "feel-session: --plan, no phone touched"; exit 0; }

if [ -e "$main/$dir" ]; then echo "feel-session: $dir exists; pass another --date or move it away" >&2; exit 2; fi
prc=0
$cli feel probe || prc=$?
[ "$prc" -eq 0 ] || exit 3

set -m
nohup $cli feel start --site "$site" --dir "$dir" --pin Serious --seed "$seed" --fresh > "$log" 2>&1 &
pid=$!
set +m
echo "$pid" > "$log.pid"
echo "feel-session: started pid $pid (own process group), log $log; waiting up to $wait_s s for the control server"

waited=0
while [ "$waited" -lt "$wait_s" ]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "feel-session: the session process ended before it was ready; last log lines:" >&2
    tail -n 15 "$log" >&2
    $cli feel ask --file "$log" >&2 || true
    exit 1
  fi
  if $cli feel status --dir "$dir" > /dev/null 2>&1; then
    echo "feel-session: running (pid $pid, pin Serious, capture on). Nothing is open on the phone yet: the lead runs 'feel next' after the user says go."
    echo "feel-session: next -> $cli feel next --dir $dir   (from packages/measure-webkit)"
    exit 0
  fi
  sleep "$poll_s"
  waited=$((waited + poll_s))
done
echo "feel-session: not ready after $wait_s s (pid $pid still alive); last log lines:" >&2
tail -n 15 "$log" >&2
$cli feel ask --file "$log" >&2 || true
exit 1
