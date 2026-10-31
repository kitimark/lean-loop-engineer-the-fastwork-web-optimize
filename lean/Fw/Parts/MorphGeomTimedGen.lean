import Fw.Parts.MorphGeomTimed
import Fw.Parts.MorphGeomVerify
import Fw.Parts.MorphGeomReady
namespace Fw.Parts.MorphGeomTimed
open Lean Fw.Parts.MorphGeom Fw.Parts.MorphTween

def idealAt (evs : List Ev) (t : Rat) : Rat := idealM (run (evs.filter fun ev => ev.e ≤ t)) t

def scenarios : List (String × List Ev) :=
  [("open", [⟨0, 1⟩]), ("close", [⟨0, 1⟩, ⟨1000, 0⟩]), ("reverse-early", [⟨0, 1⟩, ⟨100, 0⟩]),
    ("reverse-mid", [⟨0, 1⟩, ⟨300, 0⟩]), ("reverse-late", [⟨0, 1⟩, ⟨500, 0⟩]),
    ("reverse-twice", [⟨0, 1⟩, ⟨200, 0⟩, ⟨400, 1⟩])]

def times (evs : List Ev) : List Rat :=
  let last := (evs.map (·.e)).foldl max 0
  (List.range 28).map fun (k : Nat) => (k : Rat) * (last + 680) / 27

def scenarioLines (_ : Unit) : List String :=
  scenarios.map fun (n, evs) =>
    gline "scenario" [("name", .str n), ("events", jl (evs.map fun ev => Json.mkObj [("e", jdec 6 ev.e), ("g", jdec 0 ev.g)]))]
      (Json.mkObj [("t", jl ((times evs).map (jdec 6))), ("m", jl ((times evs).map fun t => jdec 6 (idealAt evs t)))])

def rebaseCases : List (Rat × Rat) := [(0, 1), (3 / 10, 1), (1 / 20, 1), (4 / 5, 0), (1, 0), (1 / 2, 0), (1 / 10, 1 / 2)]

def panelTrack : Track := mk panelO panelKnots

def rebaseLines (_ : Unit) : List String :=
  rebaseCases.map fun (m0, g) =>
    let kf := rebase panelTrack m0 g
    gline "rebase" [("m0", jdec 6 m0), ("g", jdec 6 g)]
      (Json.mkObj [("offsets", jl (kf.map fun x => jdec 9 x.1)), ("values", jl (kf.map fun x => jdec 9 x.2))])

def crossCases : List (Rat × Rat × Rat) :=
  [(0, 1, 1 / 1000), (0, 1, 1 / 5), (0, 1, 2 / 5), (0, 1, 11 / 20), (0, 1, 9 / 10), (0, 1, 23 / 25), (1, 0, 9 / 10), (1, 0, 1 / 2),
    (1, 0, 1 / 5), (3 / 10, 1, 2 / 5), (3 / 5, 0, 1 / 5), (1, 0, 1 / 1000)]

def crossLines (_ : Unit) : List String :=
  crossCases.map fun (m0, g, c) =>
    gline "cross" [("m0", jdec 6 m0), ("g", jdec 6 g), ("c", jdec 6 c)]
      (match crossMs m0 g c with | some n => .num ⟨n, 0⟩ | none => .null)

def takeScenarios : List (String × List Ev × List (List Bool)) :=
  [("dark-at-start", [⟨0, 1⟩], [[true]]), ("light-then-dark-3", [⟨0, 1⟩], [[false, false, false, true]]),
    ("never-dark", [⟨0, 1⟩], [[]]), ("close-from-rest", [⟨0, 1⟩, ⟨1020, 0⟩], [[], [false, false, true]]),
    ("close-after-open", [⟨0, 1⟩, ⟨1020, 0⟩], [[true], []]),
    ("reversal-while-pending", [⟨0, 1⟩, ⟨340, 0⟩], [[], [false, true]]),
    ("reversal-after-take", [⟨0, 1⟩, ⟨340, 0⟩], [[false, false, true], [false]])]

def tickMs : Nat := 17

def frameCount (evs : List Ev) (i : Nat) : Nat :=
  let e := (evs.getD i ⟨0, 0⟩).e
  let gap : Rat := match evs[i + 1]? with | some n => n.e - e | none => 680
  min 40 (((min gap 680).ceil).toNat / tickMs + 1)

