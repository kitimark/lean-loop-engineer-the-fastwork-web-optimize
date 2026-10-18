#!/bin/sh
# Build the fwcore binary and record the commit it was built from next to it (read by `fw watch`, task console-stale:
# the binary is stale when lean/ inputs changed on main after this commit). Run in the checkout whose binary runs.
set -eu
cd "$(dirname "$0")/../lean"
lake build
git rev-parse HEAD > .lake/build/bin/fwcore.commit
echo "fwcore built from $(cat .lake/build/bin/fwcore.commit)"
