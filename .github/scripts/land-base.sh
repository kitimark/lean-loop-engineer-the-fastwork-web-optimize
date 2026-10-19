#!/bin/sh
# The one revision the land lane takes from the pushed commit, never from origin/main (which may lag the Mac's main).
#   rev   the first commit from HEAD that changes something: HEAD itself, or under any `[ci:land]` marker tips (a commit
#         with one parent and the same tree as that parent). The change under test is rev.
#   main  = base = rev^1 (rev itself for a root): for a land merge the local main it was made on, for a probe the commit
#         under the work. The lane sets refs/heads/main there and diffs the selected checks against it, so neither
#         holds the change under test.
set -eu
what="${1:?usage: land-base.sh main|base}"
case "$what" in
  main|base) ;;
  *) echo "usage: land-base.sh main|base" >&2; exit 2 ;;
esac
rev=HEAD
while [ "$(git rev-list --parents -n1 "$rev" | wc -w)" -eq 2 ] && [ "$(git rev-parse "$rev^{tree}")" = "$(git rev-parse "$rev^1^{tree}")" ]; do
  rev="$rev^1"
done
git rev-parse --verify --quiet "$rev^1" || git rev-parse "$rev"
