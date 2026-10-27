import Lean.Data.Json
import Fw.Device.Session
import Fw.Measure.WebKitProfile
namespace Fw.Device.PhoneArms
open Lean
open Fw.Device.Session (Zone zoneOf Verdict verdict spread sameFlags sameFlags_comm sameFlags_refl)
open Fw.Measure.WebKitProfile (driftOk offsetOf meanOffset)

inductive Target where
  | original | rewrite
  deriving DecidableEq, Repr

def Target.name : Target → String
  | .original => "original" | .rewrite => "rewrite"

structure Arm where
  id : String
  target : Target
  flags : List String
  deriving DecidableEq, Repr

def samePage (a b : Arm) : Bool := a.target == b.target && sameFlags a.flags b.flags

theorem samePage_comm (a b : Arm) : samePage a b = samePage b a := by
  have h : (a.target == b.target) = (b.target == a.target) := by
    generalize a.target = x
    generalize b.target = y
    cases x <;> cases y <;> rfl
  unfold samePage
  rw [h, sameFlags_comm a.flags b.flags]

theorem samePage_refl (a : Arm) : samePage a a = true := by
  simp [samePage, sameFlags_refl]

def base : Arm := ⟨"base", .rewrite, []⟩

def original : Arm := ⟨"original", .original, []⟩

private def flagArm (flags : List String) : Arm := ⟨flags.getLast!, .rewrite, flags⟩

def flagArms : List Arm :=
  [flagArm ["hero.exit:threaded"], flagArm ["hero:scene-pause"], flagArm ["morph.columns:idle-none"],
   flagArm ["morph.countdown:hidden-pause"], flagArm ["hero.countdown:strip", "morph.countdown:strip"],
   flagArm ["nav.hitTest:hit-skip"], flagArm ["engine.events:quiet"], flagArm ["morph.panel:const-bounds"],
   flagArm ["nav:clip-box"], flagArm ["nav:bar-fixed"], flagArm ["nav:logo-3d"], flagArm ["morph.mount:shift-dormant"]]

def candidates : List Arm := base :: original :: flagArms

def dedupAux : List Arm → List Arm → List Arm
  | _, [] => []
  | seen, x :: rest => if seen.any (samePage x) then dedupAux seen rest else x :: dedupAux (x :: seen) rest

def dedup (xs : List Arm) : List Arm := dedupAux [] xs

theorem dedupAux_sub : ∀ (seen xs : List Arm) {x}, x ∈ dedupAux seen xs → x ∈ xs
  | _, [], _, h => by simp [dedupAux] at h
  | seen, y :: rest, x, h => by
    unfold dedupAux at h
    split at h
    · exact List.mem_cons_of_mem _ (dedupAux_sub seen rest h)
    · rcases List.mem_cons.mp h with rfl | h
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (dedupAux_sub _ rest h)

theorem dedupAux_fresh : ∀ (seen xs : List Arm) {x}, x ∈ dedupAux seen xs → seen.any (samePage x) = false
  | _, [], _, h => by simp [dedupAux] at h
  | seen, y :: rest, x, h => by
    unfold dedupAux at h
    split at h
    · exact dedupAux_fresh seen rest h
    · rcases List.mem_cons.mp h with rfl | h
      · simp_all
      · have := dedupAux_fresh _ rest h
        simp only [List.any_cons, Bool.or_eq_false_iff] at this
        exact this.2

theorem dedupAux_pairwise : ∀ (seen xs : List Arm), (dedupAux seen xs).Pairwise (fun p q => samePage p q = false)
  | _, [] => by simp [dedupAux]
  | seen, y :: rest => by
    unfold dedupAux
    split
    · exact dedupAux_pairwise seen rest
    · refine List.Pairwise.cons ?_ (dedupAux_pairwise _ rest)
      intro q hq
      have := dedupAux_fresh _ rest hq
      simp only [List.any_cons, Bool.or_eq_false_iff] at this
      rw [samePage_comm]; exact this.1

theorem dedupAux_covered : ∀ (seen xs : List Arm) {x}, x ∈ xs →
    (∃ s ∈ seen, samePage x s = true) ∨ ∃ y ∈ dedupAux seen xs, samePage x y = true
  | _, [], _, h => by simp at h
  | seen, y :: rest, x, h => by
    unfold dedupAux
    split
    · rename_i hs
      rcases List.mem_cons.mp h with rfl | h
      · left
        obtain ⟨s, hs', hss⟩ := List.any_eq_true.mp hs
        exact ⟨s, hs', hss⟩
      · exact dedupAux_covered seen rest h
    · rcases List.mem_cons.mp h with rfl | h
      · right; exact ⟨x, List.mem_cons_self, samePage_refl _⟩
      · rcases dedupAux_covered (y :: seen) rest h with ⟨s, hs, hss⟩ | ⟨z, hz, hzz⟩
        · rcases List.mem_cons.mp hs with rfl | hs
          · right; exact ⟨s, List.mem_cons_self, hss⟩
          · left; exact ⟨s, hs, hss⟩
        · right; exact ⟨z, List.mem_cons_of_mem _ hz, hzz⟩

theorem dedup_sub {xs : List Arm} {x : Arm} (h : x ∈ dedup xs) : x ∈ xs := dedupAux_sub [] xs h

theorem dedup_pairwise (xs : List Arm) : (dedup xs).Pairwise (fun p q => samePage p q = false) :=
  dedupAux_pairwise [] xs

theorem dedup_covered {xs : List Arm} {x : Arm} (h : x ∈ xs) : ∃ y ∈ dedup xs, samePage x y = true := by
  rcases dedupAux_covered [] xs h with ⟨s, hs, _⟩ | h
  · simp at hs
  · exact h

theorem dedup_head (a : Arm) (rest : List Arm) : (dedup (a :: rest)).head? = some a := by
  simp [dedup, dedupAux]

theorem dedup_length_le (xs : List Arm) : (dedup xs).length ≤ xs.length := by
  have : ∀ (seen xs : List Arm), (dedupAux seen xs).length ≤ xs.length := by
    intro seen xs
    induction xs generalizing seen with
    | nil => simp [dedupAux]
    | cons y rest ih =>
      unfold dedupAux
      split
      · exact Nat.le_succ_of_le (ih seen)
      · simp only [List.length_cons]; exact Nat.succ_le_succ (ih _)
  exact this [] xs

theorem dedup_distinct (a b c : Arm) (hab : samePage a b = false) (hac : samePage a c = false)
    (hbc : samePage b c = false) : dedup [a, b, c] = [a, b, c] := by
  have hba : samePage b a = false := by rw [samePage_comm]; exact hab
  have hca : samePage c a = false := by rw [samePage_comm]; exact hac
  have hcb : samePage c b = false := by rw [samePage_comm]; exact hbc
  simp [dedup, dedupAux, hba, hca, hcb]

theorem dedup_twin (a b : Arm) (h : samePage b a = true) : dedup [a, b] = [a] := by
  simp [dedup, dedupAux, h]

def others : List Arm := (dedup candidates).drop 1

theorem original_kept : original ∈ others := by decide

theorem others_length : others.length = 13 := by decide

def visits (b : Arm) (os : List Arm) : List Arm :=
  (b :: (os.take (os.length / 2) ++ b :: (os.drop (os.length / 2)).reverse)) ++ [b]

theorem visits_length (b : Arm) (os : List Arm) : (visits b os).length = os.length + 3 := by
  have h1 : (os.take (os.length / 2)).length = os.length / 2 := by simp; omega
  have h2 : (os.drop (os.length / 2)).length = os.length - os.length / 2 := by simp
  simp [visits, h1, h2]
  omega

theorem visits_head (b : Arm) (os : List Arm) : (visits b os).head? = some b := by
  simp [visits]

theorem visits_last (b : Arm) (os : List Arm) : (visits b os).getLast? = some b := by
  unfold visits
  rw [List.getLast?_concat]

theorem visits_mid (b : Arm) (os : List Arm) : (visits b os)[os.length / 2 + 1]? = some b := by
  have h1 : (os.take (os.length / 2)).length = os.length / 2 := by simp; omega
  unfold visits
  rw [List.getElem?_append_left (by simp [h1]), List.getElem?_cons_succ, List.getElem?_append_right (by omega)]
  simp [h1]

theorem visits_perm (b : Arm) (os : List Arm) : (visits b os).Perm (b :: b :: b :: os) := by
  have hp : (os.take (os.length / 2) ++ (os.drop (os.length / 2)).reverse).Perm os := by
    refine List.Perm.trans (List.Perm.append_left _ (List.reverse_perm _)) ?_
    rw [List.take_append_drop]
  unfold visits
  have h1 : (os.take (os.length / 2) ++ b :: (os.drop (os.length / 2)).reverse).Perm
      (b :: (os.take (os.length / 2) ++ (os.drop (os.length / 2)).reverse)) := List.perm_middle
  have h2 := List.perm_append_singleton b (os.take (os.length / 2) ++ b :: (os.drop (os.length / 2)).reverse)
  simp only [List.cons_append]
  refine List.Perm.cons b ?_
  refine List.Perm.trans h2 ?_
  exact List.Perm.cons b (List.Perm.trans h1 (List.Perm.cons b hp))

def sessionVisits : List Arm := visits base others

theorem sessionVisits_length : sessionVisits.length = 16 := by decide

def blocksAux {α : Type} : Nat → Nat → List α → List (List α)
  | 0, _, _ => []
  | _ + 1, _, [] => []
  | n + 1, per, l => l.take per :: blocksAux n per (l.drop per)

def blocks {α : Type} (per : Nat) (l : List α) : List (List α) := blocksAux l.length per l

theorem blocksAux_flatten {α : Type} {per : Nat} (hp : 0 < per) :
    ∀ (n : Nat) (l : List α), l.length ≤ n → (blocksAux n per l).flatten = l
  | 0, l, h => by
    have : l = [] := List.length_eq_zero_iff.mp (by omega)
    subst this; simp [blocksAux]
  | n + 1, l, h => by
    cases l with
    | nil => simp [blocksAux]
    | cons x xs =>
      simp only [blocksAux, List.flatten_cons]
      rw [blocksAux_flatten hp n _ (by simp only [List.length_drop, List.length_cons] at h ⊢; omega)]
      exact List.take_append_drop _ _

theorem blocksAux_len {α : Type} {per : Nat} : ∀ (n : Nat) (l : List α), ∀ b ∈ blocksAux n per l, b.length ≤ per
  | 0, _, b, h => by simp [blocksAux] at h
  | n + 1, l, b, h => by
    cases l with
    | nil => simp [blocksAux] at h
    | cons x xs =>
      simp only [blocksAux, List.mem_cons] at h
      rcases h with rfl | h
      · simp only [List.length_take]; exact Nat.min_le_left _ _
      · exact blocksAux_len n _ b h

theorem blocksAux_ne_nil {α : Type} {per : Nat} (hp : 0 < per) :
    ∀ (n : Nat) (l : List α), ∀ b ∈ blocksAux n per l, b ≠ []
  | 0, _, b, h => by simp [blocksAux] at h
  | n + 1, l, b, h => by
    cases l with
    | nil => simp [blocksAux] at h
    | cons x xs =>
      simp only [blocksAux, List.mem_cons] at h
      rcases h with rfl | h
      · simp; omega
      · exact blocksAux_ne_nil hp n _ b h

theorem blocks_flatten {α : Type} {per : Nat} (hp : 0 < per) (l : List α) : (blocks per l).flatten = l :=
  blocksAux_flatten hp l.length l (Nat.le_refl _)

