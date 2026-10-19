#!/bin/sh
# Inner-loop check (improvement E4/Q5): the cheap lean/ gates in the order they fail fastest, with per-step seconds.
#   1. check-partial.sh   grep gates (no partial ops in the glue, no escape hatches)
#   2. lake build         incremental: only the changed modules (proofs and #guard run here)
#   3. lake test          golden round trips (0.3 s when up to date)
#   4. fwcore golden diff the real binary on golden/wire-requests.txt (LEAN_ABORT_ON_PANIC=1)
#   5. axiom check        no sorryAx and only the standard axioms (scripts/axiom-check.sh)
# The breakgen checks stay in check.sh, the land gate.
# On failure: the failing step's output, then one line "check-fast: FAILED at <step> ...", exit 1.
set -u
cd "$(dirname "$0")/.." || exit 2
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
log=$(mktemp "${TMPDIR:-/tmp}/check-fast.XXXXXX")
trap 'rm -f "$log"' EXIT
total0=$(now)
timings=""
step() {
  name=$1; shift
  t0=$(now)
  if "$@" >"$log" 2>&1; then
    dt=$(perl -e "printf '%.1f', $(now) - $t0")
    timings="$timings $name=${dt}s"
  else
    cat "$log"
    echo "check-fast: FAILED at $name (output above)"
    exit 1
  fi
}
golden() {
  LEAN_ABORT_ON_PANIC=1 .lake/build/bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt
}
step check-partial scripts/check-partial.sh
step build lake build
step test lake test
step golden golden
step axioms sh scripts/axiom-check.sh
total=$(perl -e "printf '%.1f', $(now) - $total0")
echo "check-fast: ok (${total}s:$timings)"
