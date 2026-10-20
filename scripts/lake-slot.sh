#!/bin/sh
# Runs a Lake command under one machine-wide build slot (task lake-build-slots, Lean Fw.Sched.LakeSlot):
#   sh scripts/lake-slot.sh <cmd...>
#   LAKE_SLOT_LIB=1 . scripts/lake-slot.sh; ( lake_slot <repo root> <cmd...> )
# A slot is a flock(2) lock on fd 9 (lockf on macOS, flock on Linux) on <git common dir>/lake-slot/<i>; the shell then
# execs the command, so the lock lives exactly as long as the command and its children. LAKE_SLOT_DIR overrides the
# directory. LAKE_SLOT is set for the command; a nested call runs inside the caller's slot.

# _ls_take <dir> <seconds per slot>: sets _ls_i and _ls_p, or returns 75 when every slot stays busy
_ls_take() {
  _ls_i=0
  for _ls_p in $LAKE_SLOT_POOLS; do
    exec 9>>"$1/$_ls_i"
    if [ "$_ls_l" = lockf ]; then lockf -s -t "$2" 9 && return 0 || _ls_rc=$?
    elif [ "$2" = 0 ]; then flock -n -E 75 9 && return 0 || _ls_rc=$?
    else flock -w "$2" -E 75 9 && return 0 || _ls_rc=$?; fi
    [ "$_ls_rc" = 75 ] || { echo "lake-slot: $_ls_l failed on $1/$_ls_i (exit $_ls_rc)" >&2; exit "$_ls_rc"; }
    _ls_i=$((_ls_i + 1))
  done
  exec 9>&-
  return 75
}

_ls_wait() {
  until _ls_take "$1" 1; do :; done
}

lake_slot() {
  _ls_r=$1; shift
  [ -z "${LAKE_SLOT:-}" ] || exec "$@"
  . "$_ls_r/packages/contracts/golden/sched/lake-slot.gen.sh"
  _ls_d=${LAKE_SLOT_DIR:-}
  if [ -z "$_ls_d" ]; then
    if [ -d "$_ls_r/.git" ]; then _ls_c=$_ls_r/.git
    elif [ -f "$_ls_r/.git" ] && read -r _ _ls_g < "$_ls_r/.git" && case $_ls_g in /*) ;; *) _ls_g=$_ls_r/$_ls_g ;; esac &&
      [ -f "$_ls_g/commondir" ] && read -r _ls_c < "$_ls_g/commondir"; then
      case $_ls_c in /*) ;; *) _ls_c=$_ls_g/$_ls_c ;; esac
    else
      _ls_c=$(git -C "$_ls_r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exec "$@"
    fi
    _ls_d=$_ls_c/lake-slot
  fi
  if command -v lockf >/dev/null 2>&1; then _ls_l=lockf
  elif command -v flock >/dev/null 2>&1; then _ls_l=flock
  else echo "lake-slot: no lockf or flock on PATH; running without a slot" >&2; exec "$@"; fi
  [ -d "$_ls_d" ] || mkdir -p "$_ls_d"
  if ! _ls_take "$_ls_d" 0; then
    echo "lake-slot: all $_ls_i slots busy; waiting for one" >&2
    if [ -r "$_ls_r/scripts/span.sh" ]; then . "$_ls_r/scripts/span.sh"; else span() { shift 2; "$@"; }; fi
    span lake-slot wait _ls_wait "$_ls_d"
    echo "lake-slot: got slot $_ls_i" >&2
  fi
  export LAKE_SLOT="$_ls_i"
  if [ "$_ls_p" != full ]; then export LEAN_NUM_THREADS="$_ls_p"; echo "lake-slot: slot $_ls_i, pool $_ls_p" >&2; fi
  exec "$@"
}

if [ -z "${LAKE_SLOT_LIB:-}" ]; then
  set -eu
  case $0 in */*) lake_slot "${0%/*}/.." "$@" ;; *) lake_slot .. "$@" ;; esac
fi
