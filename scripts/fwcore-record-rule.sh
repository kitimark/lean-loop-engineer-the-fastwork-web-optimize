# Sourced by scripts/fwcore-build.sh. SH STAND-IN of Fw.Obs.recordTree (lean/Fw/Obs/Stale.lean; theorems recordTree_some_iff,
# recordTree_dirty, recordTree_moved, recordTree_merged), checked by scripts/fwcore-build.test.mjs against the same table as the #guards.
# record_rule <tree before> <tree after> <clean before 0/1> <clean after 0/1>: prints the tree to record, or nothing.
record_rule() {
  if [ -n "$1" ] && [ "$1" = "$2" ] && [ "$3" = 1 ] && [ "$4" = 1 ]; then echo "$1"; fi
}
