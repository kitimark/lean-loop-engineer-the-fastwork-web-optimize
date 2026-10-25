#!/bin/sh
# Archive symbol check of the toolbar gate (task toolbar-wktr-gate): do the UI-script hooks the gate calls exist in the pinned
# WebKitTestRunner binary? Counts the demangled symbols of the arm64 slice, one JSON object {symbol: count}, and prints it.
#   hook-check.sh <WebKitTestRunnerApp binary> <out.json>
# The names are src/gate.mjs HOOK_SYMBOLS (UIScriptControllerIOS.mm:1486-1494, UIScriptControllerCocoa.mm:683-692@862f17d).
set -eu
bin=${1:?binary}; out=${2:?out json}
syms=$(nm -arch arm64 "$bin" | c++filt)
n=0
printf '{' > "$out"
for s in \
  'WTR::UIScriptControllerIOS::beginInteractiveObscuredInsetsChange' \
  'WTR::UIScriptControllerIOS::endInteractiveObscuredInsetsChange' \
  'WTR::UIScriptControllerCocoa::setObscuredInsets'; do
  c=$(printf '%s\n' "$syms" | grep -cF "$s" || true)
  [ "$n" -eq 0 ] || printf ',' >> "$out"
  printf '"%s":%s' "$s" "$c" >> "$out"
  n=$((n + 1))
done
printf '}\n' >> "$out"
cat "$out"
