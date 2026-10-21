import Lean.Data.Json
import Fw.Sup.Adapt

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
    ("simIdleS", toJson p.simIdleS), ("graceMs", toJson p.graceMs)]

def sampleJson (s : Sample) : Json :=
  Json.mkObj [("time", toJson s.time), ("loadCenti", toJson s.loadCenti), ("freeMB", toJson s.freeMB),
    ("ramMB", toJson s.ramMB), ("compressorMB", toJson s.compressorMB), ("swapUsedMB", toJson s.swapUsedMB),
    ("cores", toJson s.cores)]

def prevJson : Option (Nat × Nat) → Json
  | none => .null
  | some (t, mb) => Json.mkObj [("time", toJson t), ("swapUsedMB", toJson mb)]

def ctlJson (c : Ctl) : Json :=
  Json.mkObj [("n", toJson c.n), ("lastChange", toJson c.lastChange), ("prev", prevJson c.prev)]

def entryJson (e : Entry) : Json :=
  Json.mkObj [("owner", .str e.owner), ("token", .str e.token), ("kind", .str e.kind.name), ("since", toJson e.since),
    ("till", toJson e.till), ("foot", toJson e.foot)]

def entriesJson (es : List Entry) : Json := .arr (es.map entryJson).toArray

def whyFields : Why → List (String × Json)
  | .queued a => [("why", "queued"), ("ahead", toJson a)]
  | .older => [("why", "older")]
  | .full r l => [("why", "full"), ("running", toJson r), ("limit", toJson l)]
  | .simBusy => [("why", "simBusy")]
  | .memory n r => [("why", "memory"), ("needMB", toJson n), ("roomMB", toJson r)]

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

/-- Parameter overrides the cases use, as the JSON fields that differ from the defaults. -/
def tight : Params := { holdS := 0, nMax := 6 }

def tightJson : Json := Json.mkObj [("holdS", toJson tight.holdS), ("nMax", toJson tight.nMax)]

def busySample : Sample := { okSample with loadCenti := 3550 }

def stepCases : List (String × Bool × Ctl × Sample) :=
  [ ("quiet sample after the window: +1", false, { n := 2, lastChange := 0 }, okSample),
    ("quiet sample inside the window: unchanged", false, { n := 2, lastChange := 990 }, okSample),
    ("window just passed: +1", false, { n := 2, lastChange := 970 }, okSample),
    ("load at the high mark: halve", false, { n := 4, lastChange := 0 }, { okSample with loadCenti := 1600 }),
    ("load just below the high mark and above target: hold", false, { n := 3, lastChange := 0 },
      { okSample with loadCenti := 1599 }),
    ("load at target: hold", false, { n := 3, lastChange := 0 }, { okSample with loadCenti := 800 }),
    ("busy hour with the Simulator up (load 35.5): halve", false, { n := 4, lastChange := 0 }, busySample),
    ("free memory below the floor: halve, clamped to nMin", false, { n := 1, lastChange := 0 }, { okSample with freeMB := 1023 }),
    ("free memory at the floor but no headroom: hold", false, { n := 2, lastChange := 0 }, { okSample with freeMB := 2000 }),
    ("free memory exactly floor + headroom: +1", false, { n := 2, lastChange := 0 }, { okSample with freeMB := 3072 }),
    ("compressor at 40 percent of RAM: halve", false, { n := 4, lastChange := 0 }, { okSample with compressorMB := 6554 }),
    ("compressor just below 40 percent: +1", false, { n := 2, lastChange := 0 }, { okSample with compressorMB := 6553 }),
    ("swap rising 100 MB in 5 s: halve", false, { n := 3, lastChange := 0, prev := some (995, 4900) }, okSample),
    ("swap rising just below the rate: +1", false, { n := 3, lastChange := 0, prev := some (940, 4489) }, okSample),
    ("swap static at 61 percent of dynamic swap: +1 (ratio not read)", false, { n := 3, lastChange := 0, prev := some (995, 5000) },
      okSample),
    ("swap shrinking: +1", false, { n := 3, lastChange := 0, prev := some (995, 6000) }, okSample),
    ("no previous reading: swap not read", false, { n := 3, lastChange := 0 }, { okSample with swapUsedMB := 9000 }),
    ("at nMax: stays", false, { n := 4, lastChange := 0 }, okSample),
    ("above nMax (old state): clamped down", false, { n := 9, lastChange := 0 }, okSample),
    ("below nMin (old state): clamped up on hold", false, { n := 0, lastChange := 0 }, { okSample with loadCenti := 1000 }),
    ("no window, nMax 6: +1 at once", true, { n := 5, lastChange := 999 }, okSample) ]

