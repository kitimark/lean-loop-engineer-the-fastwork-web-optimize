/-!
# The phone feel session
Blind order, 1-5 scores and per-arm verdicts of `packages/measure-webkit/src/device-feel.mjs`.
-/
namespace Fw.Device.Feel

structure Arm where
  id : String
  flags : List String
  text : String

def dropPart (part : String) (list : List String) : List String := list.filter fun f => !f.startsWith (part ++ ":")

def sameArmsOf (preset : List String) : List Arm :=
  [⟨"base", [], ""⟩, ⟨"v2-proved", preset, ""⟩, ⟨"v2-proved-2flag", dropPart "platform" preset, ""⟩]

def lookArms : List Arm :=
  [⟨"nav:earn-logical", ["nav:earn-logical"], "the Join waitlist button in the nav animates when the nav changes, as it does on a desktop browser"⟩,
   ⟨"platform.glint:compositor", ["platform.glint:compositor"], "the shiny dash on the platform line glides; check it does not stutter or jump"⟩,
   ⟨"morph.end.nobounce", ["morph.end.nobounce:on"], "the page end does not bounce"⟩,
   ⟨"morph.stage", ["morph.stage:on"], "the nav morph at the page end follows your finger; the page is longer"⟩]

theorem lookArms_length : lookArms.length = 4 := rfl

theorem arm_ids_nodup (preset : List String) :
    ((sameArmsOf preset).map (·.id) ++ lookArms.map (·.id)).Nodup := by
  simp only [sameArmsOf, lookArms, List.map_cons, List.map_nil, List.cons_append, List.nil_append]
  decide

def doText : String := "Scroll slowly to the end, push through the end, scroll back up once."
def rateText : String := "Rate how smooth it felt, 1 (rough) to 5 (smooth)."

def nSame : Nat := 3
def baseArm : Nat := 0
def repeats : Nat := 2
def scoreMin : Nat := 1
def scoreMax : Nat := 5
def margin : Nat := 1

theorem sameArmsOf_length (preset : List String) : (sameArmsOf preset).length = nSame := rfl

theorem sameArmsOf_proved (preset : List String) : ((sameArmsOf preset)[1]?).map (·.flags) = some preset := rfl

theorem sameArmsOf_base (preset : List String) : ((sameArmsOf preset)[baseArm]?).map (·.flags) = some [] := rfl

theorem dropPart_sublist (part : String) (list : List String) : (dropPart part list).Sublist list :=
  List.filter_sublist

theorem dropPart_isolates {part : String} {list : List String} {f : String} (h : f ∈ list)
    (hn : f ∉ dropPart part list) : f.startsWith (part ++ ":") = true := by
  cases hb : f.startsWith (part ++ ":")
  · exact absurd (List.mem_filter.mpr ⟨h, by simp [hb]⟩) hn
  · rfl

theorem dropPart_none {part : String} {list : List String} {f : String} (h : f ∈ dropPart part list) :
    f.startsWith (part ++ ":") = false := by
  have := (List.mem_filter.mp h).2
  simpa using this

theorem dropPart_noop {part : String} {list : List String} (h : ∀ f ∈ list, f.startsWith (part ++ ":") = false) :
    dropPart part list = list :=
  List.filter_eq_self.mpr fun f hf => by simp [h f hf]

def rot (n r : Nat) : List Nat := (List.range n).map fun i => (i + r) % n

def orderR (r : Nat) : List Nat := rot nSame r ++ rot nSame (r + 1)

def order (seed : Nat) : List Nat := orderR (seed % nSame)

def noRepeat : List Nat → Bool
  | a :: b :: t => a != b && noRepeat (b :: t)
  | _ => true

theorem order_length (seed : Nat) : (order seed).length = repeats * nSame := by
  have : ∀ r, r < 3 → (orderR r).length = 6 := by decide
  exact this _ (Nat.mod_lt _ (by decide))

