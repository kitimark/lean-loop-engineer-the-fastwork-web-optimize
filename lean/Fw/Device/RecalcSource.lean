import Lean.Data.Json
/-!
# The recalc-source verdict
Reads `packages/measure-wktr/src/recalc-source.mjs`: with every running animation paused, WebKit still runs about one style
recalc per frame. Which page-side action, if any, is present in those frames?

A frame is one task-bounded rendering update. Its `keys` are the page-side actions seen in it, each as `kind:what`
(`mut:` DOM mutation by part and attribute, `raf:` requestAnimationFrame callback by call site, `timer:` timer callback by call
site, `cssom:` stylesheet rule write, `anim:` Element.animate call). A key is present in a frame when its count is at least 1.
`sizes` are the element counts of the recalcs the probe could read one by one (diagnostic, not in the verdict).
A job has the plain all-paused arm (`floor`, no observer), the observed arm (`base`) and one arm per intervention
(`ivs`: the kind of page callback the probe swallowed, with the frames of that arm).

The thresholds are fixed here, before any data.
-/
namespace Fw.Device.RecalcSource
open Lean

structure Frame where
  recalcs : Nat
  keys : List String
  sizes : List Nat
  deriving DecidableEq, Repr

/-- Recalcs per 100 frames, rounded down. -/
def rpf100 (fs : List Frame) : Nat :=
  if fs.length = 0 then 0 else (fs.map (·.recalcs)).sum * 100 / fs.length

structure Job where
  floor : List Frame
  base : List Frame
  ivs : List (String × List Frame)
  deriving DecidableEq, Repr

