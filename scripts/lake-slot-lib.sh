# Defines lake_slot, the machine-wide Lake build slot (task lake-build-slots, Lean Fw.Sched.LakeSlot); defines only.
#   . scripts/lake-slot-lib.sh; ( lake_slot <repo root> <cmd...> )   or   lake_slot_hold <repo root>; ...; lake_slot_release
# The command-line form is scripts/lake-slot.sh. A slot is a flock(2) lock on fd 9 (lockf on macOS, flock on Linux) on
# <git common dir>/lake-slot/<i>; the shell then execs the command (with lock events on it runs the command as a child
# and exits with its status), so the lock lives exactly as long as the command and its children. LAKE_SLOT_DIR overrides the directory. LAKE_SLOT is set for the command; a nested call runs inside the
# caller's slot.

# Lock events (task sup-baseline): one JSON line per slot taken or given back in <main checkout>/.fw-console/locks.jsonl
# (FW_LOCK_EVENTS_FILE overrides the file, FW_LOCK_EVENTS=off or CI disables it). Fields: ts (ms; whole seconds where
# `date` has no %N), lock, ev, kind, pid ($$ of the calling shell) and start (epoch s, 0 when unknown), slot, waitMs or holdMs. No paths, no arguments.
# With events on, lake_slot runs the command as a child (to see its end) instead of exec; with events off it execs.
_ls_now() {
  _ls_ms=$(date +%s%N 2>/dev/null) || _ls_ms=
  case "$_ls_ms" in *N|"") _ls_ms=$(( $(date +%s) * 1000 )) ;; *) _ls_ms=$((_ls_ms / 1000000)) ;; esac
}

_ls_start_of() {
  _ls_st=$(LC_ALL=C TZ=UTC ps -o lstart= -p "$1" 2>/dev/null) || _ls_st=
  if [ -n "$_ls_st" ]; then LC_ALL=C TZ=UTC date -j -f '%a %b %e %T %Y' "$_ls_st" +%s 2>/dev/null || echo 0; else echo 0; fi
}

# _ls_ev <ev> <kind>: appends the event; acquire carries waitMs (since _ls_t0), release carries holdMs (since the acquire)
_ls_ev() {
  [ -n "${_ls_ef:-}" ] || return 0
  _ls_now
  {
    if [ "$1" = acquire ]; then _ls_f=waitMs; _ls_ed=$((_ls_ms - ${_ls_t0:-$_ls_ms})); _ls_acq=$_ls_ms
    else _ls_f=holdMs; _ls_ed=$((_ls_ms - ${_ls_acq:-$_ls_ms})); fi
    mkdir -p "${_ls_ef%/*}"
    printf '{"ts":%s,"lock":"lake-slot","ev":"%s","kind":"%s","pid":%s,"start":%s,"slot":%s,"%s":%s}\n' "$_ls_ms" "$1" "$2" "$$" \
      "$(_ls_start_of "$$")" "${LAKE_SLOT:-0}" "$_ls_f" "$_ls_ed" >> "$_ls_ef"
  } 2>/dev/null || :
}

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