theorem order_lt (seed : Nat) : ∀ a ∈ order seed, a < nSame := by
  have : ∀ r, r < 3 → ∀ a ∈ orderR r, a < 3 := by decide
  exact this _ (Nat.mod_lt _ (by decide))

theorem order_count (seed : Nat) : ∀ k, k < nSame → (order seed).count k = repeats := by
  have : ∀ r, r < 3 → ∀ k, k < 3 → (orderR r).count k = 2 := by decide
  exact this _ (Nat.mod_lt _ (by decide))

theorem order_noRepeat (seed : Nat) : noRepeat (order seed) = true := by
  have : ∀ r, r < 3 → noRepeat (orderR r) = true := by decide
  exact this _ (Nat.mod_lt _ (by decide))

structure Visit where
  arm : Nat
  round : Nat
  label : Nat
  deriving DecidableEq

def visitsOf (seed : Nat) : List Visit :=
  (order seed).mapIdx fun i a => ⟨a, i / nSame, i⟩

def letter (i : Nat) : Char := Char.ofNat (65 + i)

theorem labels_fresh (seed : Nat) : (visitsOf seed).map (·.label) = [0, 1, 2, 3, 4, 5] := by
  have : ∀ r, r < 3 → ((orderR r).mapIdx fun i a => (⟨a, i / 3, i⟩ : Visit)).map (·.label) = [0, 1, 2, 3, 4, 5] := by decide
  exact this _ (Nat.mod_lt _ (by decide))

theorem labels_nodup (seed : Nat) : ((visitsOf seed).map (·.label)).Nodup := by
  rw [labels_fresh]; decide

theorem one_per_round (seed : Nat) : ∀ a, a < nSame → ∀ j, j < repeats →
    ((visitsOf seed).filter fun v => v.arm == a && v.round == j).length = 1 := by
  have : ∀ r, r < 3 → ∀ a, a < 3 → ∀ j, j < 2 →
      (((orderR r).mapIdx fun i a => (⟨a, i / 3, i⟩ : Visit)).filter fun v => v.arm == a && v.round == j).length = 1 := by decide
  exact this _ (Nat.mod_lt _ (by decide))

theorem first_label_A (seed : Nat) : (visitsOf seed).head?.map (·.label) = some 0 := by
  have : ∀ r, r < 3 → (((orderR r).mapIdx fun i a => (⟨a, i / 3, i⟩ : Visit)).head?.map (·.label)) = some 0 := by decide
  exact this _ (Nat.mod_lt _ (by decide))

inductive Cell where
  | better | same | worse
  deriving DecidableEq

def Cell.flip : Cell → Cell
  | .better => .worse | .same => .same | .worse => .better

def cell (x b : Nat) : Cell :=
  if b + margin ≤ x then .better else if x + margin ≤ b then .worse else .same

theorem cell_better {x b : Nat} (h : b + margin ≤ x) : cell x b = .better := by simp [cell, h]

theorem cell_worse {x b : Nat} (h : x + margin ≤ b) : cell x b = .worse := by
  have : ¬ (b + margin ≤ x) := by unfold margin at *; omega
  simp [cell, this, h]

theorem cell_same {x b : Nat} (h1 : x < b + margin) (h2 : b < x + margin) : cell x b = .same := by
  have h3 : ¬ (b + margin ≤ x) := by unfold margin at *; omega
  have h4 : ¬ (x + margin ≤ b) := by unfold margin at *; omega
  simp [cell, h3, h4]

theorem cell_swap (x b : Nat) : cell b x = (cell x b).flip := by
  by_cases h1 : b + margin ≤ x
  · have h2 : ¬ x + margin ≤ b := by unfold margin at *; omega
    simp [cell, h1, h2, Cell.flip]
  · by_cases h2 : x + margin ≤ b <;> simp [cell, h1, h2, Cell.flip]

inductive Verdict where
  | better | same | worse | mixed | unrated
  deriving DecidableEq

def Verdict.flip : Verdict → Verdict
  | .better => .worse | .worse => .better | v => v

