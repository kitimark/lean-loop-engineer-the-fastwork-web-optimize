#!/bin/sh
# Node 24 for a CircleCI job (the twin of actions/setup-node with node-version 24): the newest 24.x tarball of nodejs.org for
# this OS and CPU, checked against the SHASUMS256.txt of the same directory, unpacked to $HOME/.fw-node (bin/ is put on PATH by
# .circleci/job.sh). Skipped when node 24 is already on PATH. Glue only: no decision.
#   sh .circleci/node-install.sh
set -eu
dest=${FW_NODE_DIR:-$HOME/.fw-node}
if [ -x "$dest/bin/node" ] && "$dest/bin/node" --version | grep -q '^v24\.'; then echo "node: $("$dest/bin/node" --version) already in $dest"; exit 0; fi
if command -v node >/dev/null 2>&1 && node --version | grep -q '^v24\.'; then echo "node: $(node --version) on PATH"; exit 0; fi
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo "node-install: unsupported OS $(uname -s)" >&2; exit 1 ;; esac
case "$(uname -m)" in aarch64|arm64) cpu=arm64 ;; x86_64) cpu=x64 ;; *) echo "node-install: unsupported CPU $(uname -m)" >&2; exit 1 ;; esac
base=https://nodejs.org/dist/latest-v24.x
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fwnode.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -o "$tmp/SHASUMS256.txt" "$base/SHASUMS256.txt"
line=$(grep "node-v24\.[0-9.]*-$os-$cpu\.tar\.gz\$" "$tmp/SHASUMS256.txt" | head -1)
[ -n "$line" ] || { echo "node-install: no node-v24 tarball for $os-$cpu in SHASUMS256.txt" >&2; exit 1; }
sum=${line%% *}
file=${line##* }
curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -o "$tmp/$file" "$base/$file"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp/$file" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1); fi
[ "$got" = "$sum" ] || { echo "node-install: sha256 of $file is $got, SHASUMS256.txt says $sum" >&2; exit 1; }
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/$file" -C "$dest" --strip-components=1
echo "node: $("$dest/bin/node" --version) installed in $dest ($file)"
