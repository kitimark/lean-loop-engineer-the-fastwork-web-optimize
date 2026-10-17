#!/bin/sh
# All lean/ gates (TL0): grep gates, build (proofs + #guard), tests (golden round trips),
# math-view lint (math present, no sorryAx, standard axioms only), and the real binary on the
# golden lines with LEAN_ABORT_ON_PANIC=1.
set -eu
cd "$(dirname "$0")/.."
scripts/check-partial.sh
lake build
lake test
lake exe mathview --lint
LEAN_ABORT_ON_PANIC=1 .lake/build/bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt
echo "check: fwcore binary reproduces golden/wire-replies.txt"
echo "check: all lean/ gates green"