def Verdict.code : Verdict → String
  | .better => "better" | .same => "same" | .worse => "worse" | .mixed => "mixed" | .unrated => "unrated"

def Verdict.text : Verdict → String
  | .better => "felt better" | .same => "same" | .worse => "felt worse" | .mixed => "mixed" | .unrated => "not rated"

def Cell.verdict : Cell → Verdict
  | .better => .better | .same => .same | .worse => .worse

def verdict2 (a b : Cell) : Verdict := if a = b then a.verdict else .mixed

def reduceArm (xs bs : List Nat) : Verdict :=
  match xs, bs with
  | [x1, x2], [b1, b2] => verdict2 (cell x1 b1) (cell x2 b2)
  | _, _ => .unrated

def reduceLook (xs bs : List Nat) : Verdict :=
  match xs with
  | [x] => reduceArm [x, x] bs
  | _ => .unrated

theorem verdict2_agree (a : Cell) : verdict2 a a = a.verdict := by simp [verdict2]

theorem verdict2_mixed {a b : Cell} (h : a ≠ b) : verdict2 a b = .mixed := by simp [verdict2, h]

theorem reduceArm_better {x1 x2 b1 b2 : Nat} (h1 : b1 + margin ≤ x1) (h2 : b2 + margin ≤ x2) :
    reduceArm [x1, x2] [b1, b2] = .better := by
  simp [reduceArm, cell_better h1, cell_better h2, verdict2_agree, Cell.verdict]

theorem reduceArm_worse {x1 x2 b1 b2 : Nat} (h1 : x1 + margin ≤ b1) (h2 : x2 + margin ≤ b2) :
    reduceArm [x1, x2] [b1, b2] = .worse := by
  simp [reduceArm, cell_worse h1, cell_worse h2, verdict2_agree, Cell.verdict]