theorem blocks_len {α : Type} {per : Nat} (l : List α) : ∀ b ∈ blocks per l, b.length ≤ per :=
  blocksAux_len l.length l

theorem blocks_ne_nil {α : Type} {per : Nat} (hp : 0 < per) (l : List α) : ∀ b ∈ blocks per l, b ≠ [] :=
  blocksAux_ne_nil hp l.length l

def capMin : Nat := 15

def coolMin : Nat := 5

def visitMin : Nat := 7

def perBlock : Nat := capMin / visitMin

theorem block_fits {α : Type} (l : List α) : ∀ b ∈ blocks perBlock l, b.length * visitMin ≤ capMin := by
  intro b hb
  have h := blocks_len l b hb
  calc b.length * visitMin ≤ perBlock * visitMin := Nat.mul_le_mul_right _ h
    _ ≤ capMin := Nat.div_mul_le_self _ _

def mayStart (elapsedS longestS : Nat) : Bool := decide (elapsedS + longestS ≤ capMin * 60)

theorem mayStart_fits {e l : Nat} (h : mayStart e l = true) : e + l ≤ 900 := by
  have := of_decide_eq_true h
  simp only [capMin] at this
  omega

theorem mayStart_refused {e l : Nat} (h : 900 < e + l) : mayStart e l = false := by
  unfold mayStart capMin
  exact decide_eq_false (by omega)

def coolOk (gapS : Nat) : Bool := decide (coolMin * 60 ≤ gapS)

theorem coolOk_iff (g : Nat) : coolOk g = true ↔ 300 ≤ g := by
  unfold coolOk coolMin
  rw [decide_eq_true_iff]

inductive Fault where
  | usbReset
  | staleTab
  | foreignProxy
  | other
  deriving DecidableEq

def Fault.name : Fault → String
  | .usbReset => "usbReset"
  | .staleTab => "staleTab"
  | .foreignProxy => "foreignProxy"
  | .other => "other"

def Fault.harness : Fault → Bool
  | .usbReset => true
  | .staleTab => true
  | .foreignProxy => true
  | .other => false

def hasText (msg pat : String) : Bool := decide (1 < (msg.splitOn pat).length)

def faultOf (msg : String) : Fault :=
  if ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) then .usbReset
  else if hasText msg "stale own tab" then .staleTab
  else if hasText msg "another ios_webkit_debug_proxy" then .foreignProxy
  else .other

def mayAttempt (faults : List Fault) : Bool :=
  decide (faults.length < 2) || (decide (faults.length < 3) && faults.all Fault.harness)

theorem mayAttempt_first_two {faults : List Fault} (h : faults.length < 2) : mayAttempt faults = true := by
  unfold mayAttempt
  simp [h]

theorem mayAttempt_third_harness {faults : List Fault} (hl : faults.length = 2) (hh : faults.all Fault.harness = true) :
    mayAttempt faults = true := by
  unfold mayAttempt
  simp [hl, hh]

theorem mayAttempt_third_other {faults : List Fault} (hl : faults.length = 2) (hh : faults.all Fault.harness = false) :
    mayAttempt faults = false := by
  unfold mayAttempt
  simp [hl, hh]

theorem mayAttempt_fourth {faults : List Fault} (h : 3 ≤ faults.length) : mayAttempt faults = false := by
  unfold mayAttempt
  have h1 : ¬ faults.length < 2 := by omega
  have h2 : ¬ faults.length < 3 := by omega
  simp [h1, h2]

theorem harness_iff (f : Fault) : f.harness = true ↔ f = .usbReset ∨ f = .staleTab ∨ f = .foreignProxy := by
  cases f <;> simp [Fault.harness]

def recordFault (faults : List Fault) (f : Fault) : List Fault := faults ++ [f]

def handReset (faults : List Fault) : List Fault := faults

def appendOnly (old new : List Fault) : Bool := old.isPrefixOf new

theorem recordFault_prefix (faults : List Fault) (f : Fault) : faults <+: recordFault faults f :=
  List.prefix_append _ _

theorem recordFault_length (faults : List Fault) (f : Fault) : (recordFault faults f).length = faults.length + 1 := by
  simp [recordFault]

theorem handReset_keeps (faults : List Fault) : handReset faults = faults := rfl

theorem handReset_mayAttempt (faults : List Fault) : mayAttempt (handReset faults) = mayAttempt faults := rfl

theorem handReset_append_only (faults : List Fault) (f : Fault) : faults <+: recordFault (handReset faults) f :=
  recordFault_prefix faults f

theorem handReset_fourth {faults : List Fault} (h : 3 ≤ faults.length) : mayAttempt (handReset faults) = false :=
  mayAttempt_fourth h

theorem appendOnly_iff (old new : List Fault) : appendOnly old new = true ↔ old <+: new := by
  unfold appendOnly
  exact List.isPrefixOf_iff_prefix

theorem appendOnly_record (faults : List Fault) (f : Fault) : appendOnly faults (recordFault faults f) = true :=
  (appendOnly_iff _ _).2 (recordFault_prefix faults f)

theorem strip_visit_lost : mayAttempt [.usbReset, .staleTab, .other] = false := by decide

structure VisitRec where
  index : Nat
  faults : List Fault
  deriving DecidableEq

def keepOk (new : List VisitRec) (v : VisitRec) : Bool :=
  match new.find? (·.index == v.index) with
  | none => v.faults.isEmpty
  | some n => appendOnly v.faults n.faults

def writeOk (old new : List VisitRec) : Bool := old.all (keepOk new)

theorem keepOk_removed_clean {new : List VisitRec} {v : VisitRec} (hn : new.find? (·.index == v.index) = none)
    (hf : v.faults = []) : keepOk new v = true := by
  simp [keepOk, hn, hf]

theorem keepOk_removed_faulty {new : List VisitRec} {v : VisitRec} (hn : new.find? (·.index == v.index) = none)
    (hf : v.faults ≠ []) : keepOk new v = false := by
  simp [keepOk, hn, hf]

theorem keepOk_kept_extends {new : List VisitRec} {v n : VisitRec} (hn : new.find? (·.index == v.index) = some n)
    (h : v.faults <+: n.faults) : keepOk new v = true := by
  simp [keepOk, hn, appendOnly_iff, h]

theorem keepOk_kept_shortens {new : List VisitRec} {v n : VisitRec} (hn : new.find? (·.index == v.index) = some n)
    (h : ¬ v.faults <+: n.faults) : keepOk new v = false := by
  have h' : appendOnly v.faults n.faults = false := by
    cases hb : appendOnly v.faults n.faults
    · rfl
    · exact absurd ((appendOnly_iff _ _).1 hb) h
  simp [keepOk, hn, h']

theorem writeOk_nil (new : List VisitRec) : writeOk [] new = true := rfl

theorem writeOk_refuses {old new : List VisitRec} {v : VisitRec} (hv : v ∈ old) (h : keepOk new v = false) :
    writeOk old new = false := by
  unfold writeOk
  exact List.all_eq_false.2 ⟨v, hv, by simp [h]⟩

theorem writeOk_refuses_removal {old new : List VisitRec} {v : VisitRec} (hv : v ∈ old) (hf : v.faults ≠ [])
    (hn : ∀ n ∈ new, n.index ≠ v.index) : writeOk old new = false := by
  have h : new.find? (·.index == v.index) = none := by
    rw [List.find?_eq_none]
    intro n hm
    simpa using hn n hm
  exact writeOk_refuses hv (keepOk_removed_faulty h hf)

theorem writeOk_accepts {old new : List VisitRec} (h : ∀ v ∈ old, keepOk new v = true) : writeOk old new = true := by
  unfold writeOk
  exact List.all_eq_true.2 h

def handResetRecs (vs : List VisitRec) (i : Nat) : List VisitRec :=
  vs.map fun v => if v.index == i then { v with faults := handReset v.faults } else v

theorem handResetRecs_faults (vs : List VisitRec) (i : Nat) :
    (handResetRecs vs i).map (·.faults) = vs.map (·.faults) := by
  unfold handResetRecs
  induction vs with
  | nil => rfl
  | cons v rest ih =>
    by_cases h : (v.index == i) = true <;> simp_all [handReset]

theorem handResetRecs_index (vs : List VisitRec) (i : Nat) :
    (handResetRecs vs i).map (·.index) = vs.map (·.index) := by
  unfold handResetRecs
  induction vs with
  | nil => rfl
  | cons v rest ih =>
    by_cases h : (v.index == i) = true <;> simp_all

inductive ResetPlan where
  | badIndex
  | noReason
  | noVisit
  | note (index : Nat) (reason : String)
  deriving DecidableEq, Repr

def blank (s : String) : Bool := s.all Char.isWhitespace

def numeral (s : String) : Bool := !s.isEmpty && s.all fun c => '0' ≤ c && c ≤ '9'

def resetPlan (n : Nat) (vs : List VisitRec) (idx reason : String) : ResetPlan :=
  if !numeral idx || n ≤ idx.toNat! then .badIndex
  else if blank reason then .noReason
  else if vs.any (·.index == idx.toNat!) then .note idx.toNat! reason
  else .noVisit

theorem resetPlan_badIndex_text {n : Nat} {vs : List VisitRec} {idx : String} (reason : String) (h : numeral idx = false) :
    resetPlan n vs idx reason = .badIndex := by
  simp [resetPlan, h]

theorem resetPlan_badIndex_range {n : Nat} {vs : List VisitRec} {idx : String} (reason : String) (h : n ≤ idx.toNat!) :
    resetPlan n vs idx reason = .badIndex := by
  simp [resetPlan, h]

theorem resetPlan_noReason {n : Nat} {vs : List VisitRec} {idx : String} {reason : String} (hd : numeral idx = true)
    (hr : idx.toNat! < n) (h : blank reason = true) : resetPlan n vs idx reason = .noReason := by
  have : ¬ n ≤ idx.toNat! := by omega
  simp [resetPlan, hd, this, h]

theorem resetPlan_noVisit {n : Nat} {vs : List VisitRec} {idx : String} {reason : String} (hd : numeral idx = true)
    (hr : idx.toNat! < n) (h : blank reason = false) (hv : vs.any (·.index == idx.toNat!) = false) :
    resetPlan n vs idx reason = .noVisit := by
  have : ¬ n ≤ idx.toNat! := by omega
  simp [resetPlan, hd, this, h, hv]

theorem resetPlan_note {n : Nat} {vs : List VisitRec} {idx : String} {reason : String} (hd : numeral idx = true)
    (hr : idx.toNat! < n) (h : blank reason = false) (hv : vs.any (·.index == idx.toNat!) = true) :
    resetPlan n vs idx reason = .note idx.toNat! reason := by
  have : ¬ n ≤ idx.toNat! := by omega
  simp [resetPlan, hd, this, h, hv]


theorem faultOf_usb {msg : String} (h : ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) = true) :
    faultOf msg = .usbReset := by
  simp [faultOf, h]

theorem faultOf_stale {msg : String} (h1 : ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) = false)
    (h2 : hasText msg "stale own tab" = true) : faultOf msg = .staleTab := by
  simp [faultOf, h1, h2]

theorem faultOf_foreign {msg : String} (h1 : ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) = false)
    (h2 : hasText msg "stale own tab" = false) (h3 : hasText msg "another ios_webkit_debug_proxy" = true) :
    faultOf msg = .foreignProxy := by
  simp [faultOf, h1, h2, h3]

