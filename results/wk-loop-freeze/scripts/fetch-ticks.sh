#!/bin/sh
out=$1; shift
for r in "$@"; do
  mkdir -p "$out/$r"
  gh run download "$r" --pattern 'sim-tick*' -D "$out/$r" 2>&1 | tail -1
done
