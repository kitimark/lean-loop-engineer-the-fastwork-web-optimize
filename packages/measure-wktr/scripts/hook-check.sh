#!/bin/sh
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