# _ls_hold <root> <kind>: takes a slot on fd 9 of the calling shell and exports LAKE_SLOT; returns 1 when it runs without one
_ls_hold() {
  _ls_c=
  _ls_d=${LAKE_SLOT_DIR:-}
  if [ -z "$_ls_d" ]; then
    if [ -d "$1/.git" ]; then _ls_c=$1/.git
    elif [ -f "$1/.git" ] && read -r _ _ls_g < "$1/.git" && case $_ls_g in /*) ;; *) _ls_g=$1/$_ls_g ;; esac &&
      [ -f "$_ls_g/commondir" ] && read -r _ls_c < "$_ls_g/commondir"; then
      case $_ls_c in /*) ;; *) _ls_c=$_ls_g/$_ls_c ;; esac
    else
      _ls_c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    fi
    _ls_d=$_ls_c/lake-slot
  fi
  _ls_ef=${FW_LOCK_EVENTS_FILE:-}
  if [ -z "$_ls_ef" ] && [ -n "$_ls_c" ] && [ -z "${CI:-}" ]; then
    _ls_m=$(cd "$_ls_c/.." 2>/dev/null && pwd -P) && _ls_ef=$_ls_m/.fw-console/locks.jsonl
  fi
  [ "${FW_LOCK_EVENTS:-on}" != off ] || _ls_ef=
  if [ -n "$_ls_ef" ]; then _ls_now; _ls_t0=$_ls_ms; fi
  if command -v lockf >/dev/null 2>&1; then _ls_l=lockf
  elif command -v flock >/dev/null 2>&1; then _ls_l=flock
  else echo "lake-slot: no lockf or flock on PATH; running without a slot" >&2; return 1; fi
  [ -d "$_ls_d" ] || mkdir -p "$_ls_d"
  if ! _ls_take "$_ls_d" 0; then
    echo "lake-slot: all $_ls_i slots busy; waiting for one" >&2
    if [ -r "$1/scripts/span.sh" ]; then . "$1/scripts/span.sh"; else span() { shift 2; "$@"; }; fi
    span lake-slot wait _ls_wait "$_ls_d"
    echo "lake-slot: got slot $_ls_i" >&2
  fi
  export LAKE_SLOT="$_ls_i"
  _ls_ev acquire "${2:-build}"
  if [ "$_ls_p" != full ]; then export LEAN_NUM_THREADS="$_ls_p"; echo "lake-slot: slot $_ls_i, pool $_ls_p" >&2; fi
}

lake_slot() {
  _ls_r=$1; shift
  [ -z "${LAKE_SLOT:-}" ] || exec "$@"
  . "$_ls_r/packages/contracts/golden/sched/lake-slot.gen.sh"
  _ls_hold "$_ls_r" build || :
  if [ -n "${LAKE_SLOT:-}" ] && [ -n "${_ls_ef:-}" ]; then
    "$@" && _ls_rc=0 || _ls_rc=$?
    _ls_ev release build
    exit "$_ls_rc"
  fi
  exec "$@"
}

# lake_slot_hold <root>: takes a slot for the calling shell and its children (none when LAKE_SLOT is set) and sets
# LAKE_SLOT_WIDTH to the slot's job count on this machine's online cores, LAKE_SLOT_CORES if set (Lean
# Fw.Sched.LakeSlot.stage2Width); lake_slot_release frees a slot it took.
lake_slot_hold() {
  . "$1/packages/contracts/golden/sched/lake-slot.gen.sh"
  _ls_own=
  if [ -z "${LAKE_SLOT:-}" ] && _ls_hold "$1" group; then _ls_own=1; fi
  LAKE_SLOT_WIDTH=1; _ls_k=0
  for _ls_x in $LAKE_SLOT_WIDTHS; do
    [ "$_ls_k" != "${LAKE_SLOT:-0}" ] || LAKE_SLOT_WIDTH=$_ls_x
    _ls_k=$((_ls_k + 1))
  done
  _ls_c=${LAKE_SLOT_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
  [ "$_ls_c" -ge 1 ] || _ls_c=1
  [ "$_ls_c" -ge "$LAKE_SLOT_WIDTH" ] || LAKE_SLOT_WIDTH=$_ls_c
}

# lake_slot_gate <fifo path>: opens fd 8 holding LAKE_SLOT_WIDTH tokens; lake_slot_run <cmd...> waits for a token, starts
# the command in the background ($! is its pid) and puts the token back when the command ends
lake_slot_gate() {
  mkfifo "$1" && exec 8<>"$1" && rm -f "$1"
  _ls_k=0
  while [ "$_ls_k" -lt "$LAKE_SLOT_WIDTH" ]; do printf '\n'; _ls_k=$((_ls_k + 1)); done >&8
}

lake_slot_run() {
  read -r _ls_t <&8
  ( "$@"; _ls_rc=$?; printf '\n' >&8; exit "$_ls_rc" ) &
}

lake_slot_release() {
  exec 8>&-
  [ -z "${_ls_own:-}" ] || { _ls_ev release group; exec 9>&-; unset LAKE_SLOT; _ls_own=; }
}