def startValue (s : St) (e : Rat) (timed : Bool) : Rat :=
  let el := e - s.start
  if timed || 680 < el then idealM s e
  else idealM s (s.start + ((((el.ceil).toNat - 1) / tickMs * tickMs : Nat) : Rat))

def takeRows (evs : List Ev) (darks : List (List Bool)) : List (Option Nat × Rat) :=
  let go := fun (acc : Bool × Bool × St × List (Option Nat × Rat)) (i : Nat) =>
    let ev := evs.getD i ⟨0, 0⟩
    let s := push { acc.2.2.1 with value := startValue acc.2.2.1 ev.e acc.2.1 } ev.g false ev.e
    let d := darks.getD i []
    let r := takeFrame s.f s.t acc.1 (fun k => d.getD k false) (frameCount evs i)
    let m := match r with | some k => idealM s (ev.e + (k * tickMs : Nat)) | none => 0
    (acc.1 || r.isSome, r.isSome, s, acc.2.2.2 ++ [(r, m)])
  ((List.range evs.length).foldl go (false, false, MorphTween.rest, [])).2.2.2

def takeLines (_ : Unit) : List String :=
  takeScenarios.map fun (n, evs, darks) =>
    let rows := takeRows evs darks
    gline "take" [("name", .str n), ("events", jl (evs.map fun ev => Json.mkObj [("e", jdec 6 ev.e), ("g", jdec 0 ev.g)])),
      ("darks", jl (darks.map fun d => jl (d.map fun b => Json.bool b)))]
      (Json.mkObj [("taken", jl (rows.map fun r => match r.1 with | some k => .num ⟨k, 0⟩ | none => .null)),
        ("m", jl (rows.map fun r => jdec 6 r.2))])

def quietCases : List (Rat × List (Nat × Rat)) :=
  [(984, [(0, 984), (0, 984), (0, 984)]), (984, [(0, 984), (2, 984)]), (984, [(0, 984), (0, 990)]), (984, [(0, 983)]),
   (984, [(0, 982)]), (984, [(0, 984), (0, 984 + 1 / 2)]), (984, [])]

def keptCases : List (Nat × List (Rat × Rat × Rat)) :=
  [(0, [(50 / 3, 1000, 1000 + 50 / 3)]), (0, [(50 / 3, 1000, 50 / 3)]), (0, []), (1, [(50 / 3, 1000, 1000 + 50 / 3)]),
   (0, [(50 / 3, 1000, 1000 + 50 / 3), (50 / 3, 1000, 50 / 3)]), (0, [(50 / 3, 0, 50 / 3)]), (0, [(100 / 3, 5000, 5000 + 100 / 3 + 10)]),
   (0, [(50 / 3, 1000, 1040)])]

def traceCases : List (List TakeEv × List Bool) :=
  [([], []), ([.push], [true]), ([.push, .take], [true]), ([.push, .push, .take], [true, true]), ([.push, .take, .push], [true, true]),
   ([.push, .take, .push, .take], [true, true]), ([.take, .push, .take], [true]), ([.push, .take, .take], [true]),
   ([.push, .take, .push, .take, .push, .take, .push, .take], [true, true, true, true]),
   ([.push, .take, .push, .take, .push, .take, .push], [true, true, true, true]),
   ([.push, .take, .push, .take, .push, .take, .push], [true, true, true, false]),
   ([.push, .take, .push, .take, .push, .push], [true, true, false, false]),
   ([.push, .take, .push, .take, .push, .take, .push, .take], [false, false, false, false]),
   ([.push, .take, .push, .take, .push, .push], [false, false, false, false]),
   ([.push, .push, .take, .push, .push, .take], [false, false, false, true]),
   ([.push, .push, .take, .push, .push, .take], [true, false, false, true]),
   ([.push, .push], [false, false]), ([.push, .push], [true, true])]

def coveredCases : List (Rat × Rat × Rat) :=
  [(0, 800, 800), (0, 799, 800), (100, 900, 800), (100, 899, 800), (5000, 5000, 800), (0, 12000, 800)]

def retryCases : List (List PushObs) :=
  [[], [⟨false, false, true⟩, ⟨false, true, true⟩], [⟨true, false, false⟩], [⟨true, false, true⟩], [⟨true, true, false⟩],
   [⟨true, false, false⟩, ⟨false, false, true⟩], [⟨true, false, false⟩, ⟨true, true, true⟩]]

def leaveCountCases : List (Nat × Nat) := [(0, 2), (1, 2), (2, 2), (3, 2), (0, 0), (1, 1), (0, 1), (2, 0)]

