# slot-mem-avail handoff

State: branch `worktree-wf_bfa7cd8f-3b3-1`, main merged at 36cee29a; the handoff commit follows it.

Done and verified (check.sh green, runner tests 2398/2398 with typecheck, ci-paths 54/54):
- Lean `Fw.Sup.Adapt`: `Mem`, `availMB` (free + speculative + purgeable + file cache above `fileMinMB`), `swapFull`
  (75 %), `thrash` (1500 MB/min), `memLow`, `vmNext` (compression rate from the `Compressions` counter, 5..600 s).
  Verdict waits `memLow` before the fit check. Theorems: `admit_fits`, `admit_calm`, `threads_fit`, `memLow_antitone`,
  `verdict_antitone` (needs `leanProcMB ≤ simMB`), `verdict_admit_memLow`.
- Goldens `packages/contracts/golden/sup/adapt.jsonl` (ops `adapt.memLow`, `adapt.vmNext`; 24 ops), replayed by
  `apps/runner/test/slot.test.ts` against `slot-core.ts`.
- `slot.ts` probe: `parseVmStat`, `parseSysctl`, `memOf`, `markNext` (mark in `<slot dir>/vm-mark.json`). Tested on
  fixtures `apps/runner/test/fixtures/vm_stat-{busy,busy-next,idle}.txt`: busy pair gives 1754 MB available, 5309 MB/min.
- `fw slot status` prints available, pressure, swap used/total, compression; `admit --kind build` reads availMB.

MEASURED on this Mac (2026-10-22 06:30:26, `fw slot status --json` then `vm_stat` + `sysctl` within 1 s):

| reading | free | spec | purg | file | fileMin | availMB | press | swap |
|---|---|---|---|---|---|---|---|---|
| slot probe | 159 | 36 | 31 | 5764 | 4462 | 1528 | 1 | 3450/5120 |
| vm_stat by hand | 379 | 35 | 31 | 5761 | 4462 | 1744 | 1 | 3450/5120 |

The 216 MB gap is free pages that moved between the two reads. The old probe (`memory_pressure`, 76 % at 06:30:31)
would have read about 12451 MB.

Open: thresholds (floor 1024 MB, swap 75 %, 1500 MB/min) stay INFERRED until replayed on sup-sampler-avail data;
macOS only (elsewhere Node's free memory, pressure 1); probe parsing is glue tested on fixtures.
Read first: `docs/team/tools/slot.md` (Available memory, Memory low), then `lean/Fw/Sup/Adapt.lean` (`memLow`).
