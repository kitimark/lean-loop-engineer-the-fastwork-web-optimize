import Lean.Data.Json
import Fw.Sup.Adapt
import Fw.Sup.Nested
import Fw.Sup.SimRelease
import Fw.Sup.MeasureWindow

/-! Golden vectors of `Fw.Sup.Adapt` (`packages/contracts/golden/sup/adapt.jsonl`), replayed by apps/runner/test/slot.test.ts. -/
namespace Fw.Sup.Adapt

open Lean (Json ToJson toJson)

def paramsJson (p : Params) : Json :=
  Json.mkObj [("nMin", toJson p.nMin), ("nMax", toJson p.nMax), ("targetCenti", toJson p.targetCenti),
    ("highCenti", toJson p.highCenti), ("floorMB", toJson p.floorMB), ("headroomMB", toJson p.headroomMB),
    ("cmprsPct", toJson p.cmprsPct), ("swapRiseMBPerMin", toJson p.swapRiseMBPerMin), ("holdS", toJson p.holdS),
    ("leanProcMB", toJson p.leanProcMB), ("testMB", toJson p.testMB), ("landMB", toJson p.landMB),
    ("simMB", toJson p.simMB), ("otherMB", toJson p.otherMB), ("warmS", toJson p.warmS), ("ageS", toJson p.ageS),
    ("maxWaitS", toJson p.maxWaitS), ("leaseS", toJson p.leaseS), ("leaseMaxS", toJson p.leaseMaxS),
    ("simIdleS", toJson p.simIdleS), ("graceMs", toJson p.graceMs), ("simPollS", toJson p.simPollS),
    ("buildMB", toJson p.buildMB), ("agentsMax", toJson p.agentsMax), ("agentsAgeS", toJson p.agentsAgeS),
    ("swapOutMBPerMinMax", toJson p.swapOutMBPerMinMax), ("comprMBPerMinMax", toJson p.comprMBPerMinMax), ("rateMinS", toJson p.rateMinS),
    ("rateMaxS", toJson p.rateMaxS), ("measureMB", toJson p.measureMB)]

def memJson (m : Mem) : Json :=
  Json.mkObj [("freeMB", toJson m.freeMB), ("specMB", toJson m.specMB), ("purgMB", toJson m.purgMB),
    ("fileMB", toJson m.fileMB), ("fileMinMB", toJson m.fileMinMB), ("swapUsedMB", toJson m.swapUsedMB),
    ("swapTotalMB", toJson m.swapTotalMB), ("press", toJson m.press), ("comprMBPerMin", toJson m.comprMBPerMin),
    ("swapOutMBPerMin", toJson m.swapOutMBPerMin)]

def sampleJson (s : Sample) : Json :=
  Json.mkObj [("time", toJson s.time), ("loadCenti", toJson s.loadCenti), ("mem", memJson s.mem),
    ("ramMB", toJson s.ramMB), ("compressorMB", toJson s.compressorMB), ("cores", toJson s.cores)]

def markJson : Option VmMark → Json
  | none => .null
  | some m => Json.mkObj [("time", toJson m.time), ("count", toJson m.count), ("rate", toJson m.rate),
    ("swapCount", toJson m.swapCount), ("swapRate", toJson m.swapRate)]

def prevJson : Option (Nat × Nat) → Json
  | none => .null
  | some (t, mb) => Json.mkObj [("time", toJson t), ("swapUsedMB", toJson mb)]

def optJson : Option Nat → Json
  | none => .null
  | some n => toJson n

def ctlJson (c : Ctl) : Json :=
  Json.mkObj [("n", toJson c.n), ("lastChange", toJson c.lastChange), ("prev", prevJson c.prev)]

def entryJson (e : Entry) : Json :=
  Json.mkObj [("owner", .str e.owner), ("token", .str e.token), ("kind", .str e.kind.name), ("since", toJson e.since),
    ("till", toJson e.till), ("foot", toJson e.foot), ("leaseS", toJson e.leaseS)]

def entriesJson (es : List Entry) : Json := .arr (es.map entryJson).toArray

def whyFields : Why → List (String × Json)
  | .queued a => [("why", "queued"), ("ahead", toJson a)]
  | .older => [("why", "older")]
  | .full r l => [("why", "full"), ("running", toJson r), ("limit", toJson l)]
  | .simBusy => [("why", "simBusy")]
  | .drain o => [("why", "drain"), ("others", toJson o)]
  | .memory n r => [("why", "memory"), ("needMB", toJson n), ("roomMB", toJson r)]
  | .memLow a => [("why", "memLow"), ("availMB", toJson a)]
  | .simFirst => [("why", "simFirst")]
  | .pass => [("why", "pass")]
  | .gap n l => [("why", "gap"), ("needS", toJson n), ("leftS", toJson l)]
  | .unknown => [("why", "unknown")]
  | .measureBusy => [("why", "measureBusy")]

def verdictJson : Verdict → Json
  | .admit t f => Json.mkObj [("verdict", "admit"), ("threads", toJson t), ("footMB", toJson f)]
  | .wait w => Json.mkObj (("verdict", "wait") :: whyFields w)
  | .timeout w => Json.mkObj (("verdict", "timeout") :: whyFields w)

def keyJson : Option CacheKey → Json
  | none => .null
  | some k => Json.mkObj [("kind", .str k.kind.name), ("argv", .arr (k.argv.map Json.str).toArray), ("tree", .str k.tree),
    ("base", .str k.base)]

def line (name op : String) (req : List (String × Json)) (resp : Json) : String :=
  (Json.mkObj [("name", .str name), ("request", Json.mkObj (("op", .str op) :: req)), ("response", resp)]).compress

def tight : Params := { holdS := 0, nMax := 6 }

def tightJson : Json := Json.mkObj [("holdS", toJson tight.holdS), ("nMax", toJson tight.nMax)]

def busySample : Sample := { okSample with loadCenti := 3550 }

def busyWindow : Sample :=
  let m : Mem :=
    { freeMB := 217, specMB := 120, purgMB := 87, fileMB := 4986, fileMinMB := 3656, swapUsedMB := 3046,
      swapTotalMB := 4096, press := 1, comprMBPerMin := 5309 }
  { okSample with loadCenti := 6176, compressorMB := 3003, mem := m }