def stepLines : List String :=
  stepCases.map fun (nm, t, c, s) =>
    let p : Params := if t then tight else {}
    let c' := step p c s
    line nm "adapt.step" ((if t then [("params", tightJson)] else []) ++ [("ctl", ctlJson c), ("sample", sampleJson s)])
      (Json.mkObj [("ctl", ctlJson c'), ("signal", .str (signal p c.prev s).name)])

def liveH (o t : String) (k : Kind) (since foot : Nat) : Entry :=
  { owner := o, token := t, kind := k, since := since, till := 5000, foot := foot }

def verdictCases : List (String × Nat × Sample × List Entry × List Entry × Entry × Nat) :=
  let me := tk "a" "1" .check 990
  [ ("idle machine, check: threads from free memory", 2, okSample, [], [me], me, 0),
    ("check with little room: one Lean worker", 2, { okSample with freeMB := 1800 }, [], [me], me, 0),
    ("check, one worker does not fit: memory", 2, { okSample with freeMB := 1700 }, [], [me], me, 0),
    ("check, room for exactly one worker", 2, { okSample with freeMB := 1724 }, [], [me], me, 0),
    ("16 GB free on 8 cores: threads capped at the cores", 2, { okSample with freeMB := 16000 }, [], [me], me, 0),
    ("same kind ahead: queued", 2, okSample, [], [tk "b" "2" .check 980, me], me, 0),
    ("two of the same kind ahead: queued 2", 2, okSample, [], [tk "b" "2" .check 980, tk "c" "3" .check 985, me], me, 0),
    ("other kind ahead, young: no wait for it", 2, okSample, [], [tk "b" "2" .test 980, me], me, 0),
    ("other kind ahead, waited ageS: older", 2, okSample, [], [tk "b" "2" .test 700, me], me, 0),
    ("other kind ahead, one second short of ageS", 2, okSample, [], [tk "b" "2" .test 701, me], me, 0),
    ("holders at N: full", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 0),
    ("expired holder does not count", 1, okSample, [{ liveH "x" "9" .test 0 0 with till := 1000 }], [me], me, 0),
    ("N 0: full with no holder", 0, okSample, [], [me], me, 0),
    ("sim asked while a live sim holder runs: simBusy", 3, okSample, [liveH "x" "9" .sim 0 2800],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim asked, expired sim holder: admit", 3, okSample, [{ liveH "x" "9" .sim 0 2800 with till := 999 }],
      [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim needs 2800 MB plus the floor", 3, { okSample with freeMB := 3823 }, [], [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("sim exactly fits", 3, { okSample with freeMB := 3824 }, [], [tk "a" "1" .sim 990], tk "a" "1" .sim 990, 0),
    ("test beside a warming check holder is charged", 3, { okSample with freeMB := 6000 }, [liveH "x" "9" .check 980 4200],
      [tk "a" "1" .test 990], tk "a" "1" .test 990, 0),
    ("test beside a warm (old) check holder is not charged", 3, { okSample with freeMB := 6000 }, [liveH "x" "9" .check 900 4200],
      [tk "a" "1" .test 990], tk "a" "1" .test 990, 0),
    ("land needs 1500 MB", 3, { okSample with freeMB := 2523 }, [], [tk "a" "1" .land 990], tk "a" "1" .land 990, 0),
    ("other needs 1000 MB", 3, { okSample with freeMB := 2024 }, [], [tk "a" "1" .other 990], tk "a" "1" .other 990, 0),
    ("waited just below the limit: wait", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 1799),
    ("waited the limit: timeout, never run", 1, okSample, [liveH "x" "9" .test 0 0], [me], me, 1800),
    ("waited the limit but admissible: admit", 2, okSample, [], [me], me, 9999),
    ("ticket missing from the queue: every same-kind ticket is ahead", 2, okSample, [], [tk "b" "2" .check 980], me, 0) ]

def verdictLines (p : Params := {}) : List String :=
  verdictCases.map fun (nm, n, s, hs, q, me, w) =>
    line nm "adapt.verdict" [("n", toJson n), ("sample", sampleJson s), ("holders", entriesJson hs), ("queue", entriesJson q),
      ("me", entryJson me), ("waited", toJson w)] (verdictJson (verdict p n s hs q me w))

def threadsCases : List (Nat × Nat) := [(8, 0), (8, 699), (8, 700), (8, 1400), (8, 4976), (8, 100000), (0, 5000), (1, 5000)]

def threadsLines : List String :=
  threadsCases.map fun (c, r) =>
    line s!"threads cores={c} roomMB={r}" "adapt.threads" [("cores", toJson c), ("roomMB", toJson r)]
      (Json.mkObj [("threads", toJson (leanThreads {} c r))])

def holdB : Entry := { owner := "b", token := "t2", kind := .test, since := 0, till := 60 }

def leaseLines : List String :=
  let es := [holdA, holdB]
  let pr := fun (nm : String) (now : Nat) =>
    line nm "adapt.prune" [("now", toJson now), ("entries", entriesJson es)] (Json.mkObj [("entries", entriesJson (prune now es))])
  let rn := fun (nm : String) (now : Nat) (o t : String) (lease : Nat) =>
    line nm "adapt.renew" [("now", toJson now), ("owner", .str o), ("token", .str t), ("lease", toJson lease),
      ("entries", entriesJson es)]
      (Json.mkObj [("entries", match renew {} now o t lease es with | some r => entriesJson r | none => .null)])
  let rl := fun (nm : String) (o t : String) =>
    line nm "adapt.release" [("owner", .str o), ("token", .str t), ("entries", entriesJson es)]
      (Json.mkObj [("entries", entriesJson (release o t es))])
  [ pr "both live" 59, pr "one lease ends at 60" 60, pr "both expired" 100,
    rn "own live lease renewed" 50 "a" "t1" 600, rn "lease capped at leaseMaxS" 50 "a" "t1" 99999,
    rn "wrong token refused" 50 "a" "t9" 600, rn "another owner refused" 50 "b" "t1" 600,
    rn "expired lease refused" 100 "a" "t1" 600, rn "lease at its last second renewed" 99 "a" "t1" 60,
    rl "own entry released" "a" "t1", rl "foreign release is a no-op" "a" "t2" ]

def simLines : List String :=
  let boot := fun (nm : String) (now : Nat) (o t : String) (hs : List Entry) =>
    line nm "adapt.simBoot" [("now", toJson now), ("owner", .str o), ("token", .str t), ("holders", entriesJson hs)]
      (Json.mkObj [("boot", .bool (simBoot now o t hs))])
  let act := fun (nm : String) (now : Nat) (hs : List Entry) (b l : Bool) (i : Nat) =>
    line nm "adapt.simAction" [("now", toJson now), ("holders", entriesJson hs), ("booted", .bool b), ("legacyHeld", .bool l),
      ("idleSince", toJson i)] (Json.mkObj [("action", .str (simAction {} now hs b l i).name)])
  [ boot "slot owner boots" 50 "a" "t1" [holdA], boot "no slot: no boot" 50 "a" "t1" [],
    boot "another agent's slot: no boot" 50 "b" "t1" [holdA], boot "expired slot: no boot" 100 "a" "t1" [holdA],
    boot "a test slot does not allow a boot" 50 "b" "t2" [holdB],
    act "not booted: nothing" 5000 [] false false 0, act "live sim slot: keep" 50 [holdA] true false 0,
    act "old sim lock held: keep" 5000 [] true true 0, act "idle 599 s: keep" 1599 [] true false 1000,
    act "idle 600 s: shutdown" 1600 [] true false 1000, act "expired slot, idle: shutdown" 700 [holdA] true false 0,
    act "a live test slot does not keep the Simulator" 700 [{ holdB with till := 9999 }] true false 0 ]

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

set_option compiler.extract_closed false in
def goldenLines (_ : Unit := ()) : List String :=
  [line "default parameters" "adapt.params" [] (paramsJson {})] ++ stepLines ++ verdictLines ++ threadsLines ++ leaseLines ++
    simLines ++ stopLines ++ cacheLines

def genPath : System.FilePath := "../packages/contracts/golden/sup/adapt.jsonl"

set_option compiler.extract_closed false in
def genText (_ : Unit := ()) : String := String.join ((goldenLines ()).map (· ++ "\n"))

/-- Write `genPath`, or with `--check` throw when the file differs from `genText`. -/
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
