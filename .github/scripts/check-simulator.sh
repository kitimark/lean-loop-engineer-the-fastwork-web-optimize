#!/bin/sh
# Fails fast unless the iOS Simulator runtime is the pinned build, then (with --create) makes the measurement device.
#   sh .github/scripts/check-simulator.sh [--create]
# Env: FW_IOS_VERSION (default 27.0), FW_IOS_BUILD (default 24A434, the build counts were first measured on),
#      FW_SIM_NAME (default fw-iphone-27, the name packages/measure-webkit looks for),
#      FW_SIM_DEVICE_TYPE (default iPhone 15 Pro Max).
# Glue only: no measurement decision. A different runtime build means different WebKit bytes, so the counts would be a
# different platform; stop here instead of producing them.
set -eu
ver=${FW_IOS_VERSION:-27.0}
build=${FW_IOS_BUILD:-24A434}
name=${FW_SIM_NAME:-fw-iphone-27}
dtype=${FW_SIM_DEVICE_TYPE:-iPhone 15 Pro Max}

json=$(xcrun simctl list runtimes -j)
rt=$(printf '%s' "$json" | FW_V="$ver" FW_B="$build" node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
const all = j.runtimes.filter((r) => r.isAvailable);
console.error("available runtimes: " + (all.map((r) => `${r.name} (${r.buildversion})`).join(", ") || "none"));
const hit = all.filter((r) => r.version === process.env.FW_V && r.buildversion === process.env.FW_B && r.identifier.includes("SimRuntime.iOS-"));
if (hit.length !== 1) { console.error(`pinned runtime iOS ${process.env.FW_V} build ${process.env.FW_B} not found (${hit.length} matches)`); process.exit(1); }
process.stdout.write(hit[0].identifier);
') || { echo "FAIL: the iOS runtime is not the pinned build; not measuring" >&2; exit 1; }
echo "runtime ok: $rt (iOS $ver, build $build)"

[ "${1:-}" = "--create" ] || exit 0

# Exactly one device of that name, on the pinned runtime. A leftover device of the same name is removed first.
xcrun simctl delete "$name" 2>/dev/null || true
udid=$(xcrun simctl create "$name" "$dtype" "$rt")
echo "created $name ($dtype) on $rt"
printf '%s\n' "$udid" > "${RUNNER_TEMP:-/tmp}/fw-sim-udid.txt"
n=$(xcrun simctl list devices -j | FW_N="$name" node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
console.log(Object.values(j.devices).flat().filter((d) => d.name === process.env.FW_N).length);
')
[ "$n" = 1 ] || { echo "FAIL: expected one device named $name, found $n" >&2; exit 1; }