def runCases : List (List BandObs × Bool) :=
  [([], true), ([⟨true, true, true⟩], true), ([⟨true, true, true⟩], false), ([⟨true, true, true⟩, ⟨true, true, true⟩], true),
   ([⟨false, true, true⟩], true), ([⟨true, false, true⟩], true), ([⟨true, true, false⟩], true),
   ([⟨true, true, true⟩, ⟨true, false, true⟩], true), ([⟨true, true, true⟩, ⟨true, true, true⟩, ⟨false, false, false⟩], true)]

def readyCases : List (Nat × CellObs × CellObs) :=
  [(3, ⟨3, 13, 13, 0⟩, ⟨3, 13, 13, 0⟩), (3, ⟨3, 13, 13, 0⟩, ⟨0, 0, 0, 0⟩), (3, ⟨3, 13, 13, 0⟩, ⟨2, 13, 13, 0⟩), (3, ⟨3, 13, 13, 0⟩, ⟨3, 12, 12, 0⟩),
   (3, ⟨3, 13, 13, 0⟩, ⟨3, 13, 9, 0⟩), (3, ⟨3, 13, 7, 0⟩, ⟨3, 13, 13, 0⟩), (3, ⟨0, 0, 0, 0⟩, ⟨3, 13, 13, 0⟩), (0, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩),
   (2, ⟨2, 8, 8, 0⟩, ⟨2, 8, 8, 0⟩), (2, ⟨2, 8, 8, 0⟩, ⟨3, 8, 8, 0⟩), (3, ⟨3, 13, 13, 0⟩, ⟨3, 13, 13, 2⟩), (3, ⟨3, 13, 13, 1⟩, ⟨3, 13, 13, 0⟩)]

def waitCases : List (Nat × Nat × Bool) :=
  [(0, 20000, true), (0, 20000, false), (19999, 20000, false), (20000, 20000, false), (25000, 20000, false), (25000, 20000, true), (0, 0, false)]

def attemptCases : List (Nat × List Attempt) :=
  [(2, []), (2, [.reading true]), (2, [.reading false]), (2, [.fault]), (2, [.fault, .fault]), (2, [.fault, .reading true]),
   (2, [.fault, .reading false]), (2, [.fault, .fault, .reading true]), (3, [.fault, .fault, .reading true]), (1, [.fault, .reading true]),
   (2, [.reading false, .reading true]), (2, [.reading true, .fault]), (0, [.reading true])]

def outcomeSets : List (List Outcome) :=
  [[], [.pass], [.pass, .pass], [.pass, .fail], [.pass, .exhausted], [.fail, .exhausted], [.exhausted]]

def nextCases : List (Nat × Nat × Attempt) :=
  [(1, 2, .fault), (2, 2, .fault), (3, 2, .fault), (1, 2, .reading true), (2, 2, .reading false), (1, 1, .fault)]

def errNames : List String := ["LimitError", "TimeoutError", "TypeError", "Error", "RangeError", "", "limiterror"]