theorem faultOf_other {msg : String} (h1 : ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) = false)
    (h2 : hasText msg "stale own tab" = false) (h3 : hasText msg "another ios_webkit_debug_proxy" = false) :
    faultOf msg = .other := by
  simp [faultOf, h1, h2, h3]

def usbWaitS : Nat := 180

structure UsbReading where
  listed : Bool
  onBus : Bool
  evidence : Bool

inductive UsbVerdict where
  | ok
  | reset
  | absent
  deriving DecidableEq

def UsbVerdict.name : UsbVerdict → String
  | .ok => "ok" | .reset => "reset" | .absent => "absent"

def usbVerdict (r : UsbReading) : UsbVerdict :=
  if r.evidence || (!r.listed && r.onBus) then .reset
  else if r.listed then .ok
  else .absent

theorem usbVerdict_evidence {r : UsbReading} (h : r.evidence = true) : usbVerdict r = .reset := by
  simp [usbVerdict, h]

theorem usbVerdict_unlisted_on_bus {r : UsbReading} (hl : r.listed = false) (hb : r.onBus = true) : usbVerdict r = .reset := by
  simp [usbVerdict, hl, hb]

theorem usbVerdict_ok {r : UsbReading} (he : r.evidence = false) (hl : r.listed = true) : usbVerdict r = .ok := by
  simp [usbVerdict, he, hl]

theorem usbVerdict_absent {r : UsbReading} (he : r.evidence = false) (hl : r.listed = false) (hb : r.onBus = false) :
    usbVerdict r = .absent := by
  simp [usbVerdict, he, hl, hb]

def usbLine (line : String) : Bool :=
  hasText line "usbpowerd" && (hasText line "terminated" || hasText line "discovered")

def classify (msg : String) (u : UsbVerdict) : Fault :=
  match faultOf msg with
  | .other => if u = .reset then .usbReset else .other
  | f => f

theorem classify_named {msg : String} {u : UsbVerdict} (h : faultOf msg ≠ .other) : classify msg u = faultOf msg := by
  unfold classify
  split <;> simp_all

theorem classify_reset {msg : String} (h : faultOf msg = .other) : classify msg .reset = .usbReset := by
  simp [classify, h]

theorem classify_unreset {msg : String} {u : UsbVerdict} (h : faultOf msg = .other) (hu : u ≠ .reset) : classify msg u = .other := by
  simp [classify, h, hu]

inductive UsbWait where
  | resume
  | keep
  | giveUp
  deriving DecidableEq

def UsbWait.name : UsbWait → String
  | .resume => "resume" | .keep => "keep" | .giveUp => "giveUp"

def usbWait (listed : Bool) (waitedS : Nat) : UsbWait :=
  if listed then .resume else if usbWaitS ≤ waitedS then .giveUp else .keep

theorem usbWait_resume {w : Nat} : usbWait true w = .resume := by
  simp [usbWait]

theorem usbWait_keep {w : Nat} (h : w < usbWaitS) : usbWait false w = .keep := by
  have : ¬ usbWaitS ≤ w := by omega
  simp [usbWait, this]

theorem usbWait_giveUp {w : Nat} (h : usbWaitS ≤ w) : usbWait false w = .giveUp := by
  simp [usbWait, h]

def guardedPorts : List Nat := [9221, 9222]

inductive ProxyVerdict where
  | clear
  | holdsPorts
  | attached
  deriving DecidableEq

def ProxyVerdict.name : ProxyVerdict → String
  | .clear => "clear" | .holdsPorts => "holdsPorts" | .attached => "attached"

def regexy (id : String) : Bool := id.any fun c => ".*+?[](){}|^$\\".toList.contains c

def specAttaches (udid spec : String) : Bool :=
  ((spec.map fun c => if c == '\n' then ',' else c).splitOn ",").any fun e =>
    match e.splitOn ":" with
    | [id, port] => id != "null" && port != "-1" && (id.isEmpty || id == udid || regexy id)
    | _ => false

structure ForeignProxy where
  ports : List Nat
  spec : Option String
  usb : Bool

def proxyVerdict (p : ForeignProxy) (udid : String) : ProxyVerdict :=
  if p.ports.any guardedPorts.contains then .holdsPorts
  else if !p.usb then .clear
  else match p.spec with
    | none => .attached
    | some s => if specAttaches udid s then .attached else .clear

theorem proxyVerdict_holds {p : ForeignProxy} (udid : String) (h : p.ports.any guardedPorts.contains = true) :
    proxyVerdict p udid = .holdsPorts := by
  simp [proxyVerdict, h]

theorem proxyVerdict_socket {p : ForeignProxy} (udid : String) (h : p.ports.any guardedPorts.contains = false) (hu : p.usb = false) :
    proxyVerdict p udid = .clear := by
  simp [proxyVerdict, h, hu]

theorem proxyVerdict_unknown {p : ForeignProxy} (udid : String) (h : p.ports.any guardedPorts.contains = false) (hu : p.usb = true)
    (hs : p.spec = none) : proxyVerdict p udid = .attached := by
  simp [proxyVerdict, h, hu, hs]

theorem proxyVerdict_attached {p : ForeignProxy} {s : String} (udid : String) (h : p.ports.any guardedPorts.contains = false)
    (hu : p.usb = true) (hs : p.spec = some s) (ha : specAttaches udid s = true) : proxyVerdict p udid = .attached := by
  simp [proxyVerdict, h, hu, hs, ha]

theorem proxyVerdict_clear {p : ForeignProxy} {s : String} (udid : String) (h : p.ports.any guardedPorts.contains = false)
    (hu : p.usb = true) (hs : p.spec = some s) (ha : specAttaches udid s = false) : proxyVerdict p udid = .clear := by
  simp [proxyVerdict, h, hu, hs, ha]

def proxiesClear (ps : List ForeignProxy) (udid : String) : Bool :=
  ps.all fun p => proxyVerdict p udid == .clear

theorem proxiesClear_nil (udid : String) : proxiesClear [] udid = true := rfl

theorem proxiesClear_iff (ps : List ForeignProxy) (udid : String) :
    proxiesClear ps udid = true ↔ ∀ p ∈ ps, proxyVerdict p udid = .clear := by
  simp [proxiesClear]

theorem proxiesClear_refuses {ps : List ForeignProxy} {p : ForeignProxy} (udid : String) (hp : p ∈ ps)
    (h : proxyVerdict p udid ≠ .clear) : proxiesClear ps udid = false := by
  cases hc : proxiesClear ps udid
  · rfl
  · exact absurd ((proxiesClear_iff ps udid).1 hc p hp) h

inductive TabPlan where
  | drive (i : Nat)
  | reset (i : Nat)
  | refuse
  deriving DecidableEq

def isBlank (u : String) : Bool := u == "about:blank"

def ownTab (host u : String) : Bool := u == host || u.startsWith (host ++ ":") || u.startsWith (host ++ "/")

def tabPlan (host : String) (urls : List String) : TabPlan :=
  if urls.countP isBlank = 1 then .drive (urls.findIdx isBlank)
  else if urls.countP isBlank = 0 ∧ urls.countP (ownTab host) = 1 then .reset (urls.findIdx (ownTab host))
  else .refuse

theorem tabPlan_drive {host : String} {urls : List String} (h : urls.countP isBlank = 1) :
    tabPlan host urls = .drive (urls.findIdx isBlank) := by
  unfold tabPlan
  simp [h]

theorem tabPlan_reset {host : String} {urls : List String} (h0 : urls.countP isBlank = 0)
    (h1 : urls.countP (ownTab host) = 1) : tabPlan host urls = .reset (urls.findIdx (ownTab host)) := by
  unfold tabPlan
  simp [h0, h1]

theorem tabPlan_refuse_blank {host : String} {urls : List String} (h : 1 < urls.countP isBlank) :
    tabPlan host urls = .refuse := by
  unfold tabPlan
  have h1 : ¬ urls.countP isBlank = 1 := by omega
  have h2 : ¬ urls.countP isBlank = 0 := by omega
  simp [h1, h2]

theorem tabPlan_refuse_none {host : String} {urls : List String} (h0 : urls.countP isBlank = 0)
    (h1 : urls.countP (ownTab host) ≠ 1) : tabPlan host urls = .refuse := by
  unfold tabPlan
  simp [h0, h1]

theorem tabPlan_reset_no_blank {host : String} {urls : List String} {i : Nat} (h : tabPlan host urls = .reset i) :
    urls.countP isBlank = 0 := by
  unfold tabPlan at h
  split at h
  · cases h
  · split at h
    · rename_i _ h2
      exact h2.1
    · cases h

theorem ownTab_any_port (host port : String) : ownTab host (host ++ ":" ++ port) = true := by
  unfold ownTab
  have h : (host ++ ":" ++ port).startsWith (host ++ ":") = true := by
    rw [String.startsWith_string_iff]
    simp
  simp [h]

def sessionBlocks : List (List Arm) := blocks perBlock sessionVisits

def wallMin (n : Nat) : Nat := n * visitMin + ((blocks perBlock (List.range n)).length - 1) * coolMin

theorem wallMin_session : wallMin sessionVisits.length = 147 := by decide

def binZone (vh10 maxY10 y0 : Int) : Zone := zoneOf vh10 maxY10 (y0 * 10 + 2500)

def zoneSum (vh10 maxY10 : Int) (z : Zone) (bins : List (Int × Int)) : Int :=
  ((bins.filter fun b => binZone vh10 maxY10 b.1 == z).map (·.2)).sum

theorem zoneSum_split (vh10 maxY10 : Int) :
    ∀ bins : List (Int × Int), zoneSum vh10 maxY10 .hero bins + zoneSum vh10 maxY10 .finish bins +
      zoneSum vh10 maxY10 .rest bins = (bins.map (·.2)).sum
  | [] => by simp [zoneSum]
  | b :: bs => by
    have ih := zoneSum_split vh10 maxY10 bs
    unfold zoneSum at ih ⊢
    cases h : binZone vh10 maxY10 b.1 <;> simp [h] <;> omega

theorem binZone_hero {vh10 maxY10 y0 : Int} (h : y0 * 10 + 2500 < 2 * vh10) : binZone vh10 maxY10 y0 = .hero :=
  Fw.Device.Session.zoneOf_hero h

def cells (bs as : List (List Int)) : List Verdict := List.zipWith verdict bs as

inductive Label where
  | better | worse | mixed | same | unresolved
  deriving DecidableEq, Repr

def Label.name : Label → String
  | .better => "better" | .worse => "worse" | .mixed => "mixed" | .same => "same" | .unresolved => "unresolved"

def labelOf (vs : List Verdict) : Label :=
  if vs.contains .beats && vs.contains .worse then .mixed
  else if vs.contains .beats then .better
  else if vs.contains .worse then .worse
  else if vs.contains .same then .same
  else .unresolved

theorem labelOf_mixed {vs : List Verdict} (h1 : .beats ∈ vs) (h2 : .worse ∈ vs) : labelOf vs = .mixed := by
  simp [labelOf, h1, h2]

theorem labelOf_better {vs : List Verdict} (h1 : .beats ∈ vs) (h2 : .worse ∉ vs) : labelOf vs = .better := by
  simp [labelOf, h1, h2]

theorem labelOf_worse {vs : List Verdict} (h1 : .beats ∉ vs) (h2 : .worse ∈ vs) : labelOf vs = .worse := by
  simp [labelOf, h1, h2]