/-- A source key must be present in at least this percent of the frames that have a recalc (the lead's rule). -/
def coverMinPct : Nat := 90

/-- ... and absent from at least this percent of the frames without one (the lead's rule). -/
def absentMinPct : Nat := 90

/-- Frames without a recalc needed before absence can be judged: with 10 the 10 percent leak bound is one whole frame. -/
def minQ : Nat := 10

/-- The plain all-paused arm must show this many recalcs per 100 frames (earlier readings 99 to 100; 75 keeps it far above the half of 50 and the 25 floor). -/
def residualMin : Nat := 75

/-- The observed arm may differ from the plain arm by at most this many recalcs per 100 frames, else the observer is the cause. -/
def shiftMax : Nat := 25

/-- A swallowed kind has "fallen" when its arm shows at most this many recalcs per 100 frames (the geom-sweep-paused `idleOffMax`). -/
def fellMax : Nat := 25

def kindOf (k : String) : String := (k.splitOn ":").headD ""

def count (k : String) (fs : List Frame) : Nat := (fs.filter (fun f => f.keys.contains k)).length

def Job.withRecalc (j : Job) : List Frame := j.base.filter (fun f => 0 < f.recalcs)

def Job.withoutRecalc (j : Job) : List Frame := j.base.filter (fun f => f.recalcs = 0)

def Job.universe (j : Job) : List String := (j.base.flatMap (·.keys)).eraseDups

def Job.covered (j : Job) (k : String) : Bool :=
  coverMinPct * j.withRecalc.length ≤ 100 * count k j.withRecalc

def Job.absent (j : Job) (k : String) : Bool :=
  absentMinPct * j.withoutRecalc.length ≤ 100 * (j.withoutRecalc.length - count k j.withoutRecalc)

def Job.contrast (j : Job) : Bool := minQ ≤ j.withoutRecalc.length

def Job.hasFrames (mf : Nat) (j : Job) : Bool := mf ≤ j.floor.length && mf ≤ j.base.length

def Job.residual (j : Job) : Bool := residualMin ≤ rpf100 j.floor

def Job.shifted (j : Job) : Bool :=
  shiftMax < rpf100 j.base - rpf100 j.floor || shiftMax < rpf100 j.floor - rpf100 j.base

/-- The intervention arm of a kind fell: long enough and at most `fellMax` recalcs per 100 frames. -/
def Job.fell (mf : Nat) (j : Job) (kind : String) : Bool :=
  match j.ivs.find? (·.1 == kind) with
  | some (_, fs) => mf ≤ fs.length && rpf100 fs ≤ fellMax
  | none => false

/-- The intervention arm of a kind kept its recalcs: long enough and above `fellMax`. -/
def Job.refuted (mf : Nat) (j : Job) (kind : String) : Bool :=
  match j.ivs.find? (·.1 == kind) with
  | some (_, fs) => mf ≤ fs.length && fellMax < rpf100 fs
  | none => false

/-- Keys present in the recalc frames whose kind was not refuted by its intervention. -/
def Job.suspects (mf : Nat) (j : Job) : List String :=
  j.universe.filter fun k => j.covered k && !j.refuted mf (kindOf k)

/-- With contrast a suspect must also be absent from the frames without a recalc; without it, its kind's intervention must have fallen. -/
def Job.sources (mf : Nat) (j : Job) : List String :=
  (j.suspects mf).filter fun k => if j.contrast then j.absent k else j.fell mf (kindOf k)

inductive Why where
  | noFrames | noResidual | observerShift | internal | named | several | noContrast
  deriving DecidableEq

def Why.name : Why → String
  | .noFrames => "no-frames" | .noResidual => "no-residual" | .observerShift => "observer-shift"
  | .internal => "engine-internal" | .named => "named" | .several => "several" | .noContrast => "no-contrast"

def Why.valid : Why → Bool
  | .internal | .named | .several => true
  | _ => false

def Job.why (mf : Nat) (j : Job) : Why :=
  if !j.hasFrames mf then .noFrames
  else if !j.residual then .noResidual
  else if j.shifted then .observerShift
  else if (j.sources mf).length = 1 then .named
  else if 2 ≤ (j.sources mf).length then .several
  else if (j.suspects mf).isEmpty || j.contrast then .internal
  else .noContrast

theorem why_noFrames (mf : Nat) (j : Job) (h : j.hasFrames mf = false) : j.why mf = .noFrames := by
  simp [Job.why, h]

theorem why_noResidual (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h : j.residual = false) :
    j.why mf = .noResidual := by
  simp [Job.why, h1, h]

theorem why_observerShift (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h : j.shifted = true) : j.why mf = .observerShift := by
  simp [Job.why, h1, h2, h]

theorem why_named (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h3 : j.shifted = false) (h : (j.sources mf).length = 1) : j.why mf = .named := by
  simp [Job.why, h1, h2, h3, h]

theorem why_several (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h3 : j.shifted = false) (h : 2 ≤ (j.sources mf).length) : j.why mf = .several := by
  have h' : (j.sources mf).length ≠ 1 := by omega
  simp [Job.why, h1, h2, h3, h', h]

/-- No suspect at all: nothing page-side is present in 90 percent of the recalc frames, or the interventions refuted what is. -/
theorem why_internal_noSuspect (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h3 : j.shifted = false) (h : j.suspects mf = []) : j.why mf = .internal := by
  have hs : j.sources mf = [] := by simp [Job.sources, h]
  simp [Job.why, h1, h2, h3, hs, h]

/-- Contrast exists, suspects exist, and none of them is absent from the quiet frames: nothing separates a frame with a recalc from one without. -/
theorem why_internal_leaky (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h3 : j.shifted = false) (hc : j.contrast = true) (h : j.sources mf = []) : j.why mf = .internal := by
  simp [Job.why, h1, h2, h3, h, hc]

/-- No contrast and no fallen intervention: suspects stay suspects. -/
theorem why_noContrast (mf : Nat) (j : Job) (h1 : j.hasFrames mf = true) (h2 : j.residual = true)
    (h3 : j.shifted = false) (hc : j.contrast = false) (h : j.sources mf = []) (hs : j.suspects mf ≠ []) :
    j.why mf = .noContrast := by
  simp [Job.why, h1, h2, h3, h, hc, hs]

theorem sources_subset_suspects (mf : Nat) (j : Job) (k : String) (h : k ∈ j.sources mf) : k ∈ j.suspects mf :=
  (List.mem_filter.mp h).1

theorem suspects_covered (mf : Nat) (j : Job) (k : String) (h : k ∈ j.suspects mf) : j.covered k = true := by
  have := (List.mem_filter.mp h).2
  simp only [Bool.and_eq_true] at this
  exact this.1

theorem suspects_not_refuted (mf : Nat) (j : Job) (k : String) (h : k ∈ j.suspects mf) :
    j.refuted mf (kindOf k) = false := by
  have := (List.mem_filter.mp h).2
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at this
  exact this.2

/-- With contrast a source is absent from the quiet frames. -/
theorem sources_absent (mf : Nat) (j : Job) (k : String) (hc : j.contrast = true) (h : k ∈ j.sources mf) :
    j.absent k = true := by
  have := (List.mem_filter.mp h).2
  simpa [hc] using this

/-- Without contrast a source's kind has a fallen intervention. -/
theorem sources_fell (mf : Nat) (j : Job) (k : String) (hc : j.contrast = false) (h : k ∈ j.sources mf) :
    j.fell mf (kindOf k) = true := by
  have := (List.mem_filter.mp h).2
  simpa [hc] using this

/-- A kind is never both fallen and refuted. -/
theorem fell_not_refuted (mf : Nat) (j : Job) (kind : String) (h : j.fell mf kind = true) :
    j.refuted mf kind = false := by
  unfold Job.fell at h
  unfold Job.refuted
  cases hf : j.ivs.find? (·.1 == kind) with
  | none => simp [hf] at h
  | some p =>
    obtain ⟨a, fs⟩ := p
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    have : ¬ (fellMax < rpf100 fs) := by omega
    simp [this]

theorem thresholds_sane : fellMax < residualMin ∧ shiftMax ≤ fellMax ∧ 0 < minQ ∧ coverMinPct ≤ 100 ∧ absentMinPct ≤ 100 := by
  decide

/-- One job's reading: its reason and the key it names. -/
structure Res where
  why : Why
  src : Option String
  deriving DecidableEq

def Job.res (mf : Nat) (j : Job) : Res :=
  let w := j.why mf
  ⟨w, if w = .named then (j.sources mf).head? else none⟩

inductive Verdict where
  | inconclusive | internal | named (k : String) | several
  deriving DecidableEq

def Verdict.name : Verdict → String
  | .inconclusive => "inconclusive" | .internal => "engine-internal" | .named k => s!"named {k}" | .several => "several"

/-- At least this many jobs must be valid for a verdict. -/
def minValid : Nat := 2

/-- The verdict over the valid jobs `vs`. -/
def overallOf (vs : List Res) : Verdict :=
  if vs.all (·.why == .internal) then .internal
  else if vs.all (·.why == .named) && vs.all (·.src == (vs.head?.bind (·.src))) then
    match vs.head?.bind (·.src) with
    | some k => .named k
    | none => .several
  else .several

def overall (rs : List Res) : Verdict :=
  let vs := rs.filter (·.why.valid)
  if vs.length < minValid then .inconclusive else overallOf vs

theorem overall_inconclusive (rs : List Res) (h : (rs.filter (·.why.valid)).length < minValid) :
    overall rs = .inconclusive := by
  simp [overall, h]

theorem overall_eq (rs : List Res) (h : ¬ (rs.filter (·.why.valid)).length < minValid) :
    overall rs = overallOf (rs.filter (·.why.valid)) := by
  simp [overall, h]

theorem overallOf_internal (vs : List Res) (h : vs.all (·.why == .internal) = true) : overallOf vs = .internal := by
  simp [overallOf, h]

theorem overallOf_several_mixed (vs : List Res) (hi : vs.all (·.why == .internal) = false)
    (hn : vs.all (·.why == .named) = false) : overallOf vs = .several := by
  simp [overallOf, hi, hn]

theorem overallOf_several_keys (vs : List Res) (hi : vs.all (·.why == .internal) = false)
    (hk : vs.all (·.src == (vs.head?.bind (·.src))) = false) : overallOf vs = .several := by
  simp [overallOf, hi, hk]

theorem overallOf_named (vs : List Res) (k : String) (hi : vs.all (·.why == .internal) = false)
    (hn : vs.all (·.why == .named) = true) (hk : vs.all (·.src == (vs.head?.bind (·.src))) = true)
    (hh : vs.head?.bind (·.src) = some k) : overallOf vs = .named k := by
  have hk' := hk
  rw [hh] at hk'
  simp only [List.all_eq_true, beq_iff_eq] at hk'
  simp [overallOf, hi, hn, hh]
  exact hk'

inductive Next where
  | fixTask | splitByIntervention | engineReport | rerun
  deriving DecidableEq

def Next.name : Next → String
  | .fixTask => "one same-look fix task for the named source"
  | .splitByIntervention => "one intervention arm per source"
  | .engineReport => "no page-side fix: read the WebKit invalidation path"
  | .rerun => "rerun with contrast or more valid jobs"

def Verdict.next : Verdict → Next
  | .named _ => .fixTask
  | .several => .splitByIntervention
  | .internal => .engineReport
  | .inconclusive => .rerun

theorem next_fix_iff (v : Verdict) : v.next = .fixTask ↔ ∃ k, v = .named k := by
  cases v <;> simp [Verdict.next]

/-- Share of the readable recalc element counts that are 0, per mille (diagnostic: an empty update is an invalidation without a style change). -/
def emptyPm (fs : List Frame) : Nat :=
  let zs := fs.flatMap (·.sizes)
  if zs.length = 0 then 0 else (zs.filter (· = 0)).length * 1000 / zs.length

private def fr (r : Nat) (ks : List String := []) (sz : List Nat := []) : Frame := ⟨r, ks, sz⟩

private def rep (n : Nat) (f : Frame) : List Frame := List.replicate n f

private def kA : String := "raf:clock>scroll"
private def kB : String := "raf:clock>pain"
private def kM : String := "mut:platform#style"
private def kT : String := "timer:poll"

private def job (floor base : List Frame) (ivs : List (String × List Frame) := []) : Job := ⟨floor, base, ivs⟩

private def fl : List Frame := rep 60 (fr 1)

/-- Named cases: (name, minimum frames per arm, job). Idle cases use 40, flip cases 12. -/
def cases : List (String × Nat × Job) :=
  [("named by contrast", 40, job fl (rep 70 (fr 1 [kA]) ++ rep 12 (fr 0))),
   ("leaky candidate dropped", 40, job fl (rep 70 (fr 1 [kA, kM]) ++ rep 6 (fr 0 [kM]) ++ rep 6 (fr 0))),
   ("two quiet candidates", 40, job fl (rep 70 (fr 1 [kA, kM]) ++ rep 12 (fr 0))),
   ("all leak", 40, job fl (rep 70 (fr 1 [kA]) ++ rep 12 (fr 0 [kA]))),
   ("no candidate", 40, job fl (rep 80 (fr 1 [] [0]))),
   ("block fell names raf", 40, job fl (rep 80 (fr 1 [kA, kM])) [("raf", rep 60 (fr 0))]),
   ("block kept", 40, job fl (rep 80 (fr 1 [kA, kM])) [("raf", rep 60 (fr 1))]),
   ("no block", 40, job fl (rep 80 (fr 1 [kA, kM]))),
   ("two raf sites fell", 40, job fl (rep 80 (fr 1 [kA, kB])) [("raf", rep 60 (fr 0))]),
   ("fell but no raf suspect", 40, job fl (rep 80 (fr 1 [kM])) [("raf", rep 60 (fr 0))]),
   ("all suspects refuted", 40, job fl (rep 80 (fr 1 [kA])) [("raf", rep 60 (fr 1))]),
   ("timer block fell names timer", 40, job fl (rep 80 (fr 1 [kT, kM])) [("timer", rep 60 (fr 0)), ("raf", rep 60 (fr 1))]),
   ("block arm too short", 40, job fl (rep 80 (fr 1 [kA])) [("raf", rep 10 (fr 0))]),
   ("coverage edge hit", 40, job fl (rep 90 (fr 1 [kA]) ++ rep 10 (fr 1) ++ rep 12 (fr 0))),
   ("coverage edge miss", 40, job fl (rep 89 (fr 1 [kA]) ++ rep 11 (fr 1) ++ rep 12 (fr 0))),
   ("quiet edge hit", 40, job fl (rep 80 (fr 1 [kA]) ++ rep 1 (fr 0 [kA]) ++ rep 9 (fr 0))),
   ("quiet edge miss", 40, job fl (rep 80 (fr 1 [kA]) ++ rep 2 (fr 0 [kA]) ++ rep 8 (fr 0))),
   ("contrast edge miss", 40, job fl (rep 80 (fr 1 [kA]) ++ rep 9 (fr 0))),
   ("floor absent", 40, job (rep 60 (fr 0)) (rep 80 (fr 1 [kA]) ++ rep 12 (fr 0))),
   ("floor edge hit", 40, job (rep 45 (fr 1) ++ rep 15 (fr 0)) (rep 45 (fr 1 [kA]) ++ rep 15 (fr 0))),
   ("floor edge miss", 40, job (rep 44 (fr 1) ++ rep 16 (fr 0)) (rep 44 (fr 1 [kA]) ++ rep 16 (fr 0))),
   ("observer shift", 40, job fl (rep 60 (fr 2 [kA]))),
   ("shift edge hit", 40, job fl (rep 15 (fr 2 [kA]) ++ rep 45 (fr 1 [kA])) [("raf", rep 60 (fr 0))]),
   ("no frames", 40, job (rep 10 (fr 1)) (rep 80 (fr 1 [kA]) ++ rep 12 (fr 0))),
   ("flip suspects only", 12, job (rep 18 (fr 2)) (rep 18 (fr 2 [kA, kM]))),
   ("flip contrast names", 12, job (rep 18 (fr 2) ++ rep 10 (fr 0)) (rep 18 (fr 2 [kA]) ++ rep 10 (fr 0))),
   ("flip no candidate", 12, job (rep 18 (fr 2)) (rep 18 (fr 2))),
   ("flip too short", 12, job (rep 8 (fr 2)) (rep 18 (fr 2 [kA])))]

private def zeroJob : Job := ⟨[], [], []⟩

def caseOf (n : String) : Nat × Job := ((cases.find? (·.1 == n)).map (·.2)).getD (40, zeroJob)

def combos : List (String × List String) :=
  [("three named", ["named by contrast", "block fell names raf", "coverage edge hit"]),
   ("two named, one void", ["named by contrast", "no block", "block fell names raf"]),
   ("one named, rest void", ["named by contrast", "no block", "floor absent"]),
   ("named different keys", ["named by contrast", "timer block fell names timer", "named by contrast"]),
   ("named and internal", ["named by contrast", "no candidate", "named by contrast"]),
   ("three internal", ["no candidate", "all leak", "all suspects refuted"]),
   ("several and named", ["two quiet candidates", "named by contrast", "named by contrast"]),
   ("none valid", ["no block", "floor absent", "no frames"]),
   ("observer shift void", ["observer shift", "observer shift", "named by contrast"]),
   ("two jobs named", ["named by contrast", "quiet edge hit"]),
   ("no jobs", [])]

private def frJ (f : Frame) : Json :=
  Json.mkObj [("recalcs", f.recalcs), ("keys", Json.arr (f.keys.map Json.str).toArray), ("sizes", Json.arr (f.sizes.map fun n => toJson n).toArray)]

/-- Consecutive equal frames as (n, frame) runs: the golden stays short. -/
def runs (fs : List Frame) : List (Nat × Frame) :=
  fs.foldr (fun f acc => match acc with
    | (n, g) :: t => if f == g then (n + 1, g) :: t else (1, f) :: acc
    | [] => [(1, f)]) []

private def runsJ (fs : List Frame) : Json :=
  Json.arr ((runs fs).map fun (n, f) => Json.mkObj [("n", n), ("f", frJ f)]).toArray

private def jobJ (j : Job) : Json :=
  Json.mkObj [("floor", runsJ j.floor), ("base", runsJ j.base),
    ("ivs", Json.arr (j.ivs.map fun (k, fs) => Json.mkObj [("kind", k), ("frames", runsJ fs)]).toArray)]

private def strs (xs : List String) : Json := Json.arr (xs.map Json.str).toArray

private def optJ : Option String → Json
  | some s => Json.str s
  | none => Json.null

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("coverMinPct", coverMinPct), ("absentMinPct", absentMinPct), ("minQ", minQ),
    ("residualMin", residualMin), ("shiftMax", shiftMax), ("fellMax", fellMax), ("minValid", minValid)]).compress] ++
  (cases.map fun (n, mf, j) =>
    let r := j.res mf
    (Json.mkObj [("kind", "job"), ("name", n), ("mf", mf), ("job", jobJ j), ("floorRpf", rpf100 j.floor), ("baseRpf", rpf100 j.base),
      ("withRecalc", j.withRecalc.length), ("withoutRecalc", j.withoutRecalc.length), ("suspects", strs (j.suspects mf)),
      ("sources", strs (j.sources mf)), ("why", r.why.name), ("valid", r.why.valid), ("src", optJ r.src),
      ("emptyPm", emptyPm j.base)]).compress) ++
  (combos.map fun (n, ns) =>
    let v := overall (ns.map fun m => let (mf, j) := caseOf m; j.res mf)
    (Json.mkObj [("kind", "overall"), ("name", n), ("jobs", strs ns), ("verdict", v.name), ("next", v.next.name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-recalc-source golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-recalc-source golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "recalc-source.jsonl"

def checkRepo : IO Unit := do
  if (← run ["--check", goldenPath.toString]) != 0 then throw (IO.userError "device-recalc-source golden differs")

end Fw.Device.RecalcSource
