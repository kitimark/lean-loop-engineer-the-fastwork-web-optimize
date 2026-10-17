#!/bin/sh
# All lean/ gates (TL0): grep gates, build (proofs + #guard), tests (golden round trips),
# math-view lint (math present, no sorryAx, standard axioms only), and the real binary on the
# golden lines with LEAN_ABORT_ON_PANIC=1.
set -eu
cd "$(dirname "$0")/.."
. ../scripts/span.sh  # span <tool> <step> <cmd...>: one timing line per stage in .fw-console/timings.jsonl (docs/team/tools/timings.md)
span lean/check "grep gates" scripts/check-partial.sh
span lean/check "import check" node scripts/check-imports.mjs  # every Fw module is imported by a root, none twice in Fw.lean (the union merge can repeat a line)
span lean/check "lake build" lake build
span lean/check "lake test" lake test
span lean/check "mathview lint" scripts/mathview-cached.sh >/dev/null  # lint; replayed from .lake/mathview-cache/ when the sources are unchanged
span lean/check "golden wire replay" sh -c 'LEAN_ABORT_ON_PANIC=1 .lake/build/bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt'
echo "check: fwcore binary reproduces golden/wire-replies.txt"
span lean/check "breakgen check lean" lake exe breakgen --check Fw/Site/breakpoints.gen.json
span lean/check "breakgen check site" lake exe breakgen --check ../apps/site/src/breakpoints.gen.json || echo "check: WARNING apps/site/src/breakpoints.gen.json is not the Lean output yet"
echo "check: all lean/ gates green"
