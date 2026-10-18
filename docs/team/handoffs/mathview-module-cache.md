# mathview-module-cache (handoff)

**State:** the per-module math-view cache is on the worktree branch (base main aa84eb6). Files: lean/MathView.lean,
lean/MathViewMain.lean (`cachedEntries`, `modKeyOf`, `toolHash`), lean/scripts/mathview-cached.sh (store + `--diff`),
and the `mathview-differential` job in .github/workflows/lean.yml.
**Design:** K(m) = `MathView.modKey` over (m, blob of m's .olean[.server/.private], t, [K(i) for each Fw import i]).
t = hash of the tool sources embedded by `include_str` (MathView*.lean, Fw/Spec/AxReach.lean) plus lean-toolchain,
lake-manifest.json and lakefile.toml. The store is `<git common dir>/mathview-cache/mod/<K>.json`, written as tmp then
rename. Hits are read, misses are exported with `entries (want := miss)`, then merged and sorted by `Entry.before`
(total order: module, line, name). The lint always runs on the merged entries, so only entries are cached.
The whole-tree key stays as the fast path (.lake/mathview-cache, which scripts/math-pending.mjs reads).
**Deviations from the task text:** the blob is the .olean, not the source (it also covers code that elaboration
generates); lint lines are recomputed rather than stored (every rule is per-entry and takes about 0.4 s).

**Cone-locality per rule (premise of `Fw.Console.LandSpeed.lint_modular`)**
- lintEntry / ShadowLint / WhereLint + warnOnly / warnEntry: functions of one entry and its module name. Local.
- Export with loadExts := false: extension states stay initial (Lean/Environment.lean:2428-2433). Map/Tag lookups read
  only the declaring module's entries (EnvExtension.lean:118-122,163-170). Local.
- NON-LOCAL, fixed: `findDocString?` (DocString.lean:35) appends the tactic_extension / recommended_spelling text,
  which it scans from all modules (Parser/Term/Doc.lean:60-68, Parser/Tactic/Doc.lean:250-258). This was MEASURED with
  the probe. Now `findSimpleDocString?` is used, and today's export is byte-identical.
- NON-LOCAL, in t: the axiom rule runs Fw.Spec.AxReach code, which lies outside every Fw cone; it enters t through
  include_str. Errors from the heartbeat limit are not stored (`storable`). The summary counts are global and are
  recomputed on every run.
- INFERRED: an `eq_def` realized from a downstream module is content-deterministic.

**Tests:** CI job `mathview-differential`, cold and warm, plus 3 mutations: m1 a leaf docstring (2 misses);
m2 AxReach outside LandSpeed's cone (all modules miss); m3 recommended_spelling in Fw (1 miss, no suffix). Each
asserts full == cached minus heartbeats. All three were MEASURED identical locally.
**MEASURED local (load ~19):** one-module edit through the wrapper took 10.4 s before (full lint) and 3.4 s after
(119 hits, 2 misses). A warm store with no edit takes 2.7 s.
**Open:** isInstance is always false under loadExts := false (pre-existing; the same in full and cached runs). There
is no grep gate that forbids `findDocString?` (check-partial.sh is outside my writes). math-pending.mjs could use the
module store.
**Read first:** MathViewMain.lean "Module cache" note, then `cachedEntries`; research/notes/2026/10-18-land-speed.md P2.
