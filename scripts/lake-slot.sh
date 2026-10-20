#!/bin/sh
# Runs a command under one machine-wide Lake build slot: sh scripts/lake-slot.sh <cmd...>
# The functions live in scripts/lake-slot-lib.sh; callers that should not start a second sh source that file instead.
set -eu
[ "$#" -gt 0 ] || { echo "usage: sh scripts/lake-slot.sh <cmd...>" >&2; exit 64; }
case $0 in */*) _ls_s=${0%/*} ;; *) _ls_s=. ;; esac
. "$_ls_s/lake-slot-lib.sh"
lake_slot "$_ls_s/.." "$@"