theorem reduceArm_same {x1 x2 b1 b2 : Nat} (h1 : x1 < b1 + margin) (h1' : b1 < x1 + margin)
    (h2 : x2 < b2 + margin) (h2' : b2 < x2 + margin) : reduceArm [x1, x2] [b1, b2] = .same := by
  simp [reduceArm, cell_same h1 h1', cell_same h2 h2', verdict2_agree, Cell.verdict]

theorem reduceArm_mixed {x1 x2 b1 b2 : Nat} (h : cell x1 b1 ≠ cell x2 b2) :
    reduceArm [x1, x2] [b1, b2] = .mixed := by
  simp [reduceArm, verdict2_mixed h]

theorem reduceArm_unrated {xs bs : List Nat} (h : xs.length ≠ repeats ∨ bs.length ≠ repeats) :
    reduceArm xs bs = .unrated := by
  match xs, bs, h with
  | [], _, _ | [_], _, _ => simp [reduceArm]
  | _ :: _ :: _ :: _, _, _ => simp [reduceArm]
  | [_, _], [], _ | [_, _], [_], _ => simp [reduceArm]
  | [_, _], _ :: _ :: _ :: _, _ => simp [reduceArm]
  | [_, _], [_, _], h => simp [repeats] at h

theorem Verdict.flip_flip (v : Verdict) : v.flip.flip = v := by cases v <;> rfl

theorem verdict2_flip (a b : Cell) : verdict2 a.flip b.flip = (verdict2 a b).flip := by
  cases a <;> cases b <;> simp [verdict2, Cell.flip, Cell.verdict, Verdict.flip]

theorem reduceArm_swap (x1 x2 b1 b2 : Nat) :
    reduceArm [b1, b2] [x1, x2] = (reduceArm [x1, x2] [b1, b2]).flip := by
  simp [reduceArm, cell_swap b1 x1, cell_swap b2 x2, verdict2_flip, Verdict.flip_flip]

theorem reduceArm_self (x1 x2 : Nat) : reduceArm [x1, x2] [x1, x2] = .same := by
  apply reduceArm_same <;> simp [margin]

theorem reduceLook_one {x b1 b2 : Nat} : reduceLook [x] [b1, b2] = reduceArm [x, x] [b1, b2] := rfl

theorem reduceLook_unrated {xs : List Nat} (h : xs.length ≠ 1) (bs : List Nat) : reduceLook xs bs = .unrated := by
  match xs, h with
  | [], _ | _ :: _ :: _, _ => simp [reduceLook]
  | [_], h => simp at h

def validScore (s : Nat) : Bool := scoreMin ≤ s && s ≤ scoreMax

def scoresOf (seed : Nat) (rs : List (Option Nat)) (a : Nat) : List Nat :=
  ((order seed).zip rs).filterMap fun p => if p.1 = a then p.2 else none

def sameVerdict (seed : Nat) (rs : List (Option Nat)) (a : Nat) : Verdict :=
  reduceArm (scoresOf seed rs a) (scoresOf seed rs baseArm)

def lookVerdict (seed : Nat) (rs : List (Option Nat)) (x : Option Nat) : Verdict :=
  reduceLook (x.toList) (scoresOf seed rs baseArm)

theorem sameVerdict_base (seed : Nat) (rs : List (Option Nat)) (h : (scoresOf seed rs baseArm).length = repeats) :
    sameVerdict seed rs baseArm = .same := by
  unfold sameVerdict
  match hs : scoresOf seed rs baseArm, h with
  | [x1, x2], _ => exact reduceArm_self x1 x2
  | [], h | [_], h | _ :: _ :: _ :: _, h => simp [repeats] at h

theorem scores_complete (seed : Nat) (s0 s1 s2 s3 s4 s5 : Nat) :
    ∀ a, a < nSame → (scoresOf seed [some s0, some s1, some s2, some s3, some s4, some s5] a).length = repeats := by
  have : ∀ r, r < 3 → ∀ a, a < 3 →
      (((orderR r).zip [some s0, some s1, some s2, some s3, some s4, some s5]).filterMap fun p => if p.1 = a then p.2 else none).length = 2 := by
    intro r hr a ha
    obtain rfl | rfl | rfl : r = 0 ∨ r = 1 ∨ r = 2 := by omega
    all_goals obtain rfl | rfl | rfl : a = 0 ∨ a = 1 ∨ a = 2 := by omega
    all_goals rfl
  intro a ha
  exact this _ (Nat.mod_lt _ (by decide)) a ha

structure Capture where
  moving : Nat
  long17 : Nat
  long33 : Nat
  pins : Nat
  fights : Nat
  reversals : Nat
  retargets : Nat
  blinks : Nat
  zoneWork : List Nat
  deriving DecidableEq

def Capture.score (c : Capture) : Nat := c.long33 + c.fights + c.blinks

def medianOf (l : List Nat) : Nat := (l.mergeSort (· ≤ ·)).getD (l.length / 2) 0

def addZones : List Nat → List Nat → List Nat
  | [], b => b
  | a, [] => a
  | x :: a, y :: b => (x + y) :: addZones a b

def topZone (w : List Nat) : Option Nat :=
  let m := w.foldl max 0
  if m = 0 then none else w.findIdx? (· == m)

structure Summary where
  visits : Nat
  long17 : Nat
  long33 : Nat
  fights : Nat
  blinks : Nat
  topZone : Option Nat
  deriving DecidableEq

def Summary.score (s : Summary) : Nat := s.long33 + s.fights + s.blinks

def summaryOf (cs : List Capture) : Option Summary :=
  if cs.isEmpty then none
  else some ⟨cs.length, medianOf (cs.map (·.long17)), medianOf (cs.map (·.long33)), medianOf (cs.map (·.fights)),
    medianOf (cs.map (·.blinks)), topZone (cs.foldl (fun acc c => addZones acc c.zoneWork) [])⟩

def capMargin : Nat := 2

inductive Dir where
  | lighter | same | heavier
  deriving DecidableEq

def Dir.flip : Dir → Dir
  | .lighter => .heavier | .same => .same | .heavier => .lighter

def Dir.code : Dir → String
  | .lighter => "lighter" | .same => "same" | .heavier => "heavier"

def measured (a b : Summary) : Dir :=
  if b.score + capMargin ≤ a.score then .heavier else if a.score + capMargin ≤ b.score then .lighter else .same

theorem measured_heavier {a b : Summary} (h : b.score + capMargin ≤ a.score) : measured a b = .heavier := by simp [measured, h]

theorem measured_lighter {a b : Summary} (h : a.score + capMargin ≤ b.score) : measured a b = .lighter := by
  have : ¬ (b.score + capMargin ≤ a.score) := by unfold capMargin at *; omega
  simp [measured, this, h]

theorem measured_same {a b : Summary} (h1 : a.score < b.score + capMargin) (h2 : b.score < a.score + capMargin) :
    measured a b = .same := by
  have h3 : ¬ (b.score + capMargin ≤ a.score) := by unfold capMargin at *; omega
  have h4 : ¬ (a.score + capMargin ≤ b.score) := by unfold capMargin at *; omega
  simp [measured, h3, h4]

theorem measured_swap (a b : Summary) : measured b a = (measured a b).flip := by
  by_cases h1 : b.score + capMargin ≤ a.score
  · have h2 : ¬ a.score + capMargin ≤ b.score := by unfold capMargin at *; omega
    simp [measured, h1, h2, Dir.flip]
  · by_cases h2 : a.score + capMargin ≤ b.score <;> simp [measured, h1, h2, Dir.flip]

theorem measured_self (a : Summary) : measured a a = .same := by
  apply measured_same <;> (unfold capMargin; omega)

inductive Flag where
  | none | feltWorseMeasuredLighter | feltBetterMeasuredHeavier
  deriving DecidableEq

def Flag.code : Flag → String
  | .none => "none" | .feltWorseMeasuredLighter => "felt worse, measured lighter" | .feltBetterMeasuredHeavier => "felt better, measured heavier"

def Flag.flip : Flag → Flag
  | .none => .none | .feltWorseMeasuredLighter => .feltBetterMeasuredHeavier | .feltBetterMeasuredHeavier => .feltWorseMeasuredLighter

def flagOf (v : Verdict) (d : Option Dir) : Flag :=
  match v, d with
  | .worse, some .lighter => .feltWorseMeasuredLighter
  | .better, some .heavier => .feltBetterMeasuredHeavier
  | _, _ => .none

theorem flagOf_worse_lighter : flagOf .worse (some .lighter) = .feltWorseMeasuredLighter := rfl

theorem flagOf_better_heavier : flagOf .better (some .heavier) = .feltBetterMeasuredHeavier := rfl

theorem flagOf_worse_not_lighter {d : Dir} (h : d ≠ .lighter) : flagOf .worse (some d) = .none := by
  cases d <;> simp_all [flagOf]

theorem flagOf_better_not_heavier {d : Dir} (h : d ≠ .heavier) : flagOf .better (some d) = .none := by
  cases d <;> simp_all [flagOf]

theorem flagOf_unmeasured (v : Verdict) : flagOf v none = .none := by cases v <;> rfl

theorem flagOf_quiet {v : Verdict} (h : v = .same ∨ v = .mixed ∨ v = .unrated) (d : Option Dir) : flagOf v d = .none := by
  rcases h with rfl | rfl | rfl <;> cases d <;> simp [flagOf] <;> split <;> rfl

theorem flagOf_flip (v : Verdict) (d : Dir) : flagOf v.flip (some d.flip) = (flagOf v (some d)).flip := by
  cases v <;> cases d <;> rfl

structure Joint where
  verdict : Verdict
  summary : Option Summary
  flag : Flag
  deriving DecidableEq

def capturesOf (seed : Nat) (caps : List (Option Capture)) (a : Nat) : List Capture :=
  ((order seed).zip caps).filterMap fun p => if p.1 = a then p.2 else none

def jointWith (v : Verdict) (cs bs : List Capture) : Joint :=
  let s := summaryOf cs
  ⟨v, s, flagOf v (match s, summaryOf bs with | some s, some b => some (measured s b) | _, _ => none)⟩

def jointSame (seed : Nat) (rs : List (Option Nat)) (caps : List (Option Capture)) (a : Nat) : Joint :=
  jointWith (sameVerdict seed rs a) (capturesOf seed caps a) (capturesOf seed caps baseArm)

def jointLook (seed : Nat) (rs : List (Option Nat)) (caps : List (Option Capture)) (x : Option Nat) (c : Option Capture) : Joint :=
  jointWith (lookVerdict seed rs x) c.toList (capturesOf seed caps baseArm)

theorem jointWith_base_quiet (v : Verdict) (cs : List Capture) : (jointWith v cs cs).flag = .none := by
  unfold jointWith
  cases h : summaryOf cs with
  | none => simp [flagOf_unmeasured]
  | some s => simp [measured_self]; cases v <;> rfl

theorem jointWith_flag_worse {cs bs : List Capture} {s b : Summary} (hs : summaryOf cs = some s) (hb : summaryOf bs = some b)
    (h : s.score + capMargin ≤ b.score) : (jointWith .worse cs bs).flag = .feltWorseMeasuredLighter := by
  simp [jointWith, hs, hb, measured_lighter h, flagOf]

theorem jointWith_flag_better {cs bs : List Capture} {s b : Summary} (hs : summaryOf cs = some s) (hb : summaryOf bs = some b)
    (h : b.score + capMargin ≤ s.score) : (jointWith .better cs bs).flag = .feltBetterMeasuredHeavier := by
  simp [jointWith, hs, hb, measured_heavier h, flagOf]

theorem jointWith_unmeasured (v : Verdict) {cs : List Capture} (h : summaryOf cs = none) (bs : List Capture) :
    (jointWith v cs bs).flag = .none := by
  simp [jointWith, h, flagOf_unmeasured]

theorem jointSame_verdict (seed : Nat) (rs : List (Option Nat)) (caps : List (Option Capture)) (a : Nat) :
    (jointSame seed rs caps a).verdict = sameVerdict seed rs a := rfl

theorem jointSame_base_quiet (seed : Nat) (rs : List (Option Nat)) (caps : List (Option Capture)) :
    (jointSame seed rs caps baseArm).flag = .none := jointWith_base_quiet _ _

inductive LockState where
  | locked | unlocked | unknown
  deriving DecidableEq

structure Facts where
  listed : Bool
  paired : Bool
  connected : Bool
  usb : Bool
  lock : LockState

inductive Probe where
  | ready | notListed | notPaired | notConnected | notUsb | locked | lockUnknown
  deriving DecidableEq

def probeOf (f : Facts) : Probe :=
  if !f.listed then .notListed
  else if !f.paired then .notPaired
  else if !f.connected then .notConnected
  else if !f.usb then .notUsb
  else match f.lock with
    | .locked => .locked
    | .unknown => .lockUnknown
    | .unlocked => .ready

def Probe.code : Probe → String
  | .ready => "ready" | .notListed => "notListed" | .notPaired => "notPaired" | .notConnected => "notConnected"
  | .notUsb => "notUsb" | .locked => "locked" | .lockUnknown => "lockUnknown"

def Probe.ask : Probe → String
  | .ready => ""
  | .notListed => "The Mac does not list the iPhone: plug it into the Mac with the USB cable."
  | .notPaired => "The iPhone is not paired with the Mac: unlock it and tap Trust on the phone."
  | .notConnected => "The iPhone is listed but not connected: unlock it and replug the USB cable."
  | .notUsb => "The iPhone is not on USB: replug the USB cable."
  | .locked => "The iPhone is locked: unlock it and keep it awake."
  | .lockUnknown => "The Mac could not read the iPhone lock state: unlock it, keep it awake and run the script again."

theorem probe_notListed {f : Facts} (h : f.listed = false) : probeOf f = .notListed := by simp [probeOf, h]

theorem probe_notPaired {f : Facts} (h1 : f.listed = true) (h : f.paired = false) : probeOf f = .notPaired := by
  simp [probeOf, h1, h]

theorem probe_notConnected {f : Facts} (h1 : f.listed = true) (h2 : f.paired = true) (h : f.connected = false) :
    probeOf f = .notConnected := by simp [probeOf, h1, h2, h]

theorem probe_notUsb {f : Facts} (h1 : f.listed = true) (h2 : f.paired = true) (h3 : f.connected = true)
    (h : f.usb = false) : probeOf f = .notUsb := by simp [probeOf, h1, h2, h3, h]

theorem probe_locked {f : Facts} (h1 : f.listed = true) (h2 : f.paired = true) (h3 : f.connected = true)
    (h4 : f.usb = true) (h : f.lock = .locked) : probeOf f = .locked := by simp [probeOf, h1, h2, h3, h4, h]

theorem probe_lockUnknown {f : Facts} (h1 : f.listed = true) (h2 : f.paired = true) (h3 : f.connected = true)
    (h4 : f.usb = true) (h : f.lock = .unknown) : probeOf f = .lockUnknown := by
  simp [probeOf, h1, h2, h3, h4, h]

theorem probe_ready_iff (f : Facts) :
    probeOf f = .ready ↔ f.listed = true ∧ f.paired = true ∧ f.connected = true ∧ f.usb = true ∧ f.lock = .unlocked := by
  unfold probeOf
  cases f with
  | mk a b c d l => cases a <;> cases b <;> cases c <;> cases d <;> cases l <;> simp

theorem ask_ready : Probe.ready.ask = "" := rfl

theorem ask_nonempty (p : Probe) (h : p ≠ .ready) : p.ask ≠ "" := by
  cases p <;> first | exact absurd rfl h | decide

inductive Fail where
  | webInspector | locked | notUsb | other
  deriving DecidableEq

def hasSub (s p : String) : Bool := (s.splitOn p).length > 1

def failOf (msg : String) : Fail :=
  if hasSub msg "phone is locked" then .locked
  else if hasSub msg "not on USB" then .notUsb
  else if hasSub msg "listed no tabs" || hasSub msg "0 of 0 tabs" then .webInspector
  else .other

def Fail.code : Fail → String
  | .webInspector => "webInspector" | .locked => "locked" | .notUsb => "notUsb" | .other => "other"

def Fail.ask : Fail → String
  | .webInspector => "The Mac sees no Safari tab: unlock the iPhone, and turn Web Inspector on in the Safari Advanced settings."
  | .locked => Probe.locked.ask
  | .notUsb => Probe.notUsb.ask
  | .other => "The session did not start: read the last log lines below."

theorem failOf_locked (msg : String) (h : hasSub msg "phone is locked" = true) : failOf msg = .locked := by
  simp [failOf, h]

def fixedS : Nat := 285

def visitS : Nat := 95

def visitCount : Nat := repeats * nSame + lookArms.length

def estimateS (visits : Nat) : Nat := fixedS + visits * visitS

def estimateMin (visits : Nat) : Nat := (estimateS visits + 59) / 60

theorem visitCount_eq : visitCount = 10 := rfl

theorem estimateS_succ (v : Nat) : estimateS (v + 1) = estimateS v + visitS := by
  simp [estimateS, Nat.add_mul]; omega

theorem estimateS_mono {a b : Nat} (h : a ≤ b) : estimateS a ≤ estimateS b := by
  unfold estimateS; exact Nat.add_le_add_left (Nat.mul_le_mul_right _ h) _

theorem estimateMin_ge (v : Nat) : estimateS v ≤ estimateMin v * 60 := by
  unfold estimateMin; omega

end Fw.Device.Feel