def stepCases : List (String × Bool × Ctl × Sample) :=
  [ ("quiet sample after the window: +1", false, { n := 2, lastChange := 0 }, okSample),
    ("quiet sample inside the window: unchanged", false, { n := 2, lastChange := 990 }, okSample),
    ("window just passed: +1", false, { n := 2, lastChange := 970 }, okSample),
    ("load at the high mark: halve", false, { n := 4, lastChange := 0 }, { okSample with loadCenti := 1600 }),
    ("load just below the high mark and above target: hold", false, { n := 3, lastChange := 0 },
      { okSample with loadCenti := 1599 }),
    ("load at target: hold", false, { n := 3, lastChange := 0 }, { okSample with loadCenti := 800 }),
    ("busy hour with the Simulator up (load 35.5): halve", false, { n := 4, lastChange := 0 }, busySample),
    ("free memory below the floor: halve, clamped to nMin", false, { n := 1, lastChange := 0 }, (okSample.withFree 1023)),
    ("free memory at the floor but no headroom: hold", false, { n := 2, lastChange := 0 }, (okSample.withFree 2000)),
    ("free memory exactly floor + headroom: +1", false, { n := 2, lastChange := 0 }, (okSample.withFree 3072)),
    ("compressor at 40 percent of RAM: halve", false, { n := 4, lastChange := 0 }, { okSample with compressorMB := 6554 }),
    ("compressor just below 40 percent: +1", false, { n := 2, lastChange := 0 }, { okSample with compressorMB := 6553 }),
    ("swap rising 100 MB in 5 s: halve", false, { n := 3, lastChange := 0, prev := some (995, 4900) }, okSample),
    ("swap rising just below the rate: +1", false, { n := 3, lastChange := 0, prev := some (940, 4489) }, okSample),
    ("swap static at 61 percent of dynamic swap: +1 (ratio not read)", false, { n := 3, lastChange := 0, prev := some (995, 5000) },
      okSample),
    ("swap shrinking: +1", false, { n := 3, lastChange := 0, prev := some (995, 6000) }, okSample),
    ("no previous reading: swap not read", false, { n := 3, lastChange := 0 },
      { okSample with mem := { okSample.mem with swapUsedMB := 6000 } }),
    ("at nMax: stays", false, { n := 4, lastChange := 0 }, okSample),
    ("above nMax (old state): clamped down", false, { n := 9, lastChange := 0 }, okSample),
    ("below nMin (old state): clamped up on hold", false, { n := 0, lastChange := 0 }, { okSample with loadCenti := 1000 }),
    ("no window, nMax 6: +1 at once", true, { n := 5, lastChange := 999 }, okSample),
    ("pressure level warning: halve", false, { n := 4, lastChange := 0 }, okSample.withMem { okSample.mem with press := 2 }),
    ("swap 75 percent full, nothing swapped out: +1", false, { n := 2, lastChange := 0 },
      okSample.withMem { okSample.mem with swapUsedMB := 6144 }),
    ("swapping out 64 MB a minute: halve", false, { n := 4, lastChange := 0 },
      okSample.withMem { okSample.mem with swapOutMBPerMin := 64 }),
    ("compressing 1500 MB a minute: halve", false, { n := 4, lastChange := 0 },
      okSample.withMem { okSample.mem with comprMBPerMin := 1500 }),
    ("file cache above its minimum counts as headroom: +1", false, { n := 2, lastChange := 0 },
      okSample.withMem { okSample.mem with freeMB := 300, fileMB := 5000, fileMinMB := 2228 }) ]

