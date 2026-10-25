# span.sh: source it from a POSIX sh script, then `span <tool> <step> <command...>` runs the command and appends one
# JSON line to .fw-console/timings.jsonl of the main checkout (same schema as apps/runner/src/timing.ts; docs/team/tools/timings.md).
#   . "$(dirname "$0")/../../scripts/span.sh"     # path to this file
#   span lean/check "lake build" lake build
# The command's exit status is returned unchanged. Recording never fails the step: any error is swallowed.
# Cost: two `date` spawns per step (no git, no node); commit and load are read once, when this file is sourced.
# No paths, no user names in the line. FW_TIMINGS_FILE overrides the file (tests); FW_TIMINGS=off disables.
# span_more: JSON members the command sets for its own line (`,"slot":{"width":2,"jobs":30}`), cleared after each line.

_span_now() { _t=$(date +%s%N 2>/dev/null); case "$_t" in *N|"") _t=$(( $(date +%s) * 1000 )) ;; *) _t=$((_t / 1000000)) ;; esac; }

_span_file=${FW_TIMINGS_FILE:-}
if [ -z "$_span_file" ] && [ "${FW_TIMINGS:-on}" != off ]; then
  _g=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [ -n "$_g" ] && _span_file=$(dirname "$_g")/.fw-console/timings.jsonl
fi
[ -n "$_span_file" ] && { mkdir -p "${_span_file%/*}" 2>/dev/null || _span_file=; }
_span_commit=$(git rev-parse --short=7 HEAD 2>/dev/null || true)
if [ -r /proc/loadavg ]; then _span_load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || true)
else _span_load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}' || true); fi
case "${_span_load:-}" in ''|*[!0-9.]*) _span_load=0 ;; esac
if [ -n "${CI:-}" ]; then _span_host=ci; else _span_host=local; fi

span() {
  _tool=$1; _step=$2; shift 2
  _span_now; _s=$_t
  if "$@"; then _rc=0; else _rc=$?; fi
  _span_now; _e=$_t
  [ -z "${span_more_file:-}" ] || span_more="${span_more:-}$(cat "$span_more_file" 2>/dev/null || true)"
  span_more_file=
  if [ -n "$_span_file" ]; then
    {
      printf '{"tool":"%s","step":"%s","startMs":%s,"durMs":%s,"exit":%s,"commit":"%s","load":%s,"host":"%s"%s}\n' \
        "$_tool" "$_step" "$_s" "$((_e - _s))" "$_rc" "$_span_commit" "$_span_load" "$_span_host" "${span_more:-}" >> "$_span_file"
    } 2>/dev/null || true
  fi
  span_more=
  return "$_rc"
}
