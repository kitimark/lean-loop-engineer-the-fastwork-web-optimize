import Lean.Data.Json
import Fw.Device.Session
/-!
# The phone end-of-page session: arm plan and per-arm verdict
-/
namespace Fw.Device.PhoneArms
open Lean
open Fw.Device.Session (Zone zoneOf Verdict verdict spread sameFlags sameFlags_comm sameFlags_refl)

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
  | other
  deriving DecidableEq

def Fault.name : Fault → String
  | .usbReset => "usbReset"
  | .staleTab => "staleTab"
  | .other => "other"

def Fault.harness : Fault → Bool
  | .usbReset => true
  | .staleTab => true
  | .other => false

def hasText (msg pat : String) : Bool := decide (1 < (msg.splitOn pat).length)

def faultOf (msg : String) : Fault :=
  if ["proxy closed", "not on USB", "re-enumerat", "listed no tabs"].any (hasText msg) then .usbReset
  else if hasText msg "stale own tab" then .staleTab
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

theorem harness_iff (f : Fault) : f.harness = true ↔ f = .usbReset ∨ f = .staleTab := by
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

def wallMin (n : Nat) : Nat := n * visitMin + (sessionBlocks.length - 1) * coolMin

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
   "expected exactly one about:blank Safari tab, found 0 of 2 tabs", ""]

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

private def planJ : TabPlan → Json
  | .drive i => Json.mkObj [("plan", "drive"), ("i", i)]
  | .reset i => Json.mkObj [("plan", "reset"), ("i", i)]
  | .refuse => Json.mkObj [("plan", "refuse")]

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
  [(Json.mkObj [("kind", "table"), ("base", toJson tableBase), ("arms", toJson tableArms),
    ("cells", Json.arr (tableArms.map fun a => strsJ ((cells tableBase a).map (·.name))).toArray),
    ("labels", strsJ ((table tableBase tableArms).map (·.name)))]).compress]

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