def verifyLines (_ : Unit) : List String :=
  gline "verify" [] (Json.mkObj [("windowMs", .num ⟨verifyWindowMs, 0⟩), ("frameMs", jdec 4 verifyFrameMs), ("tolPx", jdec 4 verifyTolPx),
    ("mutations", jl (Mutation.all.map fun m => Json.mkObj [("id", .str m.name), ("reading", .str m.reading)]))]) ::
  (quietCases.map fun (b, fs) =>
    gline "verifyQuiet" [("base", jdec 4 b), ("tol", jdec 4 verifyTolPx),
      ("frames", jl (fs.map fun (n, w) => Json.mkObj [("moving", .num ⟨n, 0⟩), ("width", jdec 4 w)]))]
      (.bool (quietOk b verifyTolPx (fs.map fun (n, w) => ⟨n, w⟩)))) ++
  (keptCases.map fun (lost, ps) =>
    gline "verifyKept" [("frame", jdec 4 verifyFrameMs), ("lost", .num ⟨lost, 0⟩),
      ("pairs", jl (ps.map fun (dt, b, a) => Json.mkObj [("dt", jdec 4 dt), ("before", jdec 4 b), ("after", jdec 4 a)]))]
      (.bool (keptAll verifyFrameMs lost ps))) ++
  (traceCases.map fun (evs, cs) =>
    gline "verifyTrace" [("events", jl (evs.map fun e => Json.str e.name)), ("chances", jl (cs.map fun c => Json.bool c))] (.bool (traceOk evs cs))) ++
  (coveredCases.map fun (l, t, w) =>
    gline "verifyCovered" [("leave", jdec 4 l), ("last", jdec 4 t), ("window", jdec 4 w)] (.bool (leaveCovered l t w))) ++
  (retryCases.map fun ps =>
    gline "verifyRetry" [("pushes", jl (ps.map fun p => Json.mkObj [("light", Json.bool p.light), ("chance", Json.bool p.chance), ("taken", Json.bool p.taken)]))]
      (.bool (retryJudged ps))) ++
  (leaveCountCases.map fun (l, c) =>
    gline "verifyLeaveCount" [("leaves", .num ⟨l, 0⟩), ("cycles", .num ⟨c, 0⟩)] (.bool (leaveCountOk l c))) ++
  (runCases.map fun (bs, r) =>
    gline "verifyRun" [("bands", jl (bs.map fun b => Json.mkObj [("a3a", Json.bool b.a3a), ("a4", Json.bool b.a4), ("a5", Json.bool b.a5)])), ("retry", Json.bool r)]
      (.bool (runVerdict bs r))) ++
  (readyCases.map fun (w, b, f) =>
    let side (o : CellObs) := Json.mkObj [("cols", .num ⟨o.cols, 0⟩), ("imgs", .num ⟨o.imgs, 0⟩), ("loaded", .num ⟨o.loaded, 0⟩), ("running", .num ⟨o.running, 0⟩)]
    gline "verifyReady" [("want", .num ⟨w, 0⟩), ("base", side b), ("flag", side f)] (.bool (cellReady w b f))) ++
  (waitCases.map fun (e, l, r) =>
    gline "verifyWait" [("elapsed", .num ⟨e, 0⟩), ("limit", .num ⟨l, 0⟩), ("ready", Json.bool r)] (.str (waitStep e l r).name)) ++
  (attemptCases.map fun (m, as) =>
    gline "verifyAttempts" [("max", .num ⟨m, 0⟩), ("attempts", jl (as.map fun a => Json.str a.name))] (.str (cellOutcome m as).name)) ++
  (nextCases.map fun (n, m, a) =>
    gline "verifyNext" [("n", .num ⟨n, 0⟩), ("max", .num ⟨m, 0⟩), ("attempt", .str a.name)] (.str (retryNext n m a).name)) ++
  (errNames.map fun e =>
    gline "verifyErr" [("name", .str e)]
      (Json.mkObj [("kind", .str (errKind e).name), ("next", .str (retryNext 1 maxAttempts (errKind e).attempt).name),
        ("outcome", .str (cellOutcome maxAttempts [(errKind e).attempt]).name)])) ++
  (outcomeSets.map fun os =>
    gline "verifyCells" [("outcomes", jl (os.map fun o => Json.str o.name))]
      (Json.mkObj [("pass", Json.bool (cellsPass os)), ("kept", Json.bool (cellsKept os))])) ++
  [gline "verifyLimits" [] (Json.mkObj [("readyMs", .num ⟨readyLimitMs, 0⟩), ("pollMs", .num ⟨readyPollMs, 0⟩), ("shotMs", .num ⟨shotLimitMs, 0⟩),
    ("callMs", .num ⟨callLimitMs, 0⟩), ("closeMs", .num ⟨closeLimitMs, 0⟩), ("attempts", .num ⟨maxAttempts, 0⟩)])]

def goldenText (_ : Unit) : String := String.join ((scenarioLines () ++ rebaseLines () ++ crossLines () ++ takeLines () ++ verifyLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-geom-timed golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph-geom-timed golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard (crossMs 0 1 (1 / 5)).isSome
#guard idealAt [⟨0, 1⟩] 340 == 7 / 8
#guard idealAt [⟨0, 1⟩, ⟨340, 0⟩] 340 == 7 / 8
#guard (rebase panelTrack 0 1).length == 4
#guard (takeRows [⟨0, 1⟩] [[false, false, false, true]]).map (·.1) == [some 3]
#guard (takeRows [⟨0, 1⟩, ⟨1020, 0⟩] [[], [false, false, true]]).map (·.1) == [none, some 2]
#guard (takeRows [⟨0, 1⟩, ⟨1020, 0⟩] [[true], []]).map (·.1) == [some 0, some 0]

end Fw.Parts.MorphGeomTimed
