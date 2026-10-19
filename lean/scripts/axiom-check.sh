#!/bin/sh
# Runs AxiomCheck.check after an import of every module under Fw/ and of the probe AxProbe: imported at the header,
# each module brings its exported axiom table (Lean/Util/CollectAxioms.lean:113-140 @ v4.35.0), which importModules
# (loadExts := false) leaves empty.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/axcheck.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
cp scripts/axiom-check-cases/AxProbe.lean "$tmp/"
lake env lean -R "$tmp" -o "$tmp/AxProbe.olean" "$tmp/AxProbe.lean" > "$tmp/probe.out" || { cat "$tmp/probe.out"; exit 1; }
{
  echo 'import AxProbe'
  echo 'import Fw'
  find Fw -name '*.lean' | LC_ALL=C sort | sed -e 's/\.lean$//' -e 's|/|.|g' -e 's/^/import /'
  cat scripts/AxiomCheck.lean
  echo 'run_cmd AxiomCheck.check'
} | LEAN_PATH="$tmp" lake env lean --stdin
