#!/bin/sh
# wt-prep.sh: run first in a fresh git worktree. Clones the main checkout's lean/.lake (APFS clone,
# cp -c -R) so `lake build` is a no-op instead of a clean build. [parallel-plan Q1]
# Lake takes no lock file during builds (lean4 src/lake/Lake/Util/Lock.lean:18), so a running
# `lake build` in the main lean dir is detected with ps + lsof cwd; the clone is then skipped. Only a real build counts:
# `lake serve` (the Lean LSP, long-lived) and `lean` workers do not, and nothing is ever killed.
# node_modules: left to `pnpm install --offline --frozen-lockfile` (see docs/team/handoffs/wt-prep.md).
set -eu
# build_pids: stdin = `ps -axo pid=,args=` lines; prints the pid of every line whose program is `lake` (basename) and whose
# first subcommand (flags skipped, with the value of -d/-f/--dir/--file) is `build`. Matching on argv, not on a name.
build_pids() {
  awk '{ n = split($2, p, "/"); if (p[n] != "lake") next
         for (i = 3; i <= NF; i++) { if ($i ~ /^(-d|-f|--dir|--file)$/) { i++; continue } if ($i ~ /^-/) continue; if ($i == "build") print $1; break } }'
}
if [ "${1:-}" = "--build-pids" ]; then build_pids; exit 0; fi
if [ "${1:-}" = "--self-test" ]; then  # `sh scripts/wt-prep.sh --self-test`: the LSP and look-alikes are not builds
  got=$(printf '%s\n' \
    ' 5836 /opt/elan/toolchains/t/bin/lake serve -- -Dserver.reportDelayMs=0' ' 6000 lake env lean Fw/X.lean' \
    ' 6001 /x/bin/lean --server build' ' 6003 vim lake build' ' 6004 lake' ' 6005 /x/bin/lake exe fwcore' \
    ' 100 /opt/elan/bin/lake build' ' 101 lake build fwtest' ' 102 lake -d lean build' ' 103 lake --dir lean build Fw' ' 104 lake serve' \
    | build_pids | paste -sd, -)
  [ "$got" = "100,101,102,103" ] && { echo "wt-prep self-test: ok"; exit 0; }
  echo "wt-prep self-test: FAILED (got $got)"; exit 1
fi
here=$(git rev-parse --show-toplevel)
main=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
start=$(date +%s)
# privacy pre-commit hook for every worktree (config is shared; the relative value resolves per worktree)
git config core.hooksPath scripts/hooks
if [ "$here" = "$main" ]; then
  echo "wt-prep: this is the main checkout, nothing to do"; exit 0
fi
if [ -e "$here/lean/.lake" ]; then
  msg="lean/.lake present, skipped"
elif [ ! -d "$main/lean/.lake" ]; then
  msg="main has no lean/.lake, skipped"
else
  pids=$(ps -axo pid=,args= 2>/dev/null | build_pids | paste -sd, - || true)
  busy=""
  if [ -n "$pids" ]; then
    busy=$(lsof -a -d cwd -p "$pids" -Fpn 2>/dev/null | awk -v m="$main/lean" '/^p/{p=substr($0,2)} /^n/{if (index(substr($0,2), m)==1) {print p; exit}}' || true)
  fi
  if [ -n "$busy" ]; then
    msg="main lean build running (pid $busy), clone skipped; rerun later"
  else
    rm -rf "$here/lean/.lake.partial"
    cp -c -R "$main/lean/.lake" "$here/lean/.lake.partial"
    mv "$here/lean/.lake.partial" "$here/lean/.lake"
    msg="cloned lean/.lake"
  fi
fi
echo "wt-prep: $msg ($(( $(date +%s) - start )) s)"
