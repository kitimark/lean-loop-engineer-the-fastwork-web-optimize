import Lean.Data.Json
import Std.Data.String.ToNat
import Fw.Ci.Provider
/-!
# Pool request keys, artifact names and outcome rows (task `pool-key-outcome`)
-/
namespace Fw.Ci.Pool.Key

open Lean (Json)
open Fw.Ci.Provider (Provider)

/-- A lowercase hex digit. -/
def hexDigit (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- `s` is exactly `n` lowercase hex digits. -/
def hexOf (n : Nat) (s : String) : Bool := s.length == n && s.toList.all hexDigit

/-- A character a lane id may hold: lowercase letter, digit or `-`. -/
def laneChar (c : Char) : Bool := c.isDigit || c.isLower || c == '-'

/-- One measurement request: commit, lane, sha256 of the lane config (Store's canonical JSON), repeat index. -/
structure Key where
  sha : String
  lane : String
  cfg : String
  rep : Nat
deriving DecidableEq, Repr

/-- Commit is 40 hex digits, config digest 64 hex digits, lane non-empty over `laneChar`. -/
def Key.valid (k : Key) : Bool :=
  hexOf 40 k.sha && hexOf 64 k.cfg && !k.lane.isEmpty && k.lane.toList.all laneChar

/-- The keys of one request with `n` repeats: reps `0..n-1`; a push is `n = 1`. -/
def keysOf (sha lane cfg : String) (n : Nat) : List Key := (List.range n).map (Key.mk sha lane cfg)

theorem keysOf_nodup (sha lane cfg : String) (n : Nat) : (keysOf sha lane cfg n).Nodup := by
  unfold keysOf
  exact List.Pairwise.map _ (fun _ _ hab h => hab (Key.mk.inj h).2.2.2) List.nodup_range

theorem keysOf_rep (sha lane cfg : String) (n : Nat) : (keysOf sha lane cfg n).map (·.rep) = List.range n := by
  simp [keysOf, Function.comp_def]

/-- One planned unit: a key and the leg (job) of its lane that measures it. -/
structure Item where
  key : Key
  leg : Nat
deriving DecidableEq, Repr

/-- One artifact: the unit, the `run_attempt` it ran in and the provider it ran on. -/
structure Art where
  item : Item
  attempt : Nat
  provider : Provider
deriving DecidableEq, Repr

/-- The provider field of an artifact name. -/
def providerTag : Provider → String
  | .github => "github"
  | .circleci => "circleci"

/-- `a` then a dash then `rest`. -/
def seg (a rest : List Char) : List Char := a ++ '-' :: rest

/-- `mres-<sha>-<cfg>-r<rep>-l<leg>-a<attempt>-<provider>-<lane>`. -/
def Art.name (a : Art) : String :=
  String.ofList <|
    seg "mres".toList <| seg a.item.key.sha.toList <| seg a.item.key.cfg.toList <|
    seg ('r' :: (Nat.repr a.item.key.rep).toList) <| seg ('l' :: (Nat.repr a.item.leg).toList) <|
    seg ('a' :: (Nat.repr a.attempt).toList) <| seg (providerTag a.provider).toList a.item.key.lane.toList

theorem seg_inj {a b x y : List Char} (ha : '-' ∉ a) (hb : '-' ∉ b) (h : seg a x = seg b y) : a = b ∧ x = y := by
  induction a generalizing b with
  | nil =>
    cases b with
    | nil => simp_all [seg]
    | cons d b => simp only [seg, List.nil_append, List.cons_append, List.cons.injEq] at h; simp_all
  | cons c a ih =>
    cases b with
    | nil => simp only [seg, List.nil_append, List.cons_append, List.cons.injEq] at h; simp_all
    | cons d b =>
      simp only [seg, List.cons_append, List.cons.injEq] at h
      obtain ⟨rfl, h⟩ := h
      have := ih (by simp_all) (by simp_all) h
      simp_all

theorem dash_not_mem_of_all {p : Char → Bool} {l : List Char} (hp : p '-' = false) (h : l.all p = true) :
    '-' ∉ l := by
  intro hm
  have := List.all_eq_true.mp h _ hm
  simp_all

theorem dash_not_mem_repr (n : Nat) : '-' ∉ (Nat.repr n).toList := by
  intro hm
  rw [Nat.toList_repr] at hm
  have := Nat.isDigit_of_mem_toDigits (by decide) (by decide) hm
  simp [Char.isDigit] at this

theorem dash_not_mem_tag (p : Provider) : '-' ∉ (providerTag p).toList := by
  cases p <;> decide

theorem providerTag_inj {p q : Provider} (h : (providerTag p).toList = (providerTag q).toList) : p = q := by
  cases p <;> cases q <;> first | rfl | (exfalso; revert h; decide)

theorem valid_sha {k : Key} (h : k.valid = true) : '-' ∉ k.sha.toList := by
  simp only [Key.valid, hexOf, Bool.and_eq_true] at h
  exact dash_not_mem_of_all (by decide) h.1.1.1.2

theorem valid_cfg {k : Key} (h : k.valid = true) : '-' ∉ k.cfg.toList := by
  simp only [Key.valid, hexOf, Bool.and_eq_true] at h
  exact dash_not_mem_of_all (by decide) h.1.1.2.2

theorem repr_seg_inj {c : Char} {m n : Nat} (h : c :: (Nat.repr m).toList = c :: (Nat.repr n).toList) : m = n :=
  Nat.repr_injective (String.toList_inj.mp (List.cons.inj h).2)

theorem name_inj {a b : Art} (ha : a.item.key.valid = true) (hb : b.item.key.valid = true) (h : a.name = b.name) :
    a = b := by
  have h := congrArg String.toList h
  simp only [Art.name, String.toList_ofList] at h
  have hd : ∀ {c : Char} (n : Nat), c ≠ '-' → '-' ∉ c :: (Nat.repr n).toList := fun n hc hm => by
    rcases List.mem_cons.mp hm with e | e
    · exact hc e.symm
    · exact dash_not_mem_repr n e
  have hm : '-' ∉ "mres".toList := by decide
  obtain ⟨-, h⟩ := seg_inj hm hm h
  obtain ⟨hsha, h⟩ := seg_inj (valid_sha ha) (valid_sha hb) h
  obtain ⟨hcfg, h⟩ := seg_inj (valid_cfg ha) (valid_cfg hb) h
  obtain ⟨hrep, h⟩ := seg_inj (hd _ (by decide)) (hd _ (by decide)) h
  obtain ⟨hleg, h⟩ := seg_inj (hd _ (by decide)) (hd _ (by decide)) h
  obtain ⟨hatt, h⟩ := seg_inj (hd _ (by decide)) (hd _ (by decide)) h
  obtain ⟨hprov, hlane⟩ := seg_inj (dash_not_mem_tag _) (dash_not_mem_tag _) h
  obtain ⟨⟨⟨sha, lane, cfg, rep⟩, leg⟩, att, prov⟩ := a
  obtain ⟨⟨⟨sha', lane', cfg', rep'⟩, leg'⟩, att', prov'⟩ := b
  simp only at hsha hcfg hrep hleg hatt hprov hlane
  rw [String.toList_inj] at hsha hcfg hlane
  rw [repr_seg_inj hrep, repr_seg_inj hleg, repr_seg_inj hatt, providerTag_inj hprov, hsha, hcfg, hlane]

/-- The state of one unit: a job wrote `result`, `failed`, `stale` or `skipped`; the reduce writes `notRun`; a request the
router still holds is `waiting`. -/
inductive Outcome where
  | result
  | failed
  | stale
  | skipped
  | notRun
  | waiting
deriving DecidableEq, Repr

/-- Every outcome but `waiting` ends the unit. -/
def Outcome.terminal : Outcome → Bool
  | .waiting => false
  | _ => true

/-- An outcome a job that ran writes into its artifact; only these are read back by the reduce. -/
def Outcome.delivered : Outcome → Bool
  | .result | .failed | .stale | .skipped => true
  | .notRun | .waiting => false

/-- The outcomes that fail the run's conclusion. -/
def Outcome.fails : Outcome → Bool
  | .failed | .notRun => true
  | _ => false

/-- The `outcome` field of `outcome.json` and of the golden. -/
def Outcome.tag : Outcome → String
  | .result => "result"
  | .failed => "failed"
  | .stale => "stale"
  | .skipped => "skipped"
  | .notRun => "notRun"
  | .waiting => "waiting"

/-- Every outcome, in tag order. -/
def Outcome.all : List Outcome := [.result, .failed, .stale, .skipped, .notRun, .waiting]

theorem delivered_terminal (o : Outcome) (h : o.delivered = true) : o.terminal = true := by
  cases o <;> simp_all [Outcome.delivered, Outcome.terminal]

theorem waiting_not_terminal : Outcome.waiting.terminal = false := rfl

theorem notRun_not_delivered : Outcome.notRun.delivered = false := rfl

theorem fails_failed : Outcome.failed.fails = true := rfl

theorem fails_notRun : Outcome.notRun.fails = true := rfl

theorem fails_iff (o : Outcome) : o.fails = true ↔ o = .failed ∨ o = .notRun := by cases o <;> simp [Outcome.fails]

theorem tag_nodup : (Outcome.all.map Outcome.tag).Nodup := by decide

/-- The content of one artifact's `outcome.json`. -/
structure Rec where
  art : Art
  outcome : Outcome
deriving DecidableEq, Repr

/-- One reduced row: the unit, its terminal outcome and the artifact it was read from (`none` for `notRun`). -/
structure Row where
  item : Item
  outcome : Outcome
  art : Option Art
deriving DecidableEq, Repr

/-- Tie order between providers on equal attempts. -/
def providerRank : Provider → Nat
  | .github => 0
  | .circleci => 1

/-- `r` wins over `b`: a later attempt, or the same attempt and a provider of no higher rank. -/
def wins (r b : Rec) : Bool :=
  b.art.attempt < r.art.attempt ||
    (b.art.attempt == r.art.attempt && providerRank r.art.provider ≤ providerRank b.art.provider)

/-- The winning record of a list: the latest attempt, ties to the lower provider rank, then to the first. -/
def best : List Rec → Option Rec
  | [] => none
  | r :: rs =>
    match best rs with
    | none => some r
    | some b => if wins r b then some r else some b

theorem best_none_iff {l : List Rec} : best l = none ↔ l = [] := by
  cases l with
  | nil => simp [best]
  | cons r rs => simp only [best, reduceCtorEq, iff_false]; split <;> (try split) <;> simp

theorem best_mem {l : List Rec} {r : Rec} (h : best l = some r) : r ∈ l := by
  induction l generalizing r with
  | nil => simp [best] at h
  | cons x xs ih =>
    simp only [best] at h
    split at h
    · cases h; simp
    · rename_i b hb
      split at h
      · cases h; simp
      · cases h; exact List.mem_cons_of_mem _ (ih hb)

theorem best_latest {l : List Rec} {r : Rec} (h : best l = some r) : ∀ x ∈ l, x.art.attempt ≤ r.art.attempt := by
  induction l generalizing r with
  | nil => simp [best] at h
  | cons x xs ih =>
    simp only [best] at h
    split at h
    · rename_i hn
      cases h
      rw [best_none_iff] at hn
      subst hn
      simp
    · rename_i b hb
      have ihb := ih hb
      split at h
      · rename_i hw
        cases h
        simp only [wins, Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq] at hw
        intro y hy
        rcases List.mem_cons.mp hy with e | e
        · subst e; exact Nat.le_refl _
        · have := ihb y e; omega
      · rename_i hw
        cases h
        simp only [wins, Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq, not_or, not_and] at hw
        intro y hy
        rcases List.mem_cons.mp hy with e | e
        · subst e; omega
        · exact ihb y e

/-- The delivered records of unit `i`, from any provider and any attempt. -/
def deliveredOf (recs : List Rec) (i : Item) : List Rec := recs.filter fun r => r.art.item == i && r.outcome.delivered

/-- The record the reduce reads for unit `i`, if any job delivered one. -/
def pick (recs : List Rec) (i : Item) : Option Rec := best (deliveredOf recs i)

/-- The row of unit `i`: the picked record's outcome, or `notRun` when no artifact delivered one (runner loss). -/
def rowOf (recs : List Rec) (i : Item) : Row :=
  match pick recs i with
  | some r => ⟨i, r.outcome, some r.art⟩
  | none => ⟨i, .notRun, none⟩

/-- The Linux reduce step: one row per planned unit, read from every artifact of the run, whatever its provider. -/
def reduce (plan : List Item) (recs : List Rec) : List Row := plan.map (rowOf recs)

/-- The conclusion of a reduced run fails iff some row fails. -/
def runFails (rows : List Row) : Bool := rows.any (·.outcome.fails)

theorem rowOf_item (recs : List Rec) (i : Item) : (rowOf recs i).item = i := by
  unfold rowOf; split <;> rfl

theorem rowOf_terminal (recs : List Rec) (i : Item) : (rowOf recs i).outcome.terminal = true := by
  unfold rowOf
  split
  · rename_i r hr
    have := best_mem hr
    simp only [deliveredOf, List.mem_filter, Bool.and_eq_true] at this
    exact delivered_terminal _ this.2.2
  · rfl

theorem rowOf_notRun_of_none (recs : List Rec) (i : Item)
    (h : ∀ r ∈ recs, r.art.item = i → r.outcome.delivered = false) : rowOf recs i = ⟨i, .notRun, none⟩ := by
  have : deliveredOf recs i = [] := by
    simp only [deliveredOf, List.filter_eq_nil_iff, Bool.and_eq_true, beq_iff_eq, not_and, Bool.not_eq_true]
    exact h
  simp [rowOf, pick, this, best]

theorem rowOf_of_delivered (recs : List Rec) (i : Item) (x : Rec) (hx : x ∈ recs) (hi : x.art.item = i)
    (hd : x.outcome.delivered = true) :
    ∃ r ∈ recs, rowOf recs i = ⟨i, r.outcome, some r.art⟩ ∧ r.art.item = i ∧ r.outcome.delivered = true ∧
      x.art.attempt ≤ r.art.attempt := by
  have hxd : x ∈ deliveredOf recs i := by simp [deliveredOf, hx, hi, hd]
  cases hp : pick recs i with
  | none => simp [pick, best_none_iff] at hp; simp [hp] at hxd
  | some r =>
    have hm := best_mem hp
    simp only [deliveredOf, List.mem_filter, Bool.and_eq_true, beq_iff_eq] at hm
    exact ⟨r, hm.1, by simp [rowOf, hp], hm.2.1, hm.2.2, best_latest hp x hxd⟩

theorem rowOf_notRun_iff (recs : List Rec) (i : Item) :
    (rowOf recs i).outcome = .notRun ↔ ∀ r ∈ recs, r.art.item = i → r.outcome.delivered = false := by
  constructor
  · intro h x hx hi
    cases hd : x.outcome.delivered
    · rfl
    · obtain ⟨r, -, hr, -, hrd, -⟩ := rowOf_of_delivered recs i x hx hi hd
      rw [hr] at h
      simp only at h
      rw [h] at hrd
      exact absurd hrd (by decide)
  · intro h; rw [rowOf_notRun_of_none recs i h]

theorem delivered_counted (recs : List Rec) (i : Item) (x : Rec) (hx : x ∈ recs) (hi : x.art.item = i)
    (hd : x.outcome.delivered = true) : (rowOf recs i).outcome ≠ .notRun := by
  intro h
  have := (rowOf_notRun_iff recs i).mp h x hx hi
  simp_all

theorem reduce_items (plan : List Item) (recs : List Rec) : (reduce plan recs).map (·.item) = plan := by
  simp [reduce, Function.comp_def, rowOf_item]

theorem reduce_terminal (plan : List Item) (recs : List Rec) :
    ∀ row ∈ reduce plan recs, row.outcome.terminal = true := by
  intro row h
  simp only [reduce, List.mem_map] at h
  obtain ⟨i, -, rfl⟩ := h
  exact rowOf_terminal recs i

theorem reduce_count (plan : List Item) (recs : List Rec) (i : Item) :
    (reduce plan recs).countP (·.item == i) = plan.count i := by
  simp only [reduce, List.countP_map, List.count]
  congr
  funext j
  simp [rowOf_item]

theorem exactly_one_row (plan : List Item) (recs : List Rec) (hp : plan.Nodup) {i : Item} (hi : i ∈ plan) :
    (reduce plan recs).countP (·.item == i) = 1 := by
  rw [reduce_count, hp.count_of_mem hi]

theorem no_row_unplanned (plan : List Item) (recs : List Rec) {i : Item} (hi : i ∉ plan) :
    (reduce plan recs).countP (·.item == i) = 0 := by
  rw [reduce_count, List.count_eq_zero_of_not_mem hi]

theorem runFails_iff (rows : List Row) :
    runFails rows = true ↔ ∃ row ∈ rows, row.outcome = .failed ∨ row.outcome = .notRun := by
  simp [runFails, fails_iff]

/-- The in-job `if: always()` step: a `notRun` record for each of the job's units it wrote no record for. -/
def fastPath (mine : List Item) (attempt : Nat) (provider : Provider) (written : List Rec) : List Rec :=
  (mine.filter fun i => !written.any (·.art.item == i)).map fun i => ⟨⟨i, attempt, provider⟩, .notRun⟩

theorem fastPath_notRun (mine : List Item) (a : Nat) (p : Provider) (written : List Rec) :
    ∀ r ∈ fastPath mine a p written, r.outcome = .notRun := by
  intro r hr
  simp only [fastPath, List.mem_map] at hr
  obtain ⟨_, -, rfl⟩ := hr
  rfl

theorem fastPath_covers (mine : List Item) (a : Nat) (p : Provider) (written : List Rec) :
    ∀ i ∈ mine, ∃ r ∈ written ++ fastPath mine a p written, r.art.item = i := by
  intro i hi
  by_cases hw : written.any (·.art.item == i) = true
  · obtain ⟨r, hr, he⟩ := List.any_eq_true.mp hw
    exact ⟨r, List.mem_append_left _ hr, by simpa using he⟩
  · refine ⟨⟨⟨i, a, p⟩, .notRun⟩, List.mem_append_right _ ?_, rfl⟩
    simp only [fastPath, List.mem_map, List.mem_filter]
    exact ⟨i, ⟨hi, by simpa using hw⟩, rfl⟩

theorem reduce_ignores_notRun (plan : List Item) (recs extra : List Rec) (h : ∀ r ∈ extra, r.outcome = .notRun) :
    reduce plan (recs ++ extra) = reduce plan recs := by
  have : ∀ i, deliveredOf (recs ++ extra) i = deliveredOf recs i := by
    intro i
    have he : deliveredOf extra i = [] := by
      simp only [deliveredOf, List.filter_eq_nil_iff, Bool.and_eq_true, not_and]
      intro r hr _
      simp [h r hr, Outcome.delivered]
    simp only [deliveredOf, List.filter_append] at he ⊢
    rw [he, List.append_nil]
  simp [reduce, rowOf, pick, this]

theorem fast_path_only (plan mine : List Item) (recs written : List Rec) (a : Nat) (p : Provider) :
    reduce plan (recs ++ fastPath mine a p written) = reduce plan recs :=
  reduce_ignores_notRun plan recs _ (fastPath_notRun mine a p written)

private def sha1 : String := "0123456789abcdef0123456789abcdef01234567"
private def sha2 : String := "fedcba9876543210fedcba9876543210fedcba98"
private def cfg1 : String := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
private def cfg2 : String := "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"

private def k1 : Key := ⟨sha1, "wktr", cfg1, 0⟩
private def k2 : Key := ⟨sha1, "engine-premises", cfg2, 1⟩
private def i1 : Item := ⟨k1, 0⟩
private def i2 : Item := ⟨k1, 1⟩
private def i3 : Item := ⟨k2, 0⟩
private def rec (i : Item) (a : Nat) (p : Provider) (o : Outcome) : Rec := ⟨⟨i, a, p⟩, o⟩

/-- The keys of the golden's `key` rows: valid ones and one per broken field. -/
def keyVectors : List Key :=
  [k1, k2, ⟨sha2, "wktr-fixtures", cfg1, 4⟩, ⟨"0123", "wktr", cfg1, 0⟩, ⟨sha1, "wktr", "00ff", 0⟩,
   ⟨sha1.toUpper, "wktr", cfg1, 0⟩, ⟨sha1, "", cfg1, 0⟩, ⟨sha1, "Wktr/x", cfg1, 0⟩]

/-- The artifacts of the golden's `name` rows. -/
def nameVectors : List Art :=
  [⟨i1, 1, .github⟩, ⟨i1, 1, .circleci⟩, ⟨i2, 2, .github⟩, ⟨i3, 12, .circleci⟩,
   ⟨⟨⟨sha2, "wktr-fixtures", cfg1, 4⟩, 3⟩, 1, .github⟩]

/-- The golden's `reduce` cases: name, plan, records. -/
def reduceCases : List (String × List Item × List Rec) :=
  [("all delivered on github", [i1, i2], [rec i1 1 .github .result, rec i2 1 .github .failed]),
   ("runner loss gives notRun", [i1, i2], [rec i1 1 .github .result]),
   ("ran on circleci", [i1, i3], [rec i1 1 .github .stale, rec i3 1 .circleci .result]),
   ("latest attempt wins", [i1], [rec i1 1 .github .failed, rec i1 2 .github .result]),
   ("equal attempts: github before circleci", [i1], [rec i1 1 .circleci .failed, rec i1 1 .github .skipped]),
   ("fast-path notRun is ignored", [i1], [rec i1 1 .github .result, rec i1 2 .github .notRun]),
   ("waiting is no delivery", [i1], [rec i1 1 .circleci .waiting]),
   ("unplanned artifacts get no row", [i1], [rec i3 1 .github .result]),
   ("empty plan", [], [rec i1 1 .github .result])]

/-- The golden's `fastPath` cases: name, the job's units, its attempt and provider, the records it wrote. -/
def fastPathCases : List (String × List Item × Nat × Provider × List Rec) :=
  [("one unit unwritten", [i1, i2], 1, .github, [rec i1 1 .github .result]),
   ("all written", [i1], 2, .circleci, [rec i1 2 .circleci .failed]),
   ("nothing written", [i1, i3], 1, .circleci, [])]

private def keyJson (k : Key) : List (String × Json) :=
  [("sha", k.sha), ("lane", k.lane), ("cfg", k.cfg), ("rep", k.rep)]

private def itemJson (i : Item) : Json := Json.mkObj (keyJson i.key ++ [("leg", (i.leg : Json))])

private def artJson (a : Art) : Json :=
  Json.mkObj (keyJson a.item.key ++ [("leg", (a.item.leg : Json)), ("attempt", a.attempt),
    ("provider", providerTag a.provider), ("name", a.name)])

private def recJson (r : Rec) : Json := Json.mkObj [("art", artJson r.art), ("outcome", r.outcome.tag)]

private def rowJson (r : Row) : Json :=
  Json.mkObj [("item", itemJson r.item), ("outcome", r.outcome.tag), ("art", (r.art.map (Json.str ·.name)).getD Json.null)]

private def arr {α : Type} (f : α → Json) (l : List α) : Json := Json.arr (l.map f).toArray

/-- The golden `packages/contracts/golden/ci/pool-key.jsonl`: outcomes, key validity, names, dispatch reps, reduce and
fast-path cases. -/
def goldenText : String :=
  let lines : List Json :=
    [Json.mkObj [("kind", "format"), ("prefix", "mres"), ("shaLen", 40), ("cfgLen", 64),
      ("providers", arr (Json.str ∘ providerTag) [.github, .circleci])]]
    ++ Outcome.all.map (fun o => Json.mkObj [("kind", "outcome"), ("outcome", o.tag), ("terminal", o.terminal),
      ("delivered", o.delivered), ("fails", o.fails)])
    ++ keyVectors.map (fun k => Json.mkObj ([("kind", ("key" : Json))] ++ keyJson k ++ [("valid", (k.valid : Json))]))
    ++ nameVectors.map (fun a => Json.mkObj [("kind", "name"), ("art", artJson a)])
    ++ ([0, 1, 3] : List Nat).map (fun (n : Nat) => Json.mkObj [("kind", "keysOf"), ("n", n),
      ("reps", arr (fun (k : Key) => Json.num k.rep) (keysOf sha1 "wktr" cfg1 n))])
    ++ reduceCases.map (fun (c : String × List Item × List Rec) =>
      let rows := reduce c.2.1 c.2.2
      Json.mkObj [("kind", "reduce"), ("case", c.1), ("plan", arr itemJson c.2.1), ("records", arr recJson c.2.2),
        ("rows", arr rowJson rows), ("runFails", runFails rows)])
    ++ fastPathCases.map (fun (c : String × List Item × Nat × Provider × List Rec) =>
      Json.mkObj [("kind", "fastPath"), ("case", c.1), ("mine", arr itemJson c.2.1), ("attempt", c.2.2.1),
        ("provider", providerTag c.2.2.2.1), ("written", arr recJson c.2.2.2.2),
        ("added", arr recJson (fastPath c.2.1 c.2.2.1 c.2.2.2.1 c.2.2.2.2))])
  String.join (lines.map (·.compress ++ "\n"))

#guard keyVectors.map Key.valid == [true, true, true, false, false, false, false, false]
#guard (Art.name ⟨i1, 1, .github⟩) ==
  "mres-0123456789abcdef0123456789abcdef01234567-00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff-r0-l0-a1-github-wktr"
#guard (Art.name ⟨i3, 12, .circleci⟩).endsWith "-r1-l0-a12-circleci-engine-premises"
#guard (nameVectors.map Art.name).Nodup
#guard (keysOf sha1 "wktr" cfg1 3).map (·.rep) == [0, 1, 2]
#guard keysOf sha1 "wktr" cfg1 0 == []
#guard wins (rec i1 2 .circleci .result) (rec i1 1 .github .result)
#guard wins (rec i1 1 .github .result) (rec i1 1 .circleci .result)
#guard !wins (rec i1 1 .circleci .result) (rec i1 1 .github .result)
#guard (pick [rec i1 1 .github .failed, rec i1 2 .github .result] i1).map (·.outcome) == some .result
#guard pick [rec i1 1 .github .notRun, rec i1 1 .github .waiting] i1 == none
#guard rowOf [rec i3 1 .circleci .result] i3 == ⟨i3, .result, some ⟨i3, 1, .circleci⟩⟩
#guard rowOf [rec i3 1 .circleci .result] i1 == ⟨i1, .notRun, none⟩
#guard (reduce [i1, i2] [rec i1 1 .github .result]).map (·.outcome) == [.result, .notRun]
#guard reduce [] [rec i1 1 .github .result] == []
#guard runFails (reduce [i1, i2] [rec i1 1 .github .result])
#guard !runFails (reduce [i1] [rec i1 1 .github .stale])
#guard (fastPath [i1, i2] 1 .github [rec i1 1 .github .result]).map (·.art.item) == [i2]
#guard fastPath [i1] 2 .circleci [rec i1 2 .circleci .failed] == []
#guard Outcome.all.map Outcome.terminal == [true, true, true, true, true, false]
#guard Outcome.all.map Outcome.fails == [false, true, false, false, true, false]

end Fw.Ci.Pool.Key