def stepLines : List String :=
  stepCases.map fun (nm, t, c, s) =>
    let p : Params := if t then tight else {}
    let c' := step p c s
    line nm "adapt.step" ((if t then [("params", tightJson)] else []) ++ [("ctl", ctlJson c), ("sample", sampleJson s)])
      (Json.mkObj [("ctl", ctlJson c'), ("signal", .str (signal p c.prev s).name)])

def liveH (o t : String) (k : Kind) (since foot : Nat) : Entry :=
  { owner := o, token := t, kind := k, since := since, till := 5000, foot := foot }

def oldTest : Entry := liveH "q" "7" .test 0 0

def verdictCases : List (String × Nat × Sample × List Entry × List Entry × Entry × Nat) :=
  let me := tk "a" "1" .check 990
  let sim := tk "s" "5" .sim 995
  [ ("idle machine, check: threads from free memory", 2, okSample, [], [me], me, 0),
    ("check with little room: one Lean worker", 2, (okSample.withFree 1800), [], [me], me, 0),
    ("check, one worker does not fit, a job runs: memory", 2, (okSample.withFree 1700), [oldTest], [me], me, 0),
    ("check, room for exactly one worker", 2, (okSample.withFree 1724), [], [me], me, 0),
    ("16 GB free on 8 cores: threads capped at the cores", 2, (okSample.withFree 16000), [], [me], me, 0),
    ("same kind ahead: queued", 2, okSample, [], [tk "b" "2" .check 980, me], me, 0),
    ("two of the same kind ahead: queued 2", 2, okSample, [], [tk "b" "2" .check 980, tk "c" "3" .check 985, me], me, 0),
    ("other kind ahead, young: no wait for it", 2, okSample, [], [tk "b" "2" .test 980, me], me, 0),
    ("other kind ahead, waited ageS: older", 2, okSample, [], [tk "b" "2" .test 700, me], me, 0),
    ("other kind ahead, one second short of ageS", 2, okSample, [], [tk "b" "2" .test 701, me], me, 0),
    ("old sim ticket blocked by a sim holder: check is not held back", 4, { okSample.withFree 12000 with loadCenti := 300 },
      [liveH "x" "9" .sim 0 2800], [tk "s" "5" .sim 600, me], me, 0),
    ("old sim ticket blocked by a sim holder: the sim ticket waits simBusy", 4, { okSample.withFree 12000 with loadCenti := 300 },
      [liveH "x" "9" .sim 0 2800], [tk "s" "5" .sim 600, me], tk "s" "5" .sim 600, 0),
    ("old sim ticket, Simulator free: older", 4, { okSample.withFree 12000 with loadCenti := 300 }, [],
      [tk "s" "5" .sim 600, me], me, 0),
    ("holders at N: full", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 0),
    ("expired holder does not count", 1, okSample, [{ liveH "x" "9" .test 0 0 with till := 1000 }], [me], me, 0),
    ("N 0: full with no holder", 0, okSample, [], [me], me, 0),
    ("sim asked while a live sim holder runs: simBusy", 3, okSample, [liveH "x" "9" .sim 0 2800],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim asked, expired sim holder: admit", 3, okSample, [{ liveH "x" "9" .sim 0 2800 with till := 999 }],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim needs 2800 MB plus the floor, a job runs: memory", 3, (okSample.withFree 3823), [oldTest],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim exactly fits", 3, (okSample.withFree 3824), [], [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("test beside a warming check holder is charged", 3, (okSample.withFree 6000), [liveH "x" "9" .check 980 4200],
      [tk "a" "1" .test 990], tk "a" "1" .test 990, 0),
    ("test beside a warm (old) check holder is not charged", 3, (okSample.withFree 6000), [liveH "x" "9" .check 900 4200],
      [tk "a" "1" .test 990], tk "a" "1" .test 990, 0),
    ("land needs 1500 MB, a job runs: memory", 3, (okSample.withFree 2523), [oldTest], [tk "a" "1" .land 990],
      tk "a" "1" .land 990, 0),
    ("other needs 1000 MB", 3, (okSample.withFree 2024), [], [tk "a" "1" .other 990], tk "a" "1" .other 990, 0),
    ("waited just below the limit: wait", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 1799),
    ("waited the limit: timeout, never run", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 1800),
    ("waited the limit but admissible: admit", 2, okSample, [], [me], me, 9999),
    ("ticket missing from the queue: every same-kind ticket is ahead", 2, okSample, [], [tk "b" "2" .check 980], me, 0),
    ("sim pending: a check that leaves less than the sim footprint waits simFirst", 4, okSample, [],
      [me, tk "s" "5" .sim 995], me, 0),
    ("sim pending: a check that leaves the sim footprint is admitted", 4, (okSample.withFree 12000), [],
      [me, tk "s" "5" .sim 995], me, 0),
    ("sim pending: the check leaves no slot for it (N 1): simFirst", 1, (okSample.withFree 12000), [],
      [me, tk "s" "5" .sim 995], me, 0),
    ("sim pending: N 2 leaves one slot for it: admit", 2, (okSample.withFree 12000), [],
      [me, tk "s" "5" .sim 995], me, 0),
    ("sim pending: another job already runs: simFirst", 4, (okSample.withFree 12000), [liveH "x" "9" .test 0 0],
      [me, tk "s" "5" .sim 995], me, 0),
    ("sim pending, plain memory short, a job runs: memory first", 4, (okSample.withFree 1700), [oldTest],
      [me, tk "s" "5" .sim 995], me, 0),
    ("pressure level warning, no holder: the head runs", 2, okSample.withMem { okSample.mem with press := 2 }, [], [me], me,
      0),
    ("pressure level warning, a job runs: memLow", 2, okSample.withMem { okSample.mem with press := 2 }, [oldTest], [me], me,
      0),
    ("pressure level critical, no holder: memLow", 2, okSample.withMem { okSample.mem with press := 4 }, [], [me], me, 0),
    ("the incident of 2026-10-24: 103 MB available, pressure 2, not compressing, not swapping: the head runs", 2,
      okSample.withMem { freeMB := 103, press := 2 }, [], [me], me, 0),
    ("the incident of 2026-10-24: 151 MB available, pressure 2, compressing 2164 MB a minute: memLow", 2,
      okSample.withMem { freeMB := 151, press := 2, comprMBPerMin := 2164 }, [], [me], me, 0),
    ("swap 75 percent full, nothing swapped out: admit", 2, okSample.withMem { okSample.mem with swapUsedMB := 6144 }, [],
      [me], me, 0),
    ("swapping out 64 MB a minute: memLow", 2, okSample.withMem { okSample.mem with swapOutMBPerMin := 64 }, [], [me], me,
      0),
    ("compressing 1500 MB a minute: memLow", 2, okSample.withMem { okSample.mem with comprMBPerMin := 1500 }, [], [me], me, 0),
    ("available just under the floor, a job runs: memLow", 2, okSample.withFree 1023, [oldTest], [me], me, 0),
    ("the stall of 2026-10-22, no holder: the queue head runs one Lean worker", 2, stallSample, [], [me], me, 0),
    ("the stall of 2026-10-22, one holder: memLow", 2, stallSample, [oldTest], [me], me, 0),
    ("the stall, the second ticket of the same kind: queued", 2, stallSample, [], [me, tk "b" "2" .check 991],
      tk "b" "2" .check 991, 0),
    ("the stall, expired holder does not count: the head runs", 2, stallSample, [{ oldTest with till := 1000 }], [me], me, 0),
    ("the stall, swapping out 64 MB a minute: memLow", 2, stallSample.withMem { stallMem with swapOutMBPerMin := 64 }, [],
      [me], me, 0),
    ("the stall, pressure level warning, no holder: the head runs", 2, stallSample.withMem { stallMem with press := 2 }, [], [me], me, 0),
    ("the stall, compressing 1500 MB a minute: memLow", 2, stallSample.withMem { stallMem with comprMBPerMin := 1500 }, [],
      [me], me, 0),
    ("the stall, a sim ticket behind the check: simFirst", 4, stallSample, [], [me, sim], me, 0),
    ("the stall, that sim ticket: the head of its kind runs", 4, stallSample, [], [me, sim], sim, 0),
    ("no holder, sim short of memory: the head runs", 3, (okSample.withFree 3823), [], [tk "a" "1" .sim 990],
      tk "a" "1" .sim 990, 0),
    ("available just under the floor, no holder: the head runs", 2, okSample.withFree 1023, [], [me], me, 0),
    ("a sim ticket under pressure waits memLow", 3, okSample.withMem { okSample.mem with press := 4 }, [],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("busy window (MEASURED, 03:18:44): memLow on compression, not 8 workers", 2, busyWindow, [], [me], me, 0),
    ("busy window without compression: one Lean worker", 2, busyWindow.withMem { busyWindow.mem with comprMBPerMin := 0 },
      [], [me], me, 0),
    ("sim held: a second job beside it waits simFirst", 4, (okSample.withFree 12000),
      [liveH "x" "9" .sim 0 2800, liveH "y" "8" .test 0 0], [me], me, 0),
    ("sim held, nothing else runs: one check beside it", 4, (okSample.withFree 12000), [liveH "x" "9" .sim 0 2800],
      [me], me, 0),
    ("sim ticket, two other jobs run: drain", 4, (okSample.withFree 12000),
      [liveH "x" "9" .test 0 0, liveH "y" "8" .land 0 0], [tk "s" "5" .sim 990], tk "s" "5" .sim 990, 0),
    ("sim ticket, one other job runs: admit", 4, (okSample.withFree 12000), [liveH "x" "9" .test 0 0],
      [tk "s" "5" .sim 990], tk "s" "5" .sim 990, 0),
    ("sim ticket behind an old test ticket: never older", 4, (okSample.withFree 12000), [],
      [tk "b" "2" .test 600, tk "s" "5" .sim 990], tk "s" "5" .sim 990, 0),
    ("old sim lock held: a sim ticket waits simBusy", 4, (okSample.withFree 12000), withLegacy 1000 true [],
      [tk "s" "5" .sim 990], tk "s" "5" .sim 990, 0),
    ("old sim lock held, nothing else runs: one check beside it", 4, (okSample.withFree 12000), withLegacy 1000 true [],
      [me], me, 0),
    ("old sim lock held, a test runs: the check waits simFirst", 4, (okSample.withFree 12000),
      withLegacy 1000 true [liveH "y" "8" .test 0 0], [me], me, 0) ]

def verdictLines (p : Params := {}) : List String :=
  verdictCases.map fun (nm, n, s, hs, q, me, w) =>
    line nm "adapt.verdict" [("n", toJson n), ("sample", sampleJson s), ("holders", entriesJson hs), ("queue", entriesJson q),
      ("me", entryJson me), ("waited", toJson w)] (verdictJson (verdict p n s hs q me w))

def threadsCases : List (Nat × Nat) := [(8, 0), (8, 699), (8, 700), (8, 1400), (8, 4976), (8, 100000), (0, 5000), (1, 5000)]

def threadsLines : List String :=
  threadsCases.map fun (c, r) =>
    line s!"threads cores={c} roomMB={r}" "adapt.threads" [("cores", toJson c), ("roomMB", toJson r)]
      (Json.mkObj [("threads", toJson (leanThreads {} c r))])

def idleMem : Mem :=
  { freeMB := 723, specMB := 40, purgMB := 10, fileMB := 6223, fileMinMB := 4545, swapUsedMB := 3466, swapTotalMB := 5120 }

def memLines : List String :=
  let av := fun (nm : String) (m : Mem) =>
    line nm "adapt.memLow" [("mem", memJson m)]
      (Json.mkObj [("availMB", toJson (availMB m)), ("swapActive", .bool (swapActive {} m)), ("thrash", .bool (thrash {} m)),
        ("memLow", .bool (memLow {} m))])
  let vn := fun (nm : String) (prev : Option VmMark) (now count swapCount pageB : Nat) =>
    line nm "adapt.vmNext" [("prev", markJson prev), ("now", toJson now), ("count", toJson count),
      ("swapCount", toJson swapCount), ("pageB", toJson pageB)]
      (Json.mkObj [("mark", markJson (some (vmNext {} prev now count swapCount pageB)))])
  [ av "busy window: 1754 MB available, thrashing" busyWindow.mem,
    av "file cache under its minimum adds nothing" { freeMB := 100, fileMB := 2000, fileMinMB := 3000 },
    av "idle: free, speculative, purgeable and file cache above its minimum" idleMem,
    av "no swap file" { freeMB := 4000, swapUsedMB := 10, swapTotalMB := 0 },
    av "swap 75 percent full, nothing swapped out: not low" { freeMB := 4000, swapUsedMB := 3072, swapTotalMB := 4096 },
    av "swapping out 64 MB a minute" { freeMB := 4000, swapOutMBPerMin := 64 },
    av "swapping out 63 MB a minute" { freeMB := 4000, swapOutMBPerMin := 63 },
    av "the stall of 2026-10-22: 281 MB available, low" stallMem,
    av "pressure critical" { freeMB := 4000, press := 4 },
    av "pressure unread (0) counts as not normal" { freeMB := 4000, press := 0 },
    av "available exactly the floor" { freeMB := 1000, specMB := 24 },
    vn "first reading: rates 0" none 100 5 7 16384,
    vn "11 s later: growth per minute" (some ⟨100, 1701467470, 0, 13043114, 0⟩) 111 1701529764 13043114 16384,
    vn "30 s later: 2048 pages swapped out, 64 MB a minute" (some ⟨100, 10, 7, 0, 0⟩) 130 10 2048 16384,
    vn "the stall of 2026-10-22: no swap-out in 30 s" (some ⟨100, 10, 0, 13043114, 0⟩) 130 10 13043114 16384,
    vn "4 s later: mark and rates kept" (some ⟨100, 10, 7, 3, 9⟩) 104 99999 99 16384,
    vn "exactly rateMinS later: new rates" (some ⟨100, 10, 7, 3, 9⟩) 105 74 67 16384,
    vn "older than rateMaxS: rates 0" (some ⟨100, 10, 7, 3, 9⟩) 701 99999 99 16384,
    vn "exactly rateMaxS later: new rates" (some ⟨100, 10, 7, 3, 9⟩) 700 6410 6403 16384,
    vn "counters went back (reboot): rates 0" (some ⟨100, 500, 7, 500, 9⟩) 160 10 10 16384,
    vn "only the swap counter went back: swap rate 0" (some ⟨100, 10, 7, 500, 9⟩) 160 74 10 16384 ]

def holdB : Entry := { owner := "b", token := "t2", kind := .test, since := 0, till := 60, leaseS := 60 }

def simGrant : Entry := grant {} holdA 0 1800 2800

def leaseLines : List String :=
  let es := [holdA, holdB]
  let pr := fun (nm : String) (now : Nat) =>
    line nm "adapt.prune" [("now", toJson now), ("entries", entriesJson es)] (Json.mkObj [("entries", entriesJson (prune now es))])
  let ex := fun (nm : String) (now : Nat) (es : List Entry) =>
    line nm "adapt.expired" [("now", toJson now), ("entries", entriesJson es)]
      (Json.mkObj [("entries", entriesJson (expired now es))])
  let rnIn := fun (nm : String) (now : Nat) (o t : String) (lease : Option Nat) (es : List Entry) =>
    line nm "adapt.renew" [("now", toJson now), ("owner", .str o), ("token", .str t), ("lease", optJson lease),
      ("entries", entriesJson es)]
      (Json.mkObj [("entries", match renew {} now o t lease es with | some r => entriesJson r | none => .null)])
  let rn := fun (nm : String) (now : Nat) (o t : String) (lease : Option Nat) => rnIn nm now o t lease es
  let gr := fun (nm : String) (now lease foot : Nat) =>
    line nm "adapt.grant" [("me", entryJson holdB), ("now", toJson now), ("lease", toJson lease), ("foot", toJson foot)]
      (Json.mkObj [("entry", entryJson (grant {} holdB now lease foot))])
  let lo := fun (nm : String) (stored : Option Nat) (since till : Nat) =>
    line nm "adapt.leaseOr" [("stored", optJson stored), ("since", toJson since), ("till", toJson till)]
      (Json.mkObj [("leaseS", toJson (leaseOr stored since till))])
  let rl := fun (nm : String) (o t : String) =>
    line nm "adapt.release" [("owner", .str o), ("token", .str t), ("entries", entriesJson es)]
      (Json.mkObj [("entries", entriesJson (release o t es))])
  [ pr "both live" 59, pr "one lease ends at 60" 60, pr "both expired" 100,
    ex "both live: no expire" 59 es, ex "one lease ends at 60: one expire" 60 es, ex "both expired: two expire" 100 es,
    ex "a duplicated expired entry: one expire each" 100 [holdA, holdA], ex "no entries" 5 [],
    rn "own live lease renewed" 50 "a" "t1" (some 600), rn "lease capped at leaseMaxS" 50 "a" "t1" (some 99999),
    rn "no length keeps the granted 100 s" 50 "a" "t1" none, rn "no length keeps the other holder's 60 s" 30 "b" "t2" none,
    rnIn "sim lease of 1800 s renewed after 1192 s with no length keeps 1800 s" 1192 "a" "t1" none [simGrant],
    rnIn "sim lease renewed with a length sets it" 1192 "a" "t1" (some 60) [simGrant],
    rn "wrong token refused" 50 "a" "t9" (some 600), rn "another owner refused" 50 "b" "t1" (some 600),
    rn "expired lease refused" 100 "a" "t1" (some 600), rn "expired lease refused with no length" 100 "a" "t1" none,
    rn "lease at its last second renewed" 99 "a" "t1" (some 60),
    gr "grant stores the requested length" 10 1800 2800, gr "grant caps at leaseMaxS" 10 99999 0,
    lo "stored length wins" (some 30) 0 100, lo "legacy entry: its whole span" none 40 100,
    rl "own entry released" "a" "t1", rl "foreign release is a no-op" "a" "t2" ]

def simLines : List String :=
  let boot := fun (nm : String) (now : Nat) (o t : String) (hs : List Entry) =>
    line nm "adapt.simBoot" [("now", toJson now), ("owner", .str o), ("token", .str t), ("holders", entriesJson hs)]
      (Json.mkObj [("boot", .bool (simBoot now o t hs))])
  let act := fun (nm : String) (now : Nat) (hs : List Entry) (b l : Bool) (i : Option Nat) =>
    line nm "adapt.simAction" [("now", toJson now), ("holders", entriesJson hs), ("booted", .bool b), ("legacyHeld", .bool l),
      ("idleSince", optJson i)] (Json.mkObj [("action", .str (simAction {} now hs b l i).name)])
  let idle := fun (nm : String) (now : Nat) (h b : Bool) (prev : Option Nat) =>
    line nm "adapt.simIdleNext" [("now", toJson now), ("held", .bool h), ("booted", .bool b), ("prev", optJson prev)]
      (Json.mkObj [("idleSince", optJson (simIdleNext now h b prev))])
  let due := fun (nm : String) (now last : Nat) =>
    line nm "adapt.simDue" [("now", toJson now), ("last", toJson last)] (Json.mkObj [("due", .bool (simDue {} now last))])
  [ boot "slot owner boots" 50 "a" "t1" [holdA], boot "no slot: no boot" 50 "a" "t1" [],
    boot "another agent's slot: no boot" 50 "b" "t1" [holdA], boot "expired slot: no boot" 100 "a" "t1" [holdA],
    boot "a test slot does not allow a boot" 50 "b" "t2" [holdB],
    act "not booted: nothing" 5000 [] false false (some 0), act "live sim slot: keep" 50 [holdA] true false (some 0),
    act "old sim lock held: keep" 5000 [] true true (some 0), act "idle 599 s: keep" 1599 [] true false (some 1000),
    act "idle 600 s: shutdown" 1600 [] true false (some 1000), act "expired slot, idle: shutdown" 700 [holdA] true false (some 0),
    act "a live test slot does not keep the Simulator" 700 [{ holdB with till := 9999 }] true false (some 0),
    act "no idle clock yet: keep" 99999 [] true false none,
    idle "first unheld sighting starts the clock" 700 false true none, idle "the clock keeps its start" 900 false true (some 700),
    idle "a holder clears the clock" 900 true true (some 700), idle "no device booted clears the clock" 900 false false (some 700),
    due "first look (last 0)" 100 0, due "29 s after the last look: not due" 129 100, due "30 s after: due" 130 100 ]

def buildWhyFields : BuildWhy → List (String × Json)
  | .simWaits => [("why", "simWaits")]
  | .agentsUnknown => [("why", "agentsUnknown")]
  | .agents l m => [("why", "agents"), ("live", toJson l), ("max", toJson m)]
  | .memory f n => [("why", "memory"), ("availMB", toJson f), ("needMB", toJson n)]

def buildVerdictJson : BuildVerdict → Json
  | .admit => Json.mkObj [("verdict", "admit")]
  | .wait w => Json.mkObj (("verdict", "wait") :: buildWhyFields w)

def buildLines : List String :=
  let ad := fun (nm : String) (sw : Bool) (m : Nat) (a : Option Nat) =>
    line nm "adapt.admitBuild" [("simWaits", .bool sw), ("availMB", toJson m), ("agents", optJson a)]
      (buildVerdictJson (admitBuild {} sw m a))
  let seen := fun (nm : String) (now : Nat) (r : Option (Nat × Nat)) =>
    line nm "adapt.agentsSeen" [("now", toJson now), ("reading", match r with
        | none => .null
        | some (t, n) => Json.mkObj [("time", toJson t), ("live", toJson n)])]
      (Json.mkObj [("agents", optJson (agentsSeen {} now r))])
  let sq := fun (nm : String) (now : Nat) (q : List Entry) =>
    line nm "adapt.simQueued" [("now", toJson now), ("queue", entriesJson q)] (Json.mkObj [("queued", .bool (simQueued now q))])
  [ ad "quiet: admit" false 9000 (some 5), ad "a Simulator ticket waits" true 9000 (some 5),
    ad "no fresh agent count" false 9000 none, ad "8 live agents: wait" false 9000 (some 8), ad "7 live agents: admit" false 9000 (some 7),
    ad "free memory 1 MB short of floor + buildMB" false 3123 (some 7), ad "free memory exactly floor + buildMB" false 3124 (some 7),
    ad "busy window (free 400 MB, 9 agents): agents first" false 400 (some 9),
    seen "fresh reading" 1900 (some (1000, 6)), seen "reading 901 s old: unknown" 1901 (some (1000, 6)),
    seen "no reading" 1901 none,
    sq "live sim ticket" 99 [{ tk "s" "5" .sim 0 with till := 100 }], sq "expired sim ticket" 100 [{ tk "s" "5" .sim 0 with till := 100 }],
    sq "only a test ticket" 50 [tk "t" "6" .test 0] ]

def holdLines : List String :=
  let lg := fun (nm : String) (now : Nat) (l : Bool) (hs : List Entry) =>
    line nm "adapt.withLegacy" [("now", toJson now), ("legacy", .bool l), ("holders", entriesJson hs)]
      (Json.mkObj [("holders", entriesJson (withLegacy now l hs))])
  let ho := fun (nm : String) (now : Nat) (k : Kind) (hs : List Entry) =>
    line nm "adapt.heldOf" [("now", toJson now), ("kind", .str k.name), ("holders", entriesJson hs)]
      (Json.mkObj [("held", .bool (heldOf now hs k))])
  [ lg "old lock held: one more sim holder" 1000 true [holdB], lg "old lock free: unchanged" 1000 false [holdB],
    ho "live sim holder" 50 .sim [holdA, holdB], ho "expired sim holder" 100 .sim [holdA], ho "live test holder" 50 .test [holdB],
    ho "no holder" 50 .sim [] ]

def stopLines : List String :=
  let st := fun (nm : String) (a s : Bool) (tm : Option Nat) (now : Nat) =>
    line nm "adapt.stop" [("alive", .bool a), ("sameStart", .bool s), ("termAt", match tm with | some t => toJson t | none => .null),
      ("nowMs", toJson now)] (Json.mkObj [("action", .str (stopAct {} a s tm now).name)])
  [ st "alive, not yet signalled: TERM" true true none 0, st "inside the grace: wait" true true (some 1000) 5999,
    st "grace over, same process: KILL" true true (some 1000) 6000, st "pid reused: never signalled" true false (some 1000) 9000,
    st "exited: done" false true (some 1000) 9000, st "exited before TERM: done" false true none 0 ]

def cacheLines : List String :=
  let k := fun (nm : String) (kd : Kind) (argv : List String) (tree m : String) (c : Bool) =>
    line nm "adapt.cacheKey" [("kind", .str kd.name), ("argv", .arr (argv.map Json.str).toArray), ("tree", .str tree),
      ("mainSha", .str m), ("clean", .bool c)] (Json.mkObj [("key", keyJson (keyOf kd argv tree m c))])
  let hit := fun (nm : String) (r : CacheKey) (e : Nat) (q : Option CacheKey) =>
    line nm "adapt.cacheHit" [("recorded", keyJson (some r)), ("exit", toJson e), ("key", keyJson q)]
      (Json.mkObj [("hit", .bool (cacheHit r e q))])
  let t := ["pnpm", "--filter", "@fw/runner", "test"]
  let r : CacheKey := ⟨.test, t, "tree1", ""⟩
  let l : CacheKey := ⟨.land, ["pnpm", "-s", "fw", "land", "b", "--dry"], "tree1", "main1"⟩
  [ k "clean test key ignores main" .test t "tree1" "main1" true, k "dirty tree: no key" .test t "tree1" "main1" false,
    k "land key carries main" .land l.argv "tree1" "main1" true, k "check key ignores main" .check ["sh", "lean/scripts/check.sh"] "tree1" "m" true,
    hit "same argv, tree, passed: hit" r 0 (keyOf .test t "tree1" "main2" true),
    hit "recorded failure: miss" r 1 (keyOf .test t "tree1" "main1" true),
    hit "other tree: miss" r 0 (keyOf .test t "tree2" "main1" true),
    hit "other argv: miss" r 0 (keyOf .test ["pnpm", "test"] "tree1" "main1" true),
    hit "other kind: miss" r 0 (keyOf .check t "tree1" "main1" true),
    hit "dirty tree: miss" r 0 (keyOf .test t "tree1" "main1" false),
    hit "land, main moved: miss" l 0 (keyOf .land l.argv "tree1" "main2" true),
    hit "land, same main: hit" l 0 (keyOf .land l.argv "tree1" "main1" true) ]

open Fw.Sup.MeasureWindow in
def wparamsJson (wp : WParams) : Json :=
  Json.mkObj [("measureMaxS", toJson wp.measureMaxS), ("passMaxS", toJson wp.passMaxS), ("settleS", toJson wp.settleS),
    ("histMin", toJson wp.histMin), ("histN", toJson wp.histN)]

open Fw.Sup.MeasureWindow in
def windowJson (w : Window) : Json :=
  Json.mkObj [("owner", .str w.owner), ("token", .str w.token), ("deadline", toJson w.deadline),
    ("passTill", optJson w.passTill), ("next", toJson w.next)]

open Fw.Sup.MeasureWindow in
def owJson : Option Window → Json
  | none => .null
  | some w => windowJson w

open Fw.Sup.MeasureWindow in
def passJson : PassVerdict → Json
  | .start t => Json.mkObj [("pass", "start"), ("till", toJson t)]
  | .wait o => Json.mkObj [("pass", "wait"), ("others", toJson o)]
  | .gone => Json.mkObj [("pass", "gone")]

open Fw.Sup.MeasureWindow in
def rowJson (r : Row) : Json :=
  Json.mkObj [("step", .str r.step), ("durMs", toJson r.durMs), ("exit", optJson r.exit), ("host", .str r.host)]

open Fw.Sup.MeasureWindow in
set_option compiler.extract_closed false in
def windowLines (_ : Unit := ()) : List String :=
  let wp : WParams := {}
  let m := mH "m" "M" 1000 2000
  let ck := chk "a" "1" .check 1390
  let wv := fun (nm : String) (w : Option Window) (pred : Option Nat) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry)
      (waited : Nat) =>
    line nm "window.verdict" [("wparams", wparamsJson wp), ("window", owJson w), ("pred", optJson pred), ("n", toJson n),
      ("sample", sampleJson s), ("holders", entriesJson hs), ("queue", entriesJson q), ("me", entryJson me),
      ("waited", toJson waited)] (verdictJson (wverdict wp w pred {} n s hs q me waited))
  let ps := fun (nm : String) (w : Option Window) (now : Nat) (hs : List Entry) (o t : String) (forS : Nat) =>
    line nm "window.passStart" [("wparams", wparamsJson wp), ("window", owJson w), ("now", toJson now),
      ("holders", entriesJson hs), ("owner", .str o), ("token", .str t), ("forS", toJson forS)]
      (passJson (passStart wp w now hs o t forS))
  let pr := fun (nm : String) (wp' : WParams) (k : Kind) (rows : List Row) =>
    line nm "window.predict" [("wparams", wparamsJson wp'), ("kind", .str k.name), ("rows", .arr (rows.map rowJson).toArray)]
      (Json.mkObj [("predS", optJson (predict wp' k rows))])
  let cu := fun (nm : String) (now : Nat) (hs : List Entry) (w : Option Window) =>
    line nm "window.current" [("now", toJson now), ("holders", entriesJson hs), ("window", owJson w)]
      (Json.mkObj [("window", owJson (current now hs w))])
  let ed := fun (nm : String) (w : Window) (act : String) (now x : Nat) =>
    let r := if act == "begin" then begin w x else if act == "want" then want w now else stop w now x
    line nm "window.edit" [("window", windowJson w), ("act", .str act), ("now", toJson now), ("arg", toJson x)]
      (Json.mkObj [("window", windowJson r)])
  let rows : List Row := [⟨"slot run check", 61000, some 0, "local"⟩, ⟨"slot run check lake", 1500, some 0, "local"⟩,
    ⟨"slot run check lake cached", 10, some 0, "local"⟩, ⟨"slot run checker", 10, some 0, "local"⟩,
    ⟨"slot run check", 99000, some 1, "local"⟩, ⟨"slot run check", 7000, some 0, "ci"⟩, ⟨"slot run check", 7000, none, "local"⟩,
    ⟨"slot run check lake", 2001, some 0, "local"⟩, ⟨"slot run test", 40000, some 0, "local"⟩]
  [ line "default window parameters" "window.params" [] (wparamsJson wp),
    line "measure grant at 1000, gap 0" "window.open" [("wparams", wparamsJson wp), ("owner", .str "m"), ("token", .str "M"),
      ("now", toJson 1000), ("gapS", toJson 0)] (Json.mkObj [("window", windowJson wA)]),
    line "measure grant with a first gap of 300 s" "window.open" [("wparams", wparamsJson wp), ("owner", .str "m"),
      ("token", .str "M"), ("now", toJson 1000), ("gapS", toJson 300)] (Json.mkObj [("window", windowJson (openAt wp "m" "M" 1000 300))]),
    cu "holder live: window in force" 1100 [mH "m" "M" 1000 1200] (some wA),
    cu "holder of another token: none" 1100 [mH "m" "X" 1000 1200] (some wA),
    cu "holder of another owner: none" 1100 [mH "n" "M" 1000 1200] (some wA),
    cu "deadline reached: none" 6400 [mH "m" "M" 1000 7000] (some wA),
    cu "holder expired: none" 1300 [mH "m" "M" 1000 1200] (some wA),
    cu "no window" 1100 [mH "m" "M" 1000 1200] none,
    wv "pass live: a check waits" (some (begin wA 1300)) (some 10) 4 (s1 1100) [mH "m" "M" 1000 1600]
      [chk "a" "1" .check 1090] (chk "a" "1" .check 1090) 10,
    wv "pass live: a sim waits" (some (begin wA 1300)) (some 10) 4 (s1 1100) [mH "m" "M" 1000 1600]
      [chk "s" "5" .sim 1090] (chk "s" "5" .sim 1090) 10,
    wv "pass live past maxWait: refused" (some (begin wA 1300)) (some 10) 4 (s1 1100) [mH "m" "M" 1000 1600]
      [chk "a" "1" .check 1090] (chk "a" "1" .check 1090) 1800,
    wv "pass over at its till: gap rule" (some (begin { wA with next := 1900 } 1300)) (some 100) 4 (s1 1300) [m] [ck] ck 10,
    wv "gap: 100 s + settle fits before the pass at 1900" (some gapA) (some 100) 4 (s1 1400) [m] [ck] ck 10,
    wv "gap: 470 s + settle ends exactly at 1900" (some gapA) (some 470) 4 (s1 1400) [m] [ck] ck 10,
    wv "gap: 471 s + settle overlaps the pass" (some gapA) (some 471) 4 (s1 1400) [m] [ck] ck 10,
    wv "gap: no span history" (some gapA) none 4 (s1 1400) [m] [ck] ck 10,
    wv "gap: another measure lease waits" (some gapA) (some 10) 4 (s1 1400) [m] [chk "b" "2" .measure 1390]
      (chk "b" "2" .measure 1390) 10,
    wv "gap: base waits on memory" (some gapA) (some 10) 4 ((s1 1400).withFree 1500) [m] [ck] ck 10,
    wv "gap: base limit full" (some gapA) (some 10) 1 (s1 1400) [m] [ck] ck 10,
    wv "gap: an aged test ticket goes first" (some gapA) (some 10) 4 (s1 1400) [m] [chk "t" "7" .test 1000, ck] ck 10,
    wv "after the deadline: base verdict" (some gapA) (some 500) 4 (s1 6400) [mH "m" "M" 1000 7000]
      [chk "a" "1" .check 6390] (chk "a" "1" .check 6390) 10,
    wv "no window: base verdict" none none 4 (s1 1400) [] [ck] ck 10,
    wv "window of a released lease: base verdict" (some gapA) none 4 (s1 1400) [] [ck] ck 10,
    wv "first measure lease: admitted by the base" none none 4 (s1 1400) [] [chk "b" "2" .measure 1390]
      (chk "b" "2" .measure 1390) 0,
    ps "quiet: pass of 300 s" (some wA) 1100 [mH "m" "M" 1000 1600] "m" "M" 300,
    ps "pass capped at passMaxS" (some wA) 1100 [mH "m" "M" 1000 1600] "m" "M" 9000,
    ps "pass capped at the deadline" (some wA) 6300 [mH "m" "M" 1000 7000] "m" "M" 300,
    ps "a test still runs: the pass waits" (some wA) 1100 [mH "m" "M" 1000 1600, chk "a" "1" .test 1090] "m" "M" 300,
    ps "an expired test does not block" (some wA) 1100 [mH "m" "M" 1000 1600, chk "a" "1" .test 1000] "m" "M" 300,
    ps "old sim lock counts as another holder" (some wA) 1100 (withLegacy 1100 true [mH "m" "M" 1000 1600]) "m" "M" 300,
    ps "foreign owner: gone" (some wA) 1100 [mH "m" "M" 1000 1600] "x" "M" 300,
    ps "no window: gone" none 1100 [mH "m" "M" 1000 1600] "m" "M" 300,
    ps "deadline passed: gone" (some wA) 6400 [mH "m" "M" 1000 7000] "m" "M" 300,
    pr "three usable spans: p90 61 s" wp .check rows, pr "test: one span, no prediction" wp .test rows,
    pr "two spans: no prediction" wp .check (rows.take 2), pr "window of the last 2: below histMin" { histN := 2 } .check rows,
    pr "histMin 1: test 40 s" { histMin := 1 } .test rows, pr "no rows" wp .sim [],
    pr "rounding up: 1001 ms is 2 s" { histMin := 1 } .land [⟨"slot run land dry", 1001, some 0, "local"⟩],
    ed "begin a pass till 1300" wA "begin" 1000 1300, ed "want at 1500 pulls next in" gapA "want" 1500 0,
    ed "want after next keeps it" gapA "want" 2000 0, ed "stop at 1300, next pass in 600 s" (begin wA 1300) "stop" 1300 600,
    line "lease capped at the deadline" "window.capLease" [("window", windowJson wA), ("now", toJson 6000), ("lease", toJson 600)]
      (Json.mkObj [("leaseS", toJson (capLease wA 6000 600))]),
    line "lease inside the window" "window.capLease" [("window", windowJson wA), ("now", toJson 1000), ("lease", toJson 600)]
      (Json.mkObj [("leaseS", toJson (capLease wA 1000 600))]),
    line "deadline passed: no lease" "window.capLease" [("window", windowJson wA), ("now", toJson 7000), ("lease", toJson 600)]
      (Json.mkObj [("leaseS", toJson (capLease wA 7000 600))]) ]

def nestedLines : List String :=
  let en (o t : String) (k : Kind) (till : Nat) : Entry := { owner := o, token := t, kind := k, since := 100, till := till }
  let nm (o t : String) : Option (String × String) := some (o, t)
  let namedJson : Option (String × String) → Json
    | none => .null
    | some (o, t) => Json.mkObj [("owner", .str o), ("token", .str t)]
  let nl (name : String) (now : Nat) (k : Kind) (named : Option (String × String)) (held : List Entry) : String :=
    line name "adapt.nested" [("now", toJson now), ("kind", .str k.name), ("named", namedJson named), ("held", entriesJson held)]
      (Json.mkObj [("skip", .bool (nestedSkips now k named held))])
  [nl "named live land token, land request: skip" 200 .land (nm "w" "T1") [en "w" "T1" .land 300],
    nl "FW_SLOT_HELD alone, no token named: acquire" 200 .land none [en "w" "T1" .land 300],
    nl "no token named and nothing held: acquire" 200 .land none [],
    nl "held test slot, nested land request: skip, runs under the parent lease" 200 .land (nm "w" "T1") [en "w" "T1" .test 300],
    nl "held land slot, nested test request: skip, runs under the parent lease" 200 .test (nm "w" "T1") [en "w" "T1" .land 300],
    nl "held land slot, nested sim request: acquire" 200 .sim (nm "w" "T1") [en "w" "T1" .land 300],
    nl "held sim slot, nested sim request: skip" 200 .sim (nm "w" "T1") [en "w" "T1" .sim 300],
    nl "held land slot, nested measure request: acquire" 200 .measure (nm "w" "T1") [en "w" "T1" .land 300],
    nl "named token expired (till = now): acquire" 300 .land (nm "w" "T1") [en "w" "T1" .land 300],
    nl "named token released (not in state): acquire" 200 .land (nm "w" "T1") [en "w" "T2" .land 300],
    nl "token of another owner: acquire" 200 .land (nm "w" "T1") [en "x" "T1" .land 300],
    nl "live land entry of another holder, own token unknown: acquire" 200 .land (nm "w" "T9") [en "x" "T1" .land 300, en "y" "T2" .land 300],
    nl "several holders, the named one live and of the kind: skip" 200 .check (nm "w" "T2")
      [en "x" "T1" .land 300, en "w" "T2" .check 250, en "y" "T3" .test 300],
    nl "expired twin and live entry of one token: skip" 200 .land (nm "w" "T1") [en "w" "T1" .land 150, en "w" "T1" .land 300]]

def simReleaseLines : List String :=
  let strs (l : List String) : Json := .arr (l.map Json.str).toArray
  let rec' : Option (List String) → Json
    | none => .null
    | some l => strs l
  let en (t : String) (k : Kind) (till : Nat) : Entry := { owner := "w", token := t, kind := k, since := 100, till := till }
  let st (name : String) (before booted : List String) (h : Bool) : String :=
    line name "adapt.simSettle" [("before", strs before), ("booted", strs booted), ("handover", .bool h)]
      (Json.mkObj [("shut", strs (simSettle before booted h).1), ("record", rec' (simSettle before booted h).2)])
  let ho (name : String) (now : Nat) (q : List Entry) : String :=
    line name "adapt.simHandover" [("now", toJson now), ("queue", entriesJson q)] (Json.mkObj [("handover", .bool (simHandover now q))])
  let rc (name : String) (inh : Option (List String)) (booted : List String) : String :=
    line name "adapt.simRecord" [("inherited", rec' inh), ("booted", strs booted)] (Json.mkObj [("record", strs (simRecord inh booted))])
  [st "release, no handover: the device the lease booted is shut down" ["A"] ["A", "B"] false,
    st "release: a device booted before the lease is never shut down" ["A", "B"] ["A", "B"] false,
    st "release, nothing booted: nothing to shut down" ["A"] [] false,
    st "release, lease booted two devices: both shut down" [] ["B", "C"] false,
    st "handover: nothing is shut down, the record stays for the next holder" ["A"] ["A", "B"] true,
    ho "no queued ticket: no handover" 200 [],
    ho "queued sim ticket, live: handover" 200 [en "T2" .sim 300],
    ho "queued sim ticket, expired: no handover" 300 [en "T2" .sim 300],
    ho "queued test ticket only: no handover" 200 [en "T2" .test 300],
    rc "first holder: records what is booted now" none ["A"],
    rc "after a handover: the inherited record stays" (some ["A"]) ["A", "B"]]

set_option compiler.extract_closed false in
def goldenLines (_ : Unit := ()) : List String :=
  [line "default parameters" "adapt.params" [] (paramsJson {}),
    line "reason names (WhyTag.all): the closed parse list of the timing spans" "adapt.whyTags" []
      (Json.mkObj [("names", .arr (WhyTag.all.map (fun t => Json.str t.name)).toArray)])] ++ stepLines ++ verdictLines ++ threadsLines ++ memLines ++
    leaseLines ++ simLines ++ buildLines ++ holdLines ++ stopLines ++ cacheLines ++ windowLines () ++ nestedLines ++ simReleaseLines

def genPath : System.FilePath := "../packages/contracts/golden/sup/adapt.jsonl"

set_option compiler.extract_closed false in
def genText (_ : Unit := ()) : String := String.join ((goldenLines ()).map (· ++ "\n"))

def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let cur ← IO.FS.readFile genPath
    if cur != genText () then
      throw (IO.userError s!"sup-adapt: {genPath} is stale; regenerate with Fw.Sup.Adapt.gen []")
    IO.println s!"sup-adapt: {genPath} equals the Lean output"
  else
    IO.FS.createDirAll "../packages/contracts/golden/sup"
    IO.FS.writeFile genPath (genText ())

end Fw.Sup.Adapt