theorem labelOf_same {vs : List Verdict} (h1 : .beats ∉ vs) (h2 : .worse ∉ vs) (h3 : .same ∈ vs) :
    labelOf vs = .same := by
  simp [labelOf, h1, h2, h3]

theorem labelOf_unresolved {vs : List Verdict} (h1 : .beats ∉ vs) (h2 : .worse ∉ vs) (h3 : .same ∉ vs) :
    labelOf vs = .unresolved := by
  simp [labelOf, h1, h2, h3]

theorem labelOf_nil : labelOf [] = .unresolved := by decide

theorem labelOf_better_iff (vs : List Verdict) : labelOf vs = .better ↔ .beats ∈ vs ∧ .worse ∉ vs := by
  unfold labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem labelOf_worse_iff (vs : List Verdict) : labelOf vs = .worse ↔ .worse ∈ vs ∧ .beats ∉ vs := by
  unfold labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

def armLabel (bs as : List (List Int)) : Label := labelOf (cells bs as)

def table (bs : List (List Int)) (arms : List (List (List Int))) : List Label := arms.map (armLabel bs)

theorem table_cons (bs : List (List Int)) (a : List (List Int)) (rest : List (List (List Int))) :
    table bs (a :: rest) = armLabel bs a :: table bs rest := rfl

theorem table_append (bs : List (List Int)) (xs ys : List (List (List Int))) :
    table bs (xs ++ ys) = table bs xs ++ table bs ys := List.map_append

theorem cell_beats_beyond {base arm : List Int} (h : verdict base arm = .beats) :
    ∀ o ∈ base, ∀ a ∈ arm, a + spread base < o := Fw.Device.Session.verdict_beats_beyond h

theorem cell_worse_beyond {base arm : List Int} (h : verdict base arm = .worse) :
    ∀ o ∈ base, ∀ a ∈ arm, o + spread base < a := Fw.Device.Session.verdict_worse_beyond h

theorem cell_unresolved_base {base : List Int} (arm : List Int) (h : base.length < 2) : verdict base arm = .unresolved :=
  Fw.Device.Session.verdict_unresolved_single arm h

theorem cell_unresolved_arm (base : List Int) : verdict base [] = .unresolved :=
  Fw.Device.Session.verdict_unresolved_no_arm base

theorem cell_not_beats_within {base arm : List Int} {o a : Int} (ho : o ∈ base) (ha : a ∈ arm)
    (h : o ≤ a + spread base) : verdict base arm ≠ .beats :=
  Fw.Device.Session.not_beats_within ho ha h

inductive Step where
  | fwd | hold | back
  deriving DecidableEq, Repr

def Step.name : Step → String
  | .fwd => "fwd" | .hold => "hold" | .back => "back"

def askCycle : List Step := [.fwd, .hold, .back, .hold]

def pattern : List Step := [.fwd, .hold, .back, .hold, .fwd]

def patternAsks : Nat := 2

def burstAsks : Nat := 3

def visitSteps : List Step := (List.replicate (patternAsks + burstAsks) askCycle).flatten

theorem pattern_prefix : pattern <+: (List.replicate patternAsks askCycle).flatten := by decide

theorem visitSteps_length : visitSteps.length = 20 := by decide

def pushes : Nat := (visitSteps.filter fun s => s != .hold).length

theorem pushes_eq : pushes = 10 := by decide

theorem pushes_split : pushes = 2 * (patternAsks + burstAsks) := by decide

def minVisits : Nat := 3

def pushMetrics : List String :=
  ["p95", "p99", "max", "over50", "RecalculateStyles", "Layout", "Paint", "FireAnimationFrame"]

def overLimit : Int := 5000

structure PFrame where
  t : Int
  y : Int
  r : Int
  deriving DecidableEq, Repr

def changeTimes : List PFrame → List Int
  | a :: b :: rest => (if a.y == b.y && a.r == b.r then [] else [b.t]) ++ changeTimes (b :: rest)
  | _ => []

theorem changeTimes_nil : changeTimes [] = [] := rfl

theorem changeTimes_still (a b : PFrame) (hy : a.y = b.y) (hr : a.r = b.r) : changeTimes [a, b] = [] := by
  simp [changeTimes, hy, hr]

theorem changeTimes_moved (a b : PFrame) (h : a.y ≠ b.y ∨ a.r ≠ b.r) : changeTimes [a, b] = [b.t] := by
  rcases h with h | h <;> simp [changeTimes, h]

theorem foldl_max_ge (a : Int) : ∀ l : List Int, a ≤ l.foldl max a
  | [] => Int.le_refl a
  | x :: xs => by
    have := foldl_max_ge (max a x) xs
    simp only [List.foldl_cons]
    omega

theorem foldl_max_ub (a : Int) : ∀ (l : List Int), ∀ x ∈ l, x ≤ l.foldl max a
  | [], x, hx => by simp at hx
  | y :: ys, x, hx => by
    simp only [List.foldl_cons]
    rcases List.mem_cons.mp hx with rfl | h
    · have := foldl_max_ge (max a x) ys
      omega
    · exact foldl_max_ub (max a y) ys x h

theorem foldl_max_mem (a : Int) : ∀ (l : List Int), l.foldl max a = a ∨ l.foldl max a ∈ l
  | [] => Or.inl rfl
  | y :: ys => by
    simp only [List.foldl_cons]
    rcases foldl_max_mem (max a y) ys with h | h
    · by_cases h2 : a ≤ y
      · have : max a y = y := by omega
        exact Or.inr (by rw [h, this]; simp)
      · have : max a y = a := by omega
        exact Or.inl (h.trans this)
    · exact Or.inr (List.mem_cons_of_mem _ h)

def morphEnd (lo hi : Int) (fs : List PFrame) : Int :=
  ((changeTimes fs).filter fun t => decide (lo ≤ t ∧ t < hi)).foldl max lo

theorem morphEnd_ge (lo hi : Int) (fs : List PFrame) : lo ≤ morphEnd lo hi fs := foldl_max_ge _ _

theorem morphEnd_lt {lo hi : Int} (fs : List PFrame) (h : lo < hi) : morphEnd lo hi fs < hi := by
  unfold morphEnd
  rcases foldl_max_mem lo ((changeTimes fs).filter fun t => decide (lo ≤ t ∧ t < hi)) with h1 | h1
  · rw [h1]; exact h
  · have := (List.mem_filter.mp h1).2
    simp at this
    exact this.2

