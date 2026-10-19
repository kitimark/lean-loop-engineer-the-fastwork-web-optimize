#!/bin/sh
# The two revisions the land lane takes from the pushed commit, never from origin/main (which may lag the Mac's main).
#   main  the first parent of HEAD: the local main a land merge was made on (a probe commit: its parent). The lane sets
#         refs/heads/main there, so tests that read main see the facts they see locally.
#   base  what the selected checks are diffed against: the same first parent, but a tip that changes nothing (a `[ci:land]`
#         marker commit) is skipped, so the diff is that of the work under it.
set -eu
what="${1:?usage: land-base.sh main|base}"
case "$what" in
  main) git rev-parse --verify --quiet 'HEAD^1' || git rev-parse HEAD ;;
  base)
    rev=HEAD
    while [ "$(git rev-list --parents -n1 "$rev" | wc -w)" -eq 2 ] && [ "$(git rev-parse "$rev^{tree}")" = "$(git rev-parse "$rev^1^{tree}")" ]; do
      rev="$rev^1"
    done
    git rev-parse --verify --quiet "$rev^1" || git rev-parse "$rev"
    ;;
  *) echo "usage: land-base.sh main|base" >&2; exit 2 ;;
esac
