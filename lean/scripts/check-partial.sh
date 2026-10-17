#!/bin/sh
# Grep gates for lean/ (PLAN §3.2 item 4, §5.4 TL0). Run from anywhere; exits 1 on any hit.
#  1. No partial operations in the glue (Fw/Wire.lean, Fw/Measure/Wire.lean, Fw/Measure/Golden.lean, Main.lean): any identifier or index
#     followed by a bang (the get/head/getLast/index accessors, panic, unreachable, ...).
#     String interpolation (s/m/f followed by a bang and a quote) is allowed.
#  2. No escape hatches in any Lean source: sorry, native_decide, implemented_by, unsafe.
set -u
cd "$(dirname "$0")/.." || exit 2
fail=0

hits=$(for f in Fw/Wire.lean Fw/Measure/Wire.lean Fw/Measure/Golden.lean Main.lean; do
  sed -E 's/(^|[^A-Za-z0-9_.])[smf]!"/\1"/g' "$f" | grep -nE '[A-Za-z0-9_\]]!' | sed "s|^|$f:|"
done)
if [ -n "$hits" ]; then
  echo "check-partial: partial operation in Wire/Main:"; echo "$hits"; fail=1
fi

hits=$(grep -rnwE 'sorry|native_decide|implemented_by|unsafe' --include='*.lean' \
  Fw Fw.lean Main.lean FwTest FwTestMain.lean MathView.lean MathViewMain.lean scripts/MeasureGolden.lean)
if [ -n "$hits" ]; then
  echo "check-partial: forbidden token:"; echo "$hits"; fail=1
fi

[ $fail -eq 0 ] && echo "check-partial: ok (no partial ops in Wire/Main; no forbidden tokens)"
exit $fail