theorem morphEnd_still {lo hi : Int} {fs : List PFrame} (h : ∀ t ∈ changeTimes fs, t < lo ∨ hi ≤ t) : morphEnd lo hi fs = lo := by
  unfold morphEnd
  have : (changeTimes fs).filter (fun t => decide (lo ≤ t ∧ t < hi)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro t ht
    rcases h t ht with h | h <;> simp <;> omega
  rw [this]; rfl

theorem morphEnd_after {lo hi t : Int} {fs : List PFrame} (ht : t ∈ changeTimes fs) (h1 : lo ≤ t) (h2 : t < hi) :
    t ≤ morphEnd lo hi fs :=
  foldl_max_ub lo _ t (List.mem_filter.mpr ⟨ht, by simp [h1, h2]⟩)

def windows (hiEnd : Int) : List Int → List (Int × Int)
  | a :: b :: rest => (a, b) :: windows hiEnd (b :: rest)
  | [a] => [(a, hiEnd)]
  | [] => []

theorem windows_length (hiEnd : Int) : ∀ ts : List Int, (windows hiEnd ts).length = ts.length
  | [] => rfl
  | [_] => rfl
  | _ :: b :: rest => by
    have := windows_length hiEnd (b :: rest)
    simp [windows] at this ⊢
    omega

theorem windows_starts (hiEnd : Int) : ∀ ts : List Int, (windows hiEnd ts).map Prod.fst = ts
  | [] => rfl
  | [_] => rfl
  | a :: b :: rest => by
    have := windows_starts hiEnd (b :: rest)
    simp only [windows, List.map_cons] at this ⊢
    rw [this]

def spans (fs : List PFrame) (hiEnd : Int) (ts : List Int) : List (Int × Int) :=
  (windows hiEnd ts).map fun w => (w.1, morphEnd w.1 w.2 fs)

theorem spans_length (fs : List PFrame) (hiEnd : Int) (ts : List Int) : (spans fs hiEnd ts).length = ts.length := by
  simp [spans, windows_length]

theorem spans_ordered (fs : List PFrame) (hiEnd : Int) (ts : List Int) : ∀ s ∈ spans fs hiEnd ts, s.1 ≤ s.2 := by
  intro s hs
  obtain ⟨w, _, rfl⟩ := List.mem_map.mp hs
  exact morphEnd_ge _ _ _

def dts : List PFrame → List Int
  | a :: b :: rest => (b.t - a.t) :: dts (b :: rest)
  | _ => []

theorem dts_length : ∀ fs : List PFrame, (dts fs).length = fs.length - 1
  | [] => rfl
  | [_] => rfl
  | _ :: b :: rest => by
    have := dts_length (b :: rest)
    simp [dts] at this ⊢
    omega

def framesIn (s : Int × Int) (fs : List PFrame) : List PFrame := fs.filter fun f => decide (s.1 ≤ f.t ∧ f.t ≤ s.2)

def spanDts (sps : List (Int × Int)) (fs : List PFrame) : List Int := sps.flatMap fun s => dts (framesIn s fs)

def pct (p : Nat) (xs : List Int) : Int :=
  (xs.mergeSort (fun a b => decide (a ≤ b))).getD ((p * xs.length + 99) / 100 - 1) 0

theorem pct_nil (p : Nat) : pct p [] = 0 := by simp [pct]

theorem pct_mem {p : Nat} {xs : List Int} (hp : p ≤ 100) (hx : xs ≠ []) : pct p xs ∈ xs := by
  have hn : 0 < xs.length := List.length_pos_iff.mpr hx
  have hl : (xs.mergeSort (fun a b => decide (a ≤ b))).length = xs.length := List.length_mergeSort _
  have hi : (p * xs.length + 99) / 100 - 1 < (xs.mergeSort (fun a b => decide (a ≤ b))).length := by
    rw [hl]
    have : p * xs.length ≤ 100 * xs.length := Nat.mul_le_mul_right _ hp
    omega
  unfold pct
  simp only [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi, Option.getD_some]
  exact (List.mem_mergeSort).mp (List.getElem_mem hi)

theorem pct_le_max {p : Nat} {xs : List Int} {m : Int} (hp : p ≤ 100) (hx : xs ≠ []) (hm : ∀ x ∈ xs, x ≤ m) : pct p xs ≤ m :=
  hm _ (pct_mem hp hx)

def over (lim : Int) (xs : List Int) : Nat := (xs.filter fun x => decide (lim < x)).length

theorem over_le (lim : Int) (xs : List Int) : over lim xs ≤ xs.length := List.length_filter_le _ _

theorem over_nil (lim : Int) : over lim [] = 0 := rfl

structure Rec where
  kind : String
  t : Int
  deriving DecidableEq, Repr

def countIn (kind : String) (off : Int) (s : Int × Int) (rs : List Rec) : Nat :=
  (rs.filter fun r => r.kind == kind && decide (s.1 ≤ r.t - off ∧ r.t - off ≤ s.2)).length

theorem countIn_empty (kind : String) (off : Int) {s : Int × Int} (rs : List Rec) (h : s.2 < s.1) : countIn kind off s rs = 0 := by
  unfold countIn
  rw [List.length_eq_zero_iff]
  apply List.filter_eq_nil_iff.mpr
  intro r _
  simp
  intro _ h1
  omega

theorem countIn_le (kind : String) (off : Int) (s : Int × Int) (rs : List Rec) : countIn kind off s rs ≤ rs.length :=
  List.length_filter_le _ _

def countsOf (kind : String) (off : Int) (sps : List (Int × Int)) (rs : List Rec) : Nat := (sps.map fun s => countIn kind off s rs).sum

theorem countsOf_nil (kind : String) (off : Int) (rs : List Rec) : countsOf kind off [] rs = 0 := rfl

def shifted (ts durs : List Int) : List (Int × Int) := List.zipWith (fun t d => (t, t + d)) ts durs

theorem shifted_length (ts durs : List Int) : (shifted ts durs).length = min ts.length durs.length := by
  simp [shifted]

theorem shifted_ordered {ts durs : List Int} (h : ∀ d ∈ durs, 0 ≤ d) : ∀ s ∈ shifted ts durs, s.1 ≤ s.2 := by
  intro s hs
  obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.mp hs
  simp only [shifted, List.getElem_zipWith]
  have := h (durs[i]'(by simp [shifted] at hi; omega)) (List.getElem_mem _)
  omega

def durations (sps : List (Int × Int)) : List Int := sps.map fun s => s.2 - s.1

theorem durations_nonneg (fs : List PFrame) (hiEnd : Int) (ts : List Int) : ∀ d ∈ durations (spans fs hiEnd ts), 0 ≤ d := by
  intro d hd
  obtain ⟨s, hs, rfl⟩ := List.mem_map.mp hd
  have := spans_ordered fs hiEnd ts s hs
  omega

def visitVals (fs : List PFrame) (hiEnd : Int) (ts : List Int) (tsC : List Int) (off : Int) (rs : List Rec) : List Int :=
  let sps := spans fs hiEnd ts
  let d := spanDts sps fs
  let spsC := shifted tsC (durations sps)
  [pct 95 d, pct 99 d, pct 100 d, over overLimit d] ++
    (["RecalculateStyles", "Layout", "Paint", "FireAnimationFrame"].map fun k => ((countsOf k off spsC rs : Nat) : Int))

theorem visitVals_length (fs : List PFrame) (hiEnd : Int) (ts tsC : List Int) (off : Int) (rs : List Rec) :
    (visitVals fs hiEnd ts tsC off rs).length = pushMetrics.length := by
  simp [visitVals, pushMetrics]

def clockOff (tlA tlB pgA pgB : Int) : Option Int :=
  if driftOk (offsetOf tlA pgA) (offsetOf tlB pgB) then some (meanOffset (offsetOf tlA pgA) (offsetOf tlB pgB)) else none

theorem clockOff_keep {tlA tlB pgA pgB : Int} (h : driftOk (offsetOf tlA pgA) (offsetOf tlB pgB) = true) :
    clockOff tlA tlB pgA pgB = some (meanOffset (offsetOf tlA pgA) (offsetOf tlB pgB)) := by
  simp [clockOff, h]

theorem clockOff_refuse {tlA tlB pgA pgB : Int} (h : driftOk (offsetOf tlA pgA) (offsetOf tlB pgB) = false) :
    clockOff tlA tlB pgA pgB = none := by
  simp [clockOff, h]

def columns (k : Nat) (vs : List (List Int)) : List (List Int) := (List.range k).map fun i => vs.map (·.getD i 0)

theorem columns_length (k : Nat) (vs : List (List Int)) : (columns k vs).length = k := by simp [columns]

theorem columns_len (k : Nat) (vs : List (List Int)) : ∀ c ∈ columns k vs, c.length = vs.length := by
  intro c hc
  obtain ⟨i, _, rfl⟩ := List.mem_map.mp hc
  simp

def pushLabel (base arm : List (List Int)) : Label :=
  if minVisits ≤ base.length ∧ minVisits ≤ arm.length then
    armLabel (columns pushMetrics.length base) (columns pushMetrics.length arm)
  else .unresolved

theorem pushLabel_few_base {base arm : List (List Int)} (h : base.length < minVisits) : pushLabel base arm = .unresolved := by
  simp [pushLabel]; intro h1; omega

theorem pushLabel_few_arm {base arm : List (List Int)} (h : arm.length < minVisits) : pushLabel base arm = .unresolved := by
  simp [pushLabel]; intro _ h1; omega

theorem pushLabel_enough {base arm : List (List Int)} (hb : minVisits ≤ base.length) (ha : minVisits ≤ arm.length) :
    pushLabel base arm = armLabel (columns pushMetrics.length base) (columns pushMetrics.length arm) := by
  simp [pushLabel, hb, ha]

theorem pushLabel_better {base arm : List (List Int)} (hb : minVisits ≤ base.length) (ha : minVisits ≤ arm.length) :
    pushLabel base arm = .better ↔
      .beats ∈ cells (columns pushMetrics.length base) (columns pushMetrics.length arm) ∧
      .worse ∉ cells (columns pushMetrics.length base) (columns pushMetrics.length arm) := by
  rw [pushLabel_enough hb ha]
  exact labelOf_better_iff _

theorem pushLabel_worse {base arm : List (List Int)} (hb : minVisits ≤ base.length) (ha : minVisits ≤ arm.length) :
    pushLabel base arm = .worse ↔
      .worse ∈ cells (columns pushMetrics.length base) (columns pushMetrics.length arm) ∧
      .beats ∉ cells (columns pushMetrics.length base) (columns pushMetrics.length arm) := by
  rw [pushLabel_enough hb ha]
  exact labelOf_worse_iff _

def pushArms : List Arm :=
  [base, ⟨"morph.geom:on", .rewrite, ["morph.geom:on"]⟩,
   ⟨"morph.tween:geom-timed", .rewrite, ["morph.geom:on", "morph.tween:geom-timed"]⟩, ⟨"morph.stage:on", .rewrite, ["morph.stage:on"]⟩]

def pushRounds (r : Nat) : List Arm := (List.replicate r pushArms).flatten

theorem pushRounds_length (r : Nat) : (pushRounds r).length = 4 * r := by
  simp [pushRounds, pushArms, List.length_flatten]; omega

theorem pushRounds_count (r : Nat) (a : Arm) (hn : (pushArms.count a) = 1) :
    (pushRounds r).count a = r := by
  simp [pushRounds, List.count_flatten, hn]

theorem pushRounds_base (r : Nat) : (pushRounds r).count base = r := by
  exact pushRounds_count r base (by decide)

def pushOk (order : List Arm) : Bool := pushArms.all fun a => decide (minVisits ≤ order.count a)

theorem pushOk_rounds : pushOk (pushRounds minVisits) = true := by decide

theorem pushOk_short : pushOk (pushRounds (minVisits - 1)) = false := by decide


def noRepeat : List Arm → Bool
  | a :: b :: rest => !(a == b) && noRepeat (b :: rest)
  | _ => true

theorem noRepeat_rounds : noRepeat (pushRounds minVisits) = true := by decide

theorem pushRounds_succ (r : Nat) : pushRounds (r + 1) = pushArms ++ pushRounds r := by
  simp [pushRounds, List.replicate_succ]

def latinIdx : List (List Nat) := [[0, 1, 3, 2], [1, 2, 0, 3], [2, 3, 1, 0], [3, 0, 2, 1]]

def latinRows : List (List Arm) := latinIdx.map fun r => r.map fun j => pushArms.getD j base

def latinOrder : List Arm := latinRows.flatten

def latinRound (i : Nat) : Nat := i / 4

def latinPos (i : Nat) : Nat := i % 4

def latinCol (p : Nat) : List Arm := latinRows.map fun r => r.getD p base

def latinPairs (a b : Arm) : Nat := (latinRows.map fun r => (r.zip r.tail).count (a, b)).sum

theorem latinOrder_length : latinOrder.length = 16 := by decide

theorem latin_rows_once : latinRows.all (fun r => pushArms.all fun a => r.count a == 1) = true := by decide

theorem latin_cols_once : (List.range 4).all (fun p => pushArms.all fun a => (latinCol p).count a == 1) = true := by decide

theorem latin_carry : pushArms.all (fun a => pushArms.all fun b => latinPairs a b == (if a == b then 0 else 1)) = true := by decide

theorem latin_ok : pushOk latinOrder = true := by decide

theorem latin_noRepeat : noRepeat latinOrder = true := by decide

theorem latin_base_each : latinRows.all (fun r => r.count base == 1) = true := by decide

theorem latin_index : (List.range 16).all (fun i => latinOrder.getD i base == (latinRows.getD (latinRound i) []).getD (latinPos i) base) = true := by
  decide

def probeFlag : String := "morph.columns:probe-off"

def colsArms : List Arm :=
  [base, ⟨"cols-off", .rewrite, [probeFlag]⟩, ⟨"flip", .rewrite, ["morph.geom:on", "morph.tween:geom-timed"]⟩,
   ⟨"flip+cols-off", .rewrite, ["morph.geom:on", "morph.tween:geom-timed", probeFlag]⟩]

def colsRows : List (List Arm) := latinIdx.map fun r => r.map fun j => colsArms.getD j base

def colsOrder : List Arm := colsRows.flatten

def colsCol (p : Nat) : List Arm := colsRows.map fun r => r.getD p base

def colsPairs (a b : Arm) : Nat := (colsRows.map fun r => (r.zip r.tail).count (a, b)).sum

def colsOk (order : List Arm) : Bool := colsArms.all fun a => decide (minVisits ≤ order.count a)

theorem colsOrder_length : colsOrder.length = 16 := by decide

theorem cols_same_order : colsOrder.map (fun a => colsArms.idxOf a) = latinIdx.flatten := by decide

theorem cols_rows_once : colsRows.all (fun r => colsArms.all fun a => r.count a == 1) = true := by decide

theorem cols_cols_once : (List.range 4).all (fun p => colsArms.all fun a => (colsCol p).count a == 1) = true := by decide

theorem cols_carry : colsArms.all (fun a => colsArms.all fun b => colsPairs a b == (if a == b then 0 else 1)) = true := by decide

theorem cols_ok : colsOk colsOrder = true := by decide

theorem cols_noRepeat : noRepeat colsOrder = true := by decide

theorem cols_base_each : colsRows.all (fun r => r.count base == 1) = true := by decide

theorem cols_index : (List.range 16).all (fun i => colsOrder.getD i base == (colsRows.getD (latinRound i) []).getD (latinPos i) base) = true := by
  decide

def colsContrasts : List (String × String) := [("base", "cols-off"), ("flip", "flip+cols-off")]

def armById (id : String) : Option Arm := colsArms.find? (·.id == id)

theorem contrasts_differ_by_probe : colsContrasts.all (fun (r, a) =>
    match armById r, armById a with
    | some x, some y => y.flags == x.flags ++ [probeFlag] && x.target == y.target
    | _, _ => false) = true := by decide

inductive Cause where
  | decided | overlap | withinSpread | unresolved
  deriving DecidableEq, Repr

def Cause.name : Cause → String
  | .decided => "decided" | .overlap => "overlap" | .withinSpread => "withinSpread" | .unresolved => "unresolved"

def cause (ref arm : List Int) : Cause :=
  match verdict ref arm with
  | .beats => .decided
  | .worse => .decided
  | .unresolved => .unresolved
  | .same =>
    match ref.min?, ref.max?, arm.min?, arm.max? with
    | some rLo, some rHi, some aLo, some aHi => if aHi < rLo ∨ rHi < aLo then .withinSpread else .overlap
    | _, _, _, _ => .unresolved

theorem cause_decided_beats {ref arm : List Int} (h : verdict ref arm = .beats) : cause ref arm = .decided := by
  simp [cause, h]

theorem cause_decided_worse {ref arm : List Int} (h : verdict ref arm = .worse) : cause ref arm = .decided := by
  simp [cause, h]

theorem cause_unresolved {ref arm : List Int} (h : verdict ref arm = .unresolved) : cause ref arm = .unresolved := by
  simp [cause, h]

theorem cause_overlap_same {ref arm : List Int} (h : cause ref arm = .overlap) : verdict ref arm = .same := by
  unfold cause at h
  cases hv : verdict ref arm <;> simp_all

theorem cause_overlap_touch {ref arm : List Int} (h : cause ref arm = .overlap) :
    ∃ rLo rHi aLo aHi, ref.min? = some rLo ∧ ref.max? = some rHi ∧ arm.min? = some aLo ∧ arm.max? = some aHi ∧ aLo ≤ rHi ∧ rLo ≤ aHi := by
  unfold cause at h
  cases hv : verdict ref arm <;> simp only [hv] at h <;> try (exact absurd h (by simp))
  split at h
  · rename_i rLo rHi aLo aHi hmn hmx amn amx
    by_cases c : aHi < rLo ∨ rHi < aLo
    · simp [c] at h
    · exact ⟨rLo, rHi, aLo, aHi, hmn, hmx, amn, amx, by omega, by omega⟩
  · exact absurd h (by simp)

theorem cause_apart_same {ref arm : List Int} (h : cause ref arm = .withinSpread) : verdict ref arm = .same := by
  unfold cause at h
  cases hv : verdict ref arm <;> simp_all

theorem cause_apart_gap {ref arm : List Int} (h : cause ref arm = .withinSpread) :
    ∃ rLo rHi aLo aHi, ref.min? = some rLo ∧ ref.max? = some rHi ∧ arm.min? = some aLo ∧ arm.max? = some aHi ∧
      ((aHi < rLo ∧ rLo ≤ aHi + spread ref) ∨ (rHi < aLo ∧ aLo ≤ rHi + spread ref)) := by
  unfold cause at h
  cases hv : verdict ref arm <;> simp only [hv] at h <;> try (exact absurd h (by simp))
  split at h
  · rename_i rLo rHi aLo aHi hmn hmx amn amx
    refine ⟨rLo, rHi, aLo, aHi, hmn, hmx, amn, amx, ?_⟩
    unfold verdict at hv
    simp only [hmn, hmx, amn, amx] at hv
    split at hv <;> try simp at hv
    split at hv <;> try simp at hv
    by_cases c : aHi < rLo
    · left; exact ⟨c, by omega⟩
    · right
      by_cases c2 : rHi < aLo
      · exact ⟨c2, by omega⟩
      · simp [c, c2] at h
  · exact absurd h (by simp)

def causes (ref arm : List (List Int)) : List Cause :=
  if minVisits ≤ ref.length ∧ minVisits ≤ arm.length then
    List.zipWith cause (columns pushMetrics.length ref) (columns pushMetrics.length arm)
  else List.replicate pushMetrics.length .unresolved

theorem causes_length (ref arm : List (List Int)) : (causes ref arm).length = pushMetrics.length := by
  unfold causes
  split <;> simp [columns]

theorem causes_few_ref {ref : List (List Int)} (arm : List (List Int)) (h : ref.length < minVisits) :
    causes ref arm = List.replicate pushMetrics.length .unresolved := by
  simp [causes]; intro h1; omega

theorem causes_few_arm (ref : List (List Int)) {arm : List (List Int)} (h : arm.length < minVisits) :
    causes ref arm = List.replicate pushMetrics.length .unresolved := by
  simp [causes]; intro _ h1; omega

inductive Ev where
  | push | take
  deriving DecidableEq, Repr

def Ev.name : Ev → String
  | .push => "push" | .take => "take"

def takenOf : List Ev → Nat
  | .push :: .take :: rest => 1 + takenOf rest
  | _ :: rest => takenOf rest
  | [] => 0

def pushesOf (l : List Ev) : Nat := l.count .push

theorem takenOf_le : ∀ l : List Ev, takenOf l ≤ pushesOf l
  | [] => by simp [takenOf, pushesOf]
  | .push :: .take :: rest => by
    have := takenOf_le rest
    simp only [takenOf, pushesOf] at this ⊢
    simp
    omega
  | .push :: .push :: rest => by
    have := takenOf_le (.push :: rest)
    simp only [takenOf, pushesOf] at this ⊢
    simp at this ⊢
    omega
  | .take :: rest => by
    have := takenOf_le rest
    simp only [takenOf, pushesOf] at this ⊢
    simp
    omega
  | [.push] => by simp [takenOf, pushesOf]

theorem takenOf_none (l : List Ev) (h : Ev.take ∉ l) : takenOf l = 0 := by
  induction l with
  | nil => rfl
  | cons a rest ih =>
    have hr : Ev.take ∉ rest := fun m => h (List.mem_cons_of_mem _ m)
    cases a with
    | take => exact absurd (List.mem_cons_self ..) h
    | push =>
      cases rest with
      | nil => rfl
      | cons b r2 =>
        cases b with
        | take => exact absurd (List.mem_cons_self ..) hr
        | push => simp only [takenOf]; exact ih hr

private def strsJ (l : List String) : Json := Json.arr (l.map Json.str).toArray

private def armJ (a : Arm) : Json := Json.mkObj [("id", a.id), ("target", a.target.name), ("flags", strsJ a.flags)]

private def idsJ (l : List Arm) : Json := strsJ (l.map (·.id))

def metrics : List String :=
  ["Layout", "RecalculateStyles", "Paint", "Composite", "FireAnimationFrame", "FunctionCall", "EventDispatch",
   "paintArea", "over34", "over50"]

private def dedupCases : List (String × List Arm) :=
  [("session", candidates),
   ("twin", [base, ⟨"b2", .rewrite, []⟩, original, ⟨"o2", .original, []⟩]),
   ("order", [⟨"a", .rewrite, ["x:1", "y:2"]⟩, ⟨"b", .rewrite, ["y:2", "x:1"]⟩, ⟨"c", .rewrite, ["x:1"]⟩]),
   ("single", [base]), ("empty", [])]

private def visitCases : List (String × List Arm) :=
  [("session", others), ("two", others.take 2), ("one", others.take 1), ("none", []), ("seven", others.take 7)]

private def blockCases : List (Nat × Nat) := [(5, 3), (16, 3), (16, 1), (13, 4), (0, 3), (7, 7)]

private def startCases : List (Nat × Nat) := [(0, 290), (580, 290), (610, 290), (600, 300), (601, 300), (900, 0), (0, 901)]

private def zoneCases : List (Int × Int × List (Int × Int)) :=
  [(7750, 52670, (List.range 11).map fun (i : Nat) => (Int.ofNat i * 500, Int.ofNat i + 1)),
   (7750, 52670, [(0, 5), (1500, 7), (4000, 9), (4500, 11), (5000, 13), (5500, 15)]),
   (8150, 52270, [(0, 1), (1500, 2), (4000, 4), (4500, 8)]), (7750, 52670, [])]

private def cellCases : List (List Int × List Int) :=
  [([10, 10, 10], [4, 4, 4]), ([10, 10, 10], [11, 11, 11]), ([10, 12, 14], [12, 13, 11]), ([10, 12, 14], [1, 2, 3]),
   ([10, 12, 14], [20, 21, 40]), ([10], [1]), ([], [1]), ([10, 12], []), ([10, 12, 14, 8, 8, 8], [3, 5, 6]),
   ([5, 5], [5, 5]), ([0, 0, 0], [0, 0, 0]), ([100, 100], [50, 160])]

private def labelCases : List (List Verdict) :=
  [[], [.beats], [.worse], [.same], [.unresolved], [.beats, .worse], [.beats, .same], [.worse, .same, .unresolved],
   [.same, .unresolved], [.unresolved, .unresolved], [.beats, .beats, .same, .unresolved]]

private def tableBase : List (List Int) := [[10, 10, 10, 11], [20, 22, 24, 21], [7, 7, 7, 7]]

private def tableArms : List (List (List Int)) :=
  [[[4, 4, 4], [20, 21, 22], [7, 7, 7]], [[10, 10, 10], [40, 41, 42], [7, 7, 7]],
   [[4, 4, 4], [40, 41, 42], [7, 7, 7]], [[10, 10, 10], [20, 21, 22], [7, 7, 7]], [[9, 9, 9], [1], []]]

private def faultTexts : List String :=
  ["Inspector proxy closed (code 1006)", "the phone is paired but not on USB", "the phone re-enumerated on USB",
   "phone proxy listed no tabs in 30 s", "stale own tab could not be returned to about:blank", "Runtime.evaluate timed out 15 s",
   "expected exactly one about:blank Safari tab, found 0 of 2 tabs", "another ios_webkit_debug_proxy holds port 9221", ""]

private def attemptCases : List (List Fault) :=
  [[], [.other], [.usbReset], [.other, .other], [.usbReset, .staleTab], [.usbReset, .usbReset], [.staleTab, .other],
   [.other, .usbReset], [.usbReset, .staleTab, .usbReset], [.usbReset, .usbReset, .usbReset, .usbReset],
   [.usbReset, .staleTab, .other]]

private def appendCases : List (List Fault × List Fault) :=
  [([], []), ([], [.other]), ([.usbReset], [.usbReset, .staleTab]), ([.usbReset, .staleTab], [.usbReset, .staleTab, .other]),
   ([.usbReset, .staleTab], [.usbReset, .staleTab]), ([.usbReset, .staleTab], []), ([.usbReset, .staleTab], [.usbReset]),
   ([.usbReset, .staleTab], [.staleTab, .usbReset]), ([.usbReset], [.other, .usbReset])]

private def tabHost : String := "http://harness.test"

private def tabCases : List (List String) :=
  [["about:blank"], ["about:blank", "https://example.test/"], ["about:blank", "about:blank"], [],
   ["http://harness.test:4100/"], ["http://harness.test:4100/x?a=b"], ["http://harness.test:4100"],
   ["https://example.test/", "http://harness.test:4100/"], ["http://harness.test:4100/", "http://harness.test:4100/y"],
   ["http://harness.test:41000/"], ["http://other.test:4100/"], ["http://harness.test:4100/", "about:blank"],
   ["http://harness.test:4100/", "about:blank", "about:blank"], ["https://example.test/"],
   ["http://harness.test:3999/"], ["http://harness.test:3999/", "http://harness.test:4100/"],
   ["http://harness.test.evil:4100/"], ["http://harness.test:3999/", "about:blank"], ["https://harness.test:4100/"]]

private def recJ (v : VisitRec) : Json := Json.mkObj [("index", v.index), ("faults", strsJ (v.faults.map Fault.name))]

private def recsJ (vs : List VisitRec) : Json := Json.arr (vs.map recJ).toArray

private def writeCases : List (List VisitRec × List VisitRec) :=
  let a : VisitRec := ⟨6, [.usbReset, .staleTab]⟩
  let c : VisitRec := ⟨2, []⟩
  [([], []), ([a], [a]), ([a], []), ([a], [c]), ([a, c], [c]), ([c], []), ([c], [a]), ([a], [⟨6, [.usbReset, .staleTab, .other]⟩]),
   ([a], [⟨6, [.other]⟩]), ([a], [⟨6, [.usbReset]⟩]), ([a], [⟨6, []⟩]), ([a, c], [⟨2, [.other]⟩, ⟨6, [.usbReset, .staleTab, .other]⟩]),
   ([a, c], handResetRecs [a, c] 6), ([a], [⟨7, []⟩, a]), ([⟨3, [.other]⟩], [⟨4, [.other]⟩])]

private def wallCases : List Nat := [0, 1, 2, 3, 4, 5, 15, 16, 17]

private def resetCases : List (List VisitRec × String × String) :=
  let st : List VisitRec := [⟨6, [.usbReset, .staleTab]⟩, ⟨2, []⟩]
  [(st, "6", "tab returned to about:blank by hand"), (st, "3", "last visit of a 4-visit session"), (st, "4", "one past a 4-visit session"), (st, "2", "x"), (st, "7", "no record"), (st, "16", "past the plan"),
   (st, "15", "in the plan, no record"), (st, "", "empty index"), (st, "6a", "digits and a letter"), (st, "-1", "sign"),
   (st, "6", ""), (st, "6", "   "), (st, "06", "leading zero"), (st, "1.5", "fraction"), ([], "0", "empty state")]

private def usbReadings : List UsbReading :=
  [false, true].flatMap fun l => [false, true].flatMap fun b => [false, true].map fun e => ⟨l, b, e⟩

private def usbLines : List String :=
  ["usbpowerd: discovered <private>", "usbpowerd: device terminated", "usbpowerd: assertion taken", "usbmuxd: discovered", "", "usbpowerd"]

private def classifyTexts : List String :=
  ["Runtime.evaluate timed out 15 s", "the phone is paired but not on USB", "stale own tab could not be returned to about:blank",
   "another ios_webkit_debug_proxy holds port 9221"]

private def waitCases : List (Bool × Nat) :=
  [(true, 0), (true, 500), (false, 0), (false, 179), (false, 180), (false, 181)]

private def specCases : List String :=
  ["", ":9221,:9222-9322", "null:9221,:9222-9322", "AAAA-1111:9300", "BBBB-2222:9300", "BBBB-2222:9300,AAAA-1111:9301",
   "AAAA-1111:-1", "null:9300", "A.*:9300", "BBBB-2222:9300\nAAAA-1111:9301", "9300", ":"]

private def proxyCases : List ForeignProxy :=
  [⟨[], some "BBBB-2222:9300", true⟩, ⟨[9221], some "BBBB-2222:9300", true⟩, ⟨[9222, 9300], none, true⟩, ⟨[9300], none, true⟩,
   ⟨[9300], some ":9301", true⟩, ⟨[9300], some "AAAA-1111:9301", true⟩, ⟨[9300], some "BBBB-2222:9301", true⟩,
   ⟨[9300, 9301], some "null:9300", true⟩, ⟨[], some "", true⟩, ⟨[9223], some "BBBB-2222:9300", true⟩,
   ⟨[9341, 9342], some ":9342", false⟩, ⟨[9341], none, false⟩, ⟨[9221], some ":9342", false⟩, ⟨[9300], some ":9301", false⟩]

private def proxySets : List (List ForeignProxy) :=
  [[], [⟨[9300], some "BBBB-2222:9300", true⟩], [⟨[9300], some "BBBB-2222:9300", true⟩, ⟨[9221], some ":9301", true⟩],
   [⟨[9300], some "BBBB-2222:9300", true⟩, ⟨[9301], none, true⟩], [⟨[9300], some "null:9300", true⟩, ⟨[9301], some "AAAA-1111:-1", true⟩],
   [⟨[9341, 9342], some ":9342", false⟩, ⟨[9300], some "BBBB-2222:9300", true⟩], [⟨[9341, 9342], some ":9342", false⟩]]

private def specUdid : String := "AAAA-1111"

private def optJ : Option String → Json
  | none => Json.null
  | some s => Json.str s

private def fpJ (p : ForeignProxy) : Json := Json.mkObj [("ports", toJson p.ports), ("spec", optJ p.spec), ("usb", p.usb)]

private def resetJ : ResetPlan → Json
  | .badIndex => Json.mkObj [("plan", "badIndex")]
  | .noReason => Json.mkObj [("plan", "noReason")]
  | .noVisit => Json.mkObj [("plan", "noVisit")]
  | .note i r => Json.mkObj [("plan", "note"), ("index", i), ("reason", r)]

private def planJ : TabPlan → Json
  | .drive i => Json.mkObj [("plan", "drive"), ("i", i)]
  | .reset i => Json.mkObj [("plan", "reset"), ("i", i)]
  | .refuse => Json.mkObj [("plan", "refuse")]

private def pframesJ (fs : List PFrame) : Json := toJson (fs.map fun f => [f.t, f.y, f.r])

private def recsJ' (rs : List Rec) : Json := Json.arr (rs.map fun r => Json.arr #[Json.str r.kind, toJson r.t]).toArray

private def fr (rows : List (Int × Int × Int)) : List PFrame := rows.map fun (t, y, r) => ⟨t, y, r⟩

private def pushFrames : List PFrame :=
  fr [(0, 5000, 0), (1667, 5000, 0), (3333, 5000, 0), (5000, 5040, 0), (6667, 5080, 120), (8333, 5080, 400), (10000, 5080, 800),
      (11667, 5080, 1000), (13333, 5080, 1000), (15000, 5080, 1000), (16667, 5080, 1000), (18333, 5080, 800), (20000, 5080, 300),
      (21667, 5080, 0), (23333, 5080, 0), (25000, 5080, 0)]

private def spanCases : List (String × List PFrame × Int × List Int) :=
  [("two pushes", pushFrames, 25001, [3000, 16000]), ("one push", pushFrames, 25001, [3000]), ("no push", pushFrames, 25001, []),
   ("nothing moves", fr [(0, 1, 1), (1667, 1, 1), (3333, 1, 1)], 3334, [0]), ("push after the end", pushFrames, 25001, [26000]),
   ("a gap of 120 ms", fr [(0, 0, 0), (1667, 0, 100), (3333, 0, 300), (15333, 0, 500), (17000, 0, 500)], 17001, [0])]

private def pctCases : List (Nat × List Int) :=
  [(95, []), (95, [7]), (99, [7]), (100, [3, 9, 4, 1]), (95, (List.range 20).map fun (i : Nat) => (Int.ofNat i + 1) * 100),
   (99, (List.range 20).map fun (i : Nat) => (Int.ofNat i + 1) * 100), (50, [5, 1, 4, 2, 3]), (1, [5, 1, 4, 2, 3]),
   (95, [1667, 1667, 1666, 5100, 1667, 9000, 1667, 1667, 1667, 1667])]

private def pushVisitCases : List (String × List PFrame × Int × List Int × List Int × Int × List Rec) :=
  [("window", pushFrames, 25001, [3000, 16000], [3000, 16000], 100000,
     [⟨"Layout", 103000⟩, ⟨"Layout", 108000⟩, ⟨"Layout", 140000⟩, ⟨"Paint", 108300⟩, ⟨"Paint", 113400⟩, ⟨"RecalculateStyles", 108300⟩,
      ⟨"FireAnimationFrame", 106700⟩, ⟨"FireAnimationFrame", 108400⟩, ⟨"FireAnimationFrame", 125000⟩, ⟨"Composite", 108000⟩]),
   ("counts lane starts later", pushFrames, 25001, [3000, 16000], [4000, 17500], 0,
     [⟨"Layout", 4000⟩, ⟨"Layout", 12000⟩, ⟨"Layout", 12700⟩, ⟨"Paint", 17500⟩, ⟨"Paint", 23100⟩, ⟨"Paint", 23200⟩]),
   ("no records", pushFrames, 25001, [3000, 16000], [3000, 16000], 0, []), ("no push", pushFrames, 25001, [], [], 0, [⟨"Layout", 5000⟩]),
   ("fewer starts in the counts lane", pushFrames, 25001, [3000, 16000], [3000], 0, [⟨"Layout", 5000⟩, ⟨"Layout", 19000⟩]),
   ("gap", fr [(0, 0, 0), (1667, 0, 100), (3333, 0, 300), (15333, 0, 500), (17000, 0, 500)], 17001, [0], [0], 0,
     [⟨"Paint", 0⟩, ⟨"Paint", 3333⟩, ⟨"Paint", 15333⟩, ⟨"Paint", 16000⟩])]

private def clockCases : List (Int × Int × Int × Int) :=
  [(1000, 2000, 400, 1400), (1000, 2000, 400, 1500), (1000, 2000, 400, 1000), (1000, 2000, 400, 1100), (5000, 9000, 100, 4100), (-300, 700, 0, 1000)]

private def rowCases : List (String × List (List Int) × List (List Int)) :=
  [("clear win", [[10, 20, 30, 4, 5, 6, 7, 8], [10, 20, 30, 4, 5, 6, 7, 8], [11, 20, 30, 4, 5, 6, 7, 8]],
     [[1, 2, 3, 0, 0, 0, 0, 0], [1, 2, 3, 0, 0, 0, 0, 0], [1, 2, 3, 0, 0, 0, 0, 0]]),
   ("two visits", [[10, 20, 30, 4, 5, 6, 7, 8], [10, 20, 30, 4, 5, 6, 7, 8]], [[1, 2, 3, 0, 0, 0, 0, 0], [1, 2, 3, 0, 0, 0, 0, 0], [1, 2, 3, 0, 0, 0, 0, 0]]),
   ("arm has two", [[10, 20, 30, 4, 5, 6, 7, 8], [10, 20, 30, 4, 5, 6, 7, 8], [10, 20, 30, 4, 5, 6, 7, 8]], [[1, 2, 3, 0, 0, 0, 0, 0], [1, 2, 3, 0, 0, 0, 0, 0]]),
   ("worse", [[1, 2, 3, 4, 5, 6, 7, 8], [1, 2, 3, 4, 5, 6, 7, 8], [1, 2, 3, 4, 5, 6, 7, 8]], [[50, 60, 70, 8, 9, 9, 9, 9], [50, 60, 70, 8, 9, 9, 9, 9], [50, 60, 70, 8, 9, 9, 9, 9]]),
   ("mixed", [[10, 20, 30, 40, 50, 60, 70, 80], [10, 20, 30, 40, 50, 60, 70, 80], [10, 20, 30, 40, 50, 60, 70, 80]],
     [[1, 20, 30, 40, 500, 60, 70, 80], [1, 20, 30, 40, 500, 60, 70, 80], [1, 20, 30, 40, 500, 60, 70, 80]]),
   ("same", [[10, 20, 30, 40, 50, 60, 70, 80], [12, 22, 32, 42, 52, 62, 72, 82], [14, 24, 34, 44, 54, 64, 74, 84]],
     [[11, 21, 31, 41, 51, 61, 71, 81], [13, 23, 33, 43, 53, 63, 73, 83], [12, 22, 32, 42, 52, 62, 72, 82]]),
   ("none", [], [])]

private def colsCauseCases : List (String × List (List Int) × List (List Int)) :=
  rowCases ++
  [("wide reference spread", [[10, 1, 1, 1, 1, 1, 1, 1], [50, 1, 1, 1, 1, 1, 1, 1], [90, 1, 1, 1, 1, 1, 1, 1]],
     [[160, 1, 1, 1, 1, 1, 1, 1], [165, 1, 1, 1, 1, 1, 1, 1], [170, 1, 1, 1, 1, 1, 1, 1]]),
   ("beyond the spread", [[10, 1, 1, 1, 1, 1, 1, 1], [50, 1, 1, 1, 1, 1, 1, 1], [90, 1, 1, 1, 1, 1, 1, 1]],
     [[400, 1, 1, 1, 1, 1, 1, 1], [410, 1, 1, 1, 1, 1, 1, 1], [420, 1, 1, 1, 1, 1, 1, 1]])]

private def traceCases : List (String × List Ev) :=
  [("none", []), ("one pushed, one taken", [.push, .take]), ("pushed, not taken", [.push, .push, .take]),
   ("pushes only", [.push, .push, .push]), ("three taken of four", [.push, .take, .push, .take, .push, .push, .take]),
   ("a second take is not another push", [.push, .take, .take])]

def colsGoldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "colscons"), ("probeFlag", probeFlag), ("arms", Json.arr (colsArms.map armJ).toArray),
    ("latin", Json.arr (colsRows.map idsJ).toArray), ("order", idsJ colsOrder),
    ("contrasts", Json.arr (colsContrasts.map fun (r, a) => Json.mkObj [("ref", r), ("arm", a)]).toArray)]).compress] ++
  (colsCauseCases.map fun (n, b, a) =>
    (Json.mkObj [("kind", "colscause"), ("name", n), ("ref", toJson b), ("arm", toJson a),
      ("causes", strsJ ((causes b a).map Cause.name)), ("label", (pushLabel b a).name)]).compress) ++
  (traceCases.map fun (n, es) =>
    (Json.mkObj [("kind", "coltrace"), ("name", n), ("events", strsJ (es.map Ev.name)), ("pushes", pushesOf es),
      ("taken", takenOf es)]).compress)

def pushGoldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "pushconsts"), ("minVisits", minVisits), ("patternAsks", patternAsks), ("burstAsks", burstAsks),
    ("overLimit", overLimit), ("pushes", pushes), ("metrics", strsJ pushMetrics), ("askCycle", strsJ (askCycle.map Step.name)),
    ("pattern", strsJ (pattern.map Step.name)), ("steps", strsJ (visitSteps.map Step.name)),
    ("arms", Json.arr (pushArms.map armJ).toArray), ("rounds", idsJ (pushRounds minVisits)),
    ("latin", Json.arr (latinRows.map idsJ).toArray), ("order", idsJ latinOrder),
    ("slots", toJson ((List.range 16).map fun i => [latinRound i, latinPos i]))]).compress] ++
  (spanCases.map fun (n, fs, hi, ts) =>
    (Json.mkObj [("kind", "pushspan"), ("name", n), ("frames", pframesJ fs), ("hiEnd", hi), ("starts", toJson ts),
      ("windows", toJson ((windows hi ts).map fun w => [w.1, w.2])), ("spans", toJson ((spans fs hi ts).map fun s => [s.1, s.2])),
      ("changes", toJson (changeTimes fs)), ("dts", toJson (spanDts (spans fs hi ts) fs))]).compress) ++
  (pctCases.map fun (p, xs) =>
    (Json.mkObj [("kind", "pushpct"), ("p", p), ("values", toJson xs), ("pct", pct p xs), ("over", over overLimit xs)]).compress) ++
  (pushVisitCases.map fun (n, fs, hi, ts, tsC, off, rs) =>
    (Json.mkObj [("kind", "pushvisit"), ("name", n), ("frames", pframesJ fs), ("hiEnd", hi), ("starts", toJson ts), ("startsC", toJson tsC),
      ("off", off), ("recs", recsJ' rs), ("values", toJson (visitVals fs hi ts tsC off rs))]).compress) ++
  (clockCases.map fun (a, b, c, d) =>
    (Json.mkObj [("kind", "pushclock"), ("tlA", a), ("tlB", b), ("pgA", c), ("pgB", d),
      ("off", match clockOff a b c d with | some o => toJson o | none => Json.null)]).compress) ++
  (rowCases.map fun (n, b, a) =>
    (Json.mkObj [("kind", "pushlabel"), ("name", n), ("base", toJson b), ("arm", toJson a), ("label", (pushLabel b a).name)]).compress) ++
  [(Json.mkObj [("kind", "pushplan"), ("ok3", pushOk (pushRounds 3)), ("ok2", pushOk (pushRounds 2)), ("noRepeat3", noRepeat (pushRounds 3)),
    ("latinOk", pushOk latinOrder), ("latinNoRepeat", noRepeat latinOrder)]).compress]

private def vJ (v : Verdict) : Json := Json.str v.name

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("passes", (3 : Nat)), ("warmup", (1 : Nat)), ("reps", (5 : Nat)), ("speedPxPerS", (800 : Nat)),
    ("stepPx", (50 : Nat)), ("zonePx", (500 : Nat)), ("capMin", capMin), ("coolMin", coolMin), ("visitMin", visitMin),
    ("perBlock", perBlock), ("metrics", strsJ metrics)]).compress] ++
  (candidates.map fun a => (Json.mkObj [("kind", "arm"), ("arm", armJ a)]).compress) ++
  (dedupCases.map fun (n, xs) =>
    (Json.mkObj [("kind", "dedup"), ("name", n), ("in", Json.arr (xs.map armJ).toArray), ("kept", idsJ (dedup xs)),
      ("dropped", Json.arr ((xs.filter fun x => !(dedup xs).contains x).map fun x =>
        Json.mkObj [("id", x.id), ("sameAs", match (dedup xs).find? (samePage x) with | some y => Json.str y.id | none => Json.null)]).toArray)]).compress) ++
  (visitCases.map fun (n, os) =>
    (Json.mkObj [("kind", "visits"), ("name", n), ("others", idsJ os), ("visits", idsJ (visits base os))]).compress) ++
  [(Json.mkObj [("kind", "session"), ("visits", idsJ sessionVisits), ("blocks", Json.arr (sessionBlocks.map idsJ).toArray),
    ("wallMin", wallMin sessionVisits.length)]).compress] ++
  (blockCases.map fun (n, per) =>
    (Json.mkObj [("kind", "blocks"), ("n", n), ("per", per), ("blocks", toJson ((blocks per (List.range n)).map fun b => b.length)),
      ("flat", toJson (blocks per (List.range n)).flatten)]).compress) ++
  (startCases.map fun (e, l) =>
    (Json.mkObj [("kind", "start"), ("elapsedS", e), ("longestS", l), ("mayStart", mayStart e l), ("coolOk", coolOk e)]).compress) ++
  (zoneCases.map fun (vh, mx, bins) =>
    (Json.mkObj [("kind", "zones"), ("vh10", vh), ("maxY10", mx), ("bins", toJson (bins.map fun b => [b.1, b.2])),
      ("zones", toJson (bins.map fun b => (binZone vh mx b.1).name)),
      ("hero", zoneSum vh mx .hero bins), ("finish", zoneSum vh mx .finish bins), ("rest", zoneSum vh mx .rest bins)]).compress) ++
  (cellCases.map fun (b, a) =>
    (Json.mkObj [("kind", "cell"), ("base", toJson b), ("arm", toJson a), ("spread", spread b), ("verdict", verdict b a |> vJ)]).compress) ++
  (labelCases.map fun vs =>
    (Json.mkObj [("kind", "label"), ("cells", strsJ (vs.map (·.name))), ("label", (labelOf vs).name)]).compress) ++
  (faultTexts.map fun (t : String) =>
    (Json.mkObj [("kind", "fault"), ("text", t), ("fault", (faultOf t).name), ("harness", (faultOf t).harness)]).compress) ++
  (attemptCases.map fun (fs : List Fault) =>
    (Json.mkObj [("kind", "attempt"), ("faults", strsJ (fs.map Fault.name)), ("may", mayAttempt fs)]).compress) ++
  (attemptCases.map fun (fs : List Fault) =>
    (Json.mkObj [("kind", "reset"), ("faults", strsJ (fs.map Fault.name)), ("after", strsJ ((handReset fs).map Fault.name)),
      ("may", mayAttempt (handReset fs))]).compress) ++
  (appendCases.map fun (o, n) =>
    (Json.mkObj [("kind", "append"), ("old", strsJ (o.map Fault.name)), ("new", strsJ (n.map Fault.name)), ("ok", appendOnly o n)]).compress) ++
  (tabCases.map fun (us : List String) =>
    (Json.mkObj [("kind", "tabs"), ("host", tabHost), ("urls", strsJ us), ("plan", planJ (tabPlan tabHost us))]).compress) ++
  (writeCases.map fun (o, n) =>
    (Json.mkObj [("kind", "write"), ("old", recsJ o), ("new", recsJ n), ("ok", writeOk o n)]).compress) ++
  (([16, 4] : List Nat).flatMap fun (n : Nat) => resetCases.map fun (vs, i, r) =>
    (Json.mkObj [("kind", "handreset"), ("n", n), ("state", recsJ vs), ("index", i), ("reason", r), ("plan", resetJ (resetPlan n vs i r))]).compress) ++
  (wallCases.map fun (n : Nat) => (Json.mkObj [("kind", "wallmin"), ("n", n), ("wallMin", wallMin n)]).compress) ++
  (usbReadings.map fun r =>
    (Json.mkObj [("kind", "usb"), ("listed", r.listed), ("onBus", r.onBus), ("evidence", r.evidence), ("verdict", (usbVerdict r).name)]).compress) ++
  (usbLines.map fun (t : String) => (Json.mkObj [("kind", "usbline"), ("text", t), ("is", usbLine t)]).compress) ++
  (classifyTexts.flatMap fun (t : String) => [UsbVerdict.ok, .reset, .absent].map fun (u : UsbVerdict) =>
    (Json.mkObj [("kind", "classify"), ("text", t), ("usb", u.name), ("fault", (classify t u).name)]).compress) ++
  [(Json.mkObj [("kind", "usbwait"), ("waitS", usbWaitS), ("cases", Json.arr ((waitCases.map fun (l, w) =>
    Json.mkObj [("listed", l), ("waitedS", w), ("wait", (usbWait l w).name)]).toArray))]).compress] ++
  (specCases.map fun (sp : String) =>
    (Json.mkObj [("kind", "spec"), ("udid", specUdid), ("spec", sp), ("attaches", specAttaches specUdid sp)]).compress) ++
  (proxyCases.map fun (p : ForeignProxy) =>
    (Json.mkObj [("kind", "proxy"), ("proxy", fpJ p), ("udid", specUdid), ("verdict", (proxyVerdict p specUdid).name)]).compress) ++
  [(Json.mkObj [("kind", "proxies"), ("guarded", toJson guardedPorts), ("udid", specUdid), ("cases", Json.arr ((proxySets.map fun ps =>
    Json.mkObj [("proxies", Json.arr (ps.map fpJ).toArray), ("clear", proxiesClear ps specUdid)]).toArray))]).compress] ++
  [(Json.mkObj [("kind", "table"), ("base", toJson tableBase), ("arms", toJson tableArms),
    ("cells", Json.arr (tableArms.map fun a => strsJ ((cells tableBase a).map (·.name))).toArray),
    ("labels", strsJ ((table tableBase tableArms).map (·.name)))]).compress] ++
  pushGoldenLines () ++ colsGoldenLines ()

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-phone-arms golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-phone-arms golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.PhoneArms
