import Fw.Plan.Trailer
import Fw.Console.Preview
import Fw.Gate.Search
/-!
# Builds tab: landed port/fix rows, flag and preset rows, what Preview opens, which searches a picker offers
Every list, target and search of the tab is decided here; `console.builds` and `console.buildsPicker` are the wire ops.
-/
namespace Fw.Console.Builds
open Fw.Console.Preview (Target)

/-- A commit of main's first-parent log. -/
structure LogCommit where
  sha : String
  time : Nat
  body : String
deriving Repr, DecidableEq

/-- A task of the work graph. -/
structure Known where
  id : String
  title : String
deriving Repr, DecidableEq

/-- A landed port or fix task: its land commit and the commit's time. -/
structure Row where
  task : String
  sha : String
  title : String
  landedAt : Nat
deriving Repr, DecidableEq

/-- The id starts with `port-` or `fix-`. -/
def isPortFix (id : String) : Bool := id.startsWith "port-" || id.startsWith "fix-"

/-- The prefix group of a task id. -/
def group (id : String) : String := if id.startsWith "port-" then "port" else "fix"

/-- The row a trailer `Task: t` on commit `c` makes: a known port or fix task, landed at `c`. -/
def rowOf (known : List Known) (c : LogCommit) (t : String) : Option Row :=
  match known.find? (·.id == t) with
  | some k => if isPortFix k.id then some { task := k.id, sha := c.sha, title := k.title, landedAt := c.time } else none
  | none => none

/-- Every landing the log shows, in log order. -/
def landings (known : List Known) (log : List LogCommit) : List Row :=
  log.flatMap fun c => (Fw.Plan.Trailer.trailers c.body).filterMap (rowOf known c)

/-- Newer land time first. -/
def newestFirst (a b : Row) : Bool := decide (b.landedAt ≤ a.landedAt)

/-- The rows whose task is not in `seen` and not an earlier row's task. -/
def dedupeAux (seen : List String) : List Row → List Row
  | [] => []
  | r :: rs => if seen.contains r.task then dedupeAux seen rs else r :: dedupeAux (r.task :: seen) rs

/-- The first row of each task. -/
def dedupe (rs : List Row) : List Row := dedupeAux [] rs

/-- The trailer rows: one row per task at its newest `Task:` trailer landing, newest land first. -/
def trailerRows (known : List Known) (log : List LogCommit) : List Row :=
  dedupe ((landings known log).mergeSort newestFirst)

/-- What a port row's Preview opens: main at its land commit. -/
def portTarget (r : Row) : Target := .main r.sha

/-- What an optimize row's Preview opens: the current main. -/
def optTarget (mainSha : String) : Target := .main mainSha

theorem rowOf_port_fix (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    isPortFix r.task = true := by
  unfold rowOf at h
  split at h
  · rename_i k hk
    split at h
    · rename_i hp
      cases h
      exact hp
    · cases h
  · cases h

theorem rowOf_land (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    r.sha = c.sha ∧ r.landedAt = c.time := by
  unfold rowOf at h
  split at h
  · split at h
    · cases h; exact ⟨rfl, rfl⟩
    · cases h
  · cases h

theorem rowOf_known (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    r.task = t := by
  unfold rowOf at h
  split at h
  · rename_i k hk
    split at h
    · cases h
      have := List.find?_some hk
      simpa using this
    · cases h
  · cases h

theorem mem_landings (known : List Known) (log : List LogCommit) (r : Row) :
    r ∈ landings known log ↔ ∃ c ∈ log, ∃ t ∈ Fw.Plan.Trailer.trailers c.body, rowOf known c t = some r := by
  simp [landings, List.mem_flatMap, List.mem_filterMap]

theorem dedupeAux_sublist (seen : List String) : ∀ rs : List Row, (dedupeAux seen rs).Sublist rs
  | [] => by simp [dedupeAux]
  | r :: rs => by
    unfold dedupeAux
    split
    · exact (dedupeAux_sublist seen rs).cons r
    · exact (dedupeAux_sublist (r.task :: seen) rs).cons_cons r

theorem dedupeAux_fresh (seen : List String) : ∀ rs : List Row, ∀ r ∈ dedupeAux seen rs, r.task ∉ seen
  | [], r, h => by simp [dedupeAux] at h
  | x :: rs, r, h => by
    unfold dedupeAux at h
    split at h
    · exact dedupeAux_fresh seen rs r h
    · rename_i hc
      rcases List.mem_cons.1 h with rfl | h'
      · simpa using hc
      · intro hs
        exact dedupeAux_fresh (x.task :: seen) rs r h' (List.mem_cons_of_mem _ hs)

theorem dedupeAux_nodup (seen : List String) : ∀ rs : List Row, ((dedupeAux seen rs).map (·.task)).Nodup
  | [] => by simp [dedupeAux]
  | x :: rs => by
    unfold dedupeAux
    split
    · exact dedupeAux_nodup seen rs
    · rename_i hc
      rw [List.map_cons, List.nodup_cons]
      refine ⟨?_, dedupeAux_nodup (x.task :: seen) rs⟩
      intro hm
      obtain ⟨r, hr, hrt⟩ := List.mem_map.1 hm
      exact dedupeAux_fresh (x.task :: seen) rs r hr (by rw [hrt]; exact List.mem_cons_self)

theorem dedupeAux_cover (seen : List String) : ∀ rs : List Row, ∀ r ∈ rs,
    r.task ∈ seen ∨ ∃ r' ∈ dedupeAux seen rs, r'.task = r.task
  | [], r, h => by simp at h
  | x :: rs, r, h => by
    unfold dedupeAux
    split
    · rename_i hc
      rcases List.mem_cons.1 h with rfl | h'
      · exact Or.inl (by simpa using hc)
      · exact dedupeAux_cover seen rs r h'
    · rcases List.mem_cons.1 h with rfl | h'
      · exact Or.inr ⟨r, List.mem_cons_self, rfl⟩
      · rcases dedupeAux_cover (x.task :: seen) rs r h' with h1 | ⟨r', hr', ht⟩
        · rcases List.mem_cons.1 h1 with h2 | h2
          · exact Or.inr ⟨x, List.mem_cons_self, h2.symm⟩
          · exact Or.inl h2
        · exact Or.inr ⟨r', List.mem_cons_of_mem _ hr', ht⟩

theorem trailerRows_port_fix (known : List Known) (log : List LogCommit) (r : Row) (h : r ∈ trailerRows known log) :
    isPortFix r.task = true := by
  unfold trailerRows dedupe at h
  have h1 := (dedupeAux_sublist [] _).subset h
  have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 h1
  obtain ⟨c, _, t, _, hr⟩ := (mem_landings known log r).1 h2
  exact rowOf_port_fix known c t r hr

theorem trailerRows_land_commit (known : List Known) (log : List LogCommit) (r : Row) (h : r ∈ trailerRows known log) :
    ∃ c ∈ log, r.sha = c.sha ∧ r.landedAt = c.time := by
  unfold trailerRows dedupe at h
  have h1 := (dedupeAux_sublist [] _).subset h
  have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 h1
  obtain ⟨c, hc, t, _, hr⟩ := (mem_landings known log r).1 h2
  exact ⟨c, hc, rowOf_land known c t r hr⟩

theorem trailerRows_nodup (known : List Known) (log : List LogCommit) :
    ((trailerRows known log).map (·.task)).Nodup := dedupeAux_nodup [] _

theorem trailerRows_sorted (known : List Known) (log : List LogCommit) :
    (trailerRows known log).Pairwise fun a b => b.landedAt ≤ a.landedAt := by
  unfold trailerRows dedupe
  have hs : ((landings known log).mergeSort newestFirst).Pairwise fun a b => newestFirst a b = true :=
    List.pairwise_mergeSort
      (fun a b c hab hbc => by simp only [newestFirst, decide_eq_true_eq] at *; omega)
      (fun a b => by simp [newestFirst]; omega) _
  exact (hs.imp (fun {a b} h => by simpa [newestFirst] using h)).sublist (dedupeAux_sublist [] _)

theorem trailerRows_complete (known : List Known) (log : List LogCommit) (c : LogCommit) (hc : c ∈ log)
    (t : String) (ht : t ∈ Fw.Plan.Trailer.trailers c.body) (r : Row) (hr : rowOf known c t = some r) :
    ∃ r' ∈ trailerRows known log, r'.task = r.task := by
  unfold trailerRows dedupe
  have hm : r ∈ (landings known log).mergeSort newestFirst :=
    (List.mergeSort_perm (landings known log) newestFirst).mem_iff.2 ((mem_landings known log r).2 ⟨c, hc, t, ht, hr⟩)
  rcases dedupeAux_cover [] _ r hm with h | h
  · simp at h
  · exact h

theorem portTarget_land (r : Row) : portTarget r = .main r.sha := rfl

theorem optTarget_main (m : String) : optTarget m = .main m := rfl

/-- Evidence fact of the work graph: task `task` has its evidence on main, whose land commit (the oldest first-parent commit of
main that has the evidence commit as an ancestor, resolved by the glue) is `sha`. -/
structure EvLand where
  task : String
  sha : String
deriving Repr, DecidableEq

/-- The row an evidence fact makes: its land commit must be in the log, the task a known port or fix task. -/
def evRowOf (known : List Known) (log : List LogCommit) (e : EvLand) : Option Row :=
  match log.find? (·.sha == e.sha) with
  | some c => rowOf known c e.task
  | none => none

/-- Every evidence landing. -/
def evLandings (known : List Known) (log : List LogCommit) (ev : List EvLand) : List Row :=
  ev.filterMap (evRowOf known log)

/-- The evidence rows of tasks that have no trailer row (a trailer landing wins), one per task, newest first. -/
def evOnly (known : List Known) (log : List LogCommit) (ev : List EvLand) : List Row :=
  (dedupe ((evLandings known log ev).mergeSort newestFirst)).filter fun r =>
    !((trailerRows known log).any fun x => x.task == r.task)

/-- The port list: every landed port or fix task has one row, at its trailer landing if it has one, else at its evidence
landing; newest land first. -/
def portRows (known : List Known) (log : List LogCommit) (ev : List EvLand) : List Row :=
  (trailerRows known log ++ evOnly known log ev).mergeSort newestFirst

theorem dedupeAux_newest (seen : List String) : ∀ rs : List Row, rs.Pairwise (fun a b => b.landedAt ≤ a.landedAt) →
    ∀ r ∈ dedupeAux seen rs, ∀ r' ∈ rs, r'.task = r.task → r'.landedAt ≤ r.landedAt
  | [], _, r, h, _, _, _ => by simp [dedupeAux] at h
  | x :: rs, hp, r, h, r', hr', ht => by
    rw [List.pairwise_cons] at hp
    unfold dedupeAux at h
    split at h
    · rename_i hc
      rcases List.mem_cons.1 hr' with rfl | hr'
      · exact absurd (by rw [← ht]; simpa using hc) (dedupeAux_fresh seen rs r h)
      · exact dedupeAux_newest seen rs hp.2 r h r' hr' ht
    · rename_i hc
      rcases List.mem_cons.1 h with rfl | h'
      · rcases List.mem_cons.1 hr' with rfl | hr'
        · exact Nat.le_refl _
        · exact hp.1 r' hr'
      · rcases List.mem_cons.1 hr' with rfl | hr'
        · exact absurd (by rw [← ht]; exact List.mem_cons_self) (dedupeAux_fresh (r'.task :: seen) rs r h')
        · exact dedupeAux_newest (x.task :: seen) rs hp.2 r h' r' hr' ht

theorem landings_sorted (known : List Known) (log : List LogCommit) :
    ((landings known log).mergeSort newestFirst).Pairwise fun a b => b.landedAt ≤ a.landedAt := by
  have hs : ((landings known log).mergeSort newestFirst).Pairwise fun a b => newestFirst a b = true :=
    List.pairwise_mergeSort
      (fun a b c hab hbc => by simp only [newestFirst, decide_eq_true_eq] at *; omega)
      (fun a b => by simp [newestFirst]; omega) _
  exact hs.imp (fun {a b} h => by simpa [newestFirst] using h)

theorem mem_evLandings (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row) :
    r ∈ evLandings known log ev ↔ ∃ e ∈ ev, ∃ c, log.find? (·.sha == e.sha) = some c ∧ rowOf known c e.task = some r := by
  unfold evLandings evRowOf
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨e, he, h⟩
    cases hf : log.find? (·.sha == e.sha) with
    | none => rw [hf] at h; cases h
    | some c => rw [hf] at h; exact ⟨e, he, c, hf, h⟩
  · rintro ⟨e, he, c, hf, h⟩
    exact ⟨e, he, by rw [hf]; exact h⟩

theorem mem_evOnly (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row) :
    r ∈ evOnly known log ev → r ∈ evLandings known log ev ∧ ∀ x ∈ trailerRows known log, x.task ≠ r.task := by
  intro h
  unfold evOnly at h
  rcases List.mem_filter.1 h with ⟨h1, h2⟩
  refine ⟨(List.mergeSort_perm (evLandings known log ev) newestFirst).mem_iff.1 ((dedupeAux_sublist [] _).subset h1), ?_⟩
  intro x hx hxt
  have : ((trailerRows known log).any fun x => x.task == r.task) = true :=
    List.any_eq_true.2 ⟨x, hx, by simpa using hxt⟩
  rw [this] at h2
  cases h2

theorem mem_portRows (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row) :
    r ∈ portRows known log ev ↔ r ∈ trailerRows known log ∨ r ∈ evOnly known log ev := by
  unfold portRows
  rw [(List.mergeSort_perm _ newestFirst).mem_iff, List.mem_append]

/-- Row: the row is a known port or fix task. -/
theorem portRows_port_fix (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row)
    (h : r ∈ portRows known log ev) : isPortFix r.task = true := by
  rcases (mem_portRows known log ev r).1 h with h | h
  · exact trailerRows_port_fix known log r h
  · obtain ⟨e, _, c', _, hr⟩ := (mem_evLandings known log ev r).1 (mem_evOnly known log ev r h).1
    exact rowOf_port_fix known c' e.task r hr

/-- Row, slot, landing (trailer branch): a row of a task with a trailer landing is at a trailer commit of the log. -/
theorem portRows_trailer_land (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row)
    (h : r ∈ portRows known log ev) (ht : ∃ x ∈ landings known log, x.task = r.task) :
    ∃ c ∈ log, r.sha = c.sha ∧ r.landedAt = c.time ∧ r.task ∈ Fw.Plan.Trailer.trailers c.body := by
  rcases (mem_portRows known log ev r).1 h with h | h
  · have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 ((dedupeAux_sublist [] _).subset h)
    obtain ⟨c, hc, t, htr, hr⟩ := (mem_landings known log r).1 h2
    have := rowOf_known known c t r hr
    exact ⟨c, hc, (rowOf_land known c t r hr).1, (rowOf_land known c t r hr).2, this ▸ htr⟩
  · exfalso
    obtain ⟨x, hx, hxt⟩ := ht
    have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.2 hx
    rcases dedupeAux_cover [] _ x h2 with h3 | ⟨r', hr', ht'⟩
    · simp at h3
    · exact (mem_evOnly known log ev r h).2 r' hr' (by rw [ht', hxt])

/-- Row, slot, landing (evidence branch): a row of a task without a trailer landing is at the land commit of an evidence fact. -/
theorem portRows_evidence_land (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row)
    (h : r ∈ portRows known log ev) (ht : ∀ x ∈ landings known log, x.task ≠ r.task) :
    ∃ c ∈ log, r.sha = c.sha ∧ r.landedAt = c.time ∧ ∃ e ∈ ev, e.task = r.task ∧ e.sha = c.sha := by
  rcases (mem_portRows known log ev r).1 h with h | h
  · exfalso
    have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 ((dedupeAux_sublist [] _).subset h)
    obtain ⟨c, hc, t, htr, hr⟩ := (mem_landings known log r).1 h2
    exact ht r ((mem_landings known log r).2 ⟨c, hc, t, htr, hr⟩) rfl
  · obtain ⟨e, he, c, hf, hr⟩ := (mem_evLandings known log ev r).1 (mem_evOnly known log ev r h).1
    have hcs : c.sha = e.sha := by simpa using List.find?_some hf
    exact ⟨c, List.mem_of_find?_eq_some hf, (rowOf_land known c e.task r hr).1, (rowOf_land known c e.task r hr).2, e, he,
      rowOf_known known c e.task r hr ▸ rfl, hcs.symm⟩

/-- Landing: every row's sha and time are those of a commit of the log, a trailer commit or an evidence land commit. -/
theorem portRows_land_commit (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row)
    (h : r ∈ portRows known log ev) :
    ∃ c ∈ log, r.sha = c.sha ∧ r.landedAt = c.time ∧
      (r.task ∈ Fw.Plan.Trailer.trailers c.body ∨ ∃ e ∈ ev, e.task = r.task ∧ e.sha = c.sha) := by
  by_cases ht : ∃ x ∈ landings known log, x.task = r.task
  · obtain ⟨c, hc, h1, h2, h3⟩ := portRows_trailer_land known log ev r h ht
    exact ⟨c, hc, h1, h2, Or.inl h3⟩
  · have ht' : ∀ x ∈ landings known log, x.task ≠ r.task := fun x hx hxt => ht ⟨x, hx, hxt⟩
    obtain ⟨c, hc, h1, h2, h3⟩ := portRows_evidence_land known log ev r h ht'
    exact ⟨c, hc, h1, h2, Or.inr h3⟩

/-- The row is the task's newest trailer landing. -/
theorem portRows_newest (known : List Known) (log : List LogCommit) (ev : List EvLand) (r : Row)
    (h : r ∈ portRows known log ev) (r' : Row) (hr' : r' ∈ landings known log) (ht : r'.task = r.task) :
    r'.landedAt ≤ r.landedAt := by
  rcases (mem_portRows known log ev r).1 h with h | h
  · exact dedupeAux_newest [] _ (landings_sorted known log) r h r'
      ((List.mergeSort_perm (landings known log) newestFirst).mem_iff.2 hr') ht
  · exfalso
    have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.2 hr'
    rcases dedupeAux_cover [] _ r' h2 with h3 | ⟨x, hx, ht'⟩
    · simp at h3
    · exact (mem_evOnly known log ev r h).2 x hx (by rw [ht', ht])

theorem portRows_nodup (known : List Known) (log : List LogCommit) (ev : List EvLand) :
    ((portRows known log ev).map (·.task)).Nodup := by
  unfold portRows
  refine ((List.mergeSort_perm _ newestFirst).map _).nodup_iff.2 ?_
  rw [List.map_append, List.nodup_append]
  refine ⟨dedupeAux_nodup [] _, ?_, ?_⟩
  · unfold evOnly
    exact (((dedupeAux_nodup [] _)).sublist (List.Sublist.map _ (List.filter_sublist)))
  · intro a ha b hb hab
    obtain ⟨x, hx, rfl⟩ := List.mem_map.1 ha
    obtain ⟨y, hy, rfl⟩ := List.mem_map.1 hb
    exact (mem_evOnly known log ev y hy).2 x hx hab

theorem portRows_sorted (known : List Known) (log : List LogCommit) (ev : List EvLand) :
    (portRows known log ev).Pairwise fun a b => b.landedAt ≤ a.landedAt := by
  unfold portRows
  have hs : ((trailerRows known log ++ evOnly known log ev).mergeSort newestFirst).Pairwise fun a b => newestFirst a b = true :=
    List.pairwise_mergeSort
      (fun a b c hab hbc => by simp only [newestFirst, decide_eq_true_eq] at *; omega)
      (fun a b => by simp [newestFirst]; omega) _
  exact hs.imp (fun {a b} h => by simpa [newestFirst] using h)

/-- Completeness (trailer branch): a task with a trailer landing has a row. -/
theorem portRows_complete_trailer (known : List Known) (log : List LogCommit) (ev : List EvLand) (c : LogCommit) (hc : c ∈ log)
    (t : String) (ht : t ∈ Fw.Plan.Trailer.trailers c.body) (r : Row) (hr : rowOf known c t = some r) :
    ∃ r' ∈ portRows known log ev, r'.task = r.task := by
  obtain ⟨r', hr', h⟩ := trailerRows_complete known log c hc t ht r hr
  exact ⟨r', (mem_portRows known log ev r').2 (Or.inl hr'), h⟩

/-- Completeness (evidence branch): a known port or fix task whose evidence land commit is in the log has a row. -/
theorem portRows_complete_evidence (known : List Known) (log : List LogCommit) (ev : List EvLand) (e : EvLand) (he : e ∈ ev)
    (c : LogCommit) (hc : c ∈ log) (hcs : c.sha = e.sha) (r : Row) (hr : rowOf known c e.task = some r) :
    ∃ r' ∈ portRows known log ev, r'.task = r.task := by
  have hsome : (log.find? (·.sha == e.sha)).isSome = true :=
    List.find?_isSome.2 ⟨c, hc, by simp [hcs]⟩
  obtain ⟨c', hf⟩ := Option.isSome_iff_exists.1 hsome
  -- the row of `c'` is a row of the same task
  have hk : ∃ r2, rowOf known c' e.task = some r2 := by
    unfold rowOf at hr ⊢
    split at hr
    · rename_i k hk
      split at hr
      · rename_i hp
        simp [hp]
      · cases hr
    · cases hr
  obtain ⟨r2, hr2⟩ := hk
  have hm : r2 ∈ evLandings known log ev := (mem_evLandings known log ev r2).2 ⟨e, he, c', hf, hr2⟩
  by_cases hT : ∃ x ∈ trailerRows known log, x.task = r2.task
  · obtain ⟨x, hx, hxt⟩ := hT
    exact ⟨x, (mem_portRows known log ev x).2 (Or.inl hx), by rw [hxt, rowOf_known known c' e.task r2 hr2, rowOf_known known c e.task r hr]⟩
  · have hm2 : r2 ∈ (evLandings known log ev).mergeSort newestFirst :=
      (List.mergeSort_perm _ newestFirst).mem_iff.2 hm
    rcases dedupeAux_cover [] _ r2 hm2 with h | ⟨r', hr', ht'⟩
    · simp at h
    · refine ⟨r', (mem_portRows known log ev r').2 (Or.inr ?_), by rw [ht', rowOf_known known c' e.task r2 hr2, rowOf_known known c e.task r hr]⟩
      unfold evOnly
      refine List.mem_filter.2 ⟨hr', ?_⟩
      simp only [Bool.not_eq_true', List.any_eq_false]
      intro x hx
      have : x.task ≠ r'.task := fun hxe => hT ⟨x, hx, by rw [hxe, ht']⟩
      simpa using this

/-! ## Optimize rows -/

/-- A registered flag variant (`part.json`): `requires` are the `part:variant` keys it is requested with. -/
structure Flag where
  part : String
  variant : String
  kind : String
  requires : List String
deriving Repr, DecidableEq

/-- A preset: its name and the variant it sets per part. -/
structure Preset where
  name : String
  fw : List (String × String)
deriving Repr, DecidableEq

/-- The `part:variant` key. -/
def Flag.key (f : Flag) : String := f.part ++ ":" ++ f.variant

/-- The prerendered search of a flag variant, written like `enumerateSearches` in `apps/site/src/entry-server.tsx`. -/
def flagSearch (f : Flag) : String := "?fw=" ++ ",".intercalate (f.key :: f.requires)

/-- The prerendered search of a preset. -/
def presetSearch (name : String) : String := "?preset=" ++ name

/-- The searches a build prerenders: default, each preset, each single variant. -/
def enumerate (presets : List Preset) (flags : List Flag) : List String :=
  "" :: (presets.map (fun p => presetSearch p.name) ++ flags.map flagSearch)

/-- What the tab says about a row. -/
inductive Status where
  | v2Proved
  | c3Out
  | baseline
  | notInV2
  | presetV2
  | presetOther
deriving DecidableEq, Repr

/-- The wire name of a status. -/
def Status.name : Status → String
  | .v2Proved => "v2-proved"
  | .c3Out => "out of v2-proved (C3)"
  | .baseline => "baseline"
  | .notInV2 => "not in v2-proved"
  | .presetV2 => "the v2-proved preset"
  | .presetOther => "preset"

/-- Flags the C3 decision (wave-2 gate) took out of v2-proved. -/
def c3Out : List String := ["hero.countdown:strip"]

/-- The note shown with a C3 row. -/
def c3Note : String := "C3 decision: out of v2-proved after the wave-2 gate; the generated preset follows in c3-preset-update"

/-- The note of a status. -/
def Status.note : Status → Option String
  | .c3Out => some c3Note
  | _ => none

/-- The variant is set by the generated `v2-proved` preset. -/
def inV2 (presets : List Preset) (f : Flag) : Bool :=
  presets.any fun p => p.name == "v2-proved" && p.fw.any fun kv => kv.1 == f.part && kv.2 == f.variant

/-- A C3 flag is out whatever the generated preset still says; else the baseline; else the preset decides. -/
def flagStatus (presets : List Preset) (f : Flag) : Status :=
  if c3Out.contains f.key then .c3Out
  else if f.kind == "faithful" then .baseline
  else if inV2 presets f then .v2Proved else .notInV2

/-- The status of a preset row. -/
def presetStatus (p : Preset) : Status := if p.name == "v2-proved" then .presetV2 else .presetOther

/-- A slot character: lowercase letter or digit, else `-`. -/
def slotChar (c : Char) : Char :=
  if ('a' ≤ c.toLower && c.toLower ≤ 'z') || ('0' ≤ c.toLower && c.toLower ≤ '9') then c.toLower else '-'

/-- The preview slot of an optimize row (one live preview per slot). -/
def slot (kind name : String) : String := "opt-" ++ kind ++ "-" ++ String.map slotChar name

/-- The preview slot of a port row: one slot per land build, apart from the task-detail Preview (slot = task id). -/
def landSlot (task : String) : String := "land-" ++ String.map slotChar task

theorem landSlot_eq (task : String) : landSlot task = "land-" ++ String.map slotChar task := rfl

/-- One optimize row. -/
structure Opt where
  kind : String
  name : String
  search : String
  status : Status
  slot : String
deriving Repr, DecidableEq

/-- The optimize list: one row per preset, then one per flag variant. -/
def optRows (presets : List Preset) (flags : List Flag) : List Opt :=
  presets.map (fun p => { kind := "preset", name := p.name, search := presetSearch p.name, status := presetStatus p,
                          slot := slot "preset" p.name }) ++
  flags.map (fun f => { kind := "flag", name := f.key, search := flagSearch f, status := flagStatus presets f,
                        slot := slot "flag" f.key })

theorem optRows_length (presets : List Preset) (flags : List Flag) :
    (optRows presets flags).length = presets.length + flags.length := by
  simp [optRows]

theorem optRows_prerendered (presets : List Preset) (flags : List Flag) (o : Opt) (h : o ∈ optRows presets flags) :
    o.search ∈ enumerate presets flags := by
  simp only [optRows, List.mem_append, List.mem_map] at h
  simp only [enumerate, List.mem_cons, List.mem_append, List.mem_map]
  rcases h with ⟨p, hp, rfl⟩ | ⟨f, hf, rfl⟩
  · exact Or.inr (Or.inl ⟨p, hp, rfl⟩)
  · exact Or.inr (Or.inr ⟨f, hf, rfl⟩)

theorem flagStatus_c3 (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    flagStatus presets f = .c3Out := by unfold flagStatus; rw [h]; simp

theorem flagStatus_baseline (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : f.kind = "faithful") :
    flagStatus presets f = .baseline := by unfold flagStatus; rw [h]; simp [hk]

theorem flagStatus_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : (f.kind == "faithful") = false)
    (hv : inV2 presets f = true) : flagStatus presets f = .v2Proved := by unfold flagStatus; rw [h, hk, hv]; simp

theorem flagStatus_not_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : (f.kind == "faithful") = false)
    (hv : inV2 presets f = false) : flagStatus presets f = .notInV2 := by unfold flagStatus; rw [h, hk, hv]; simp

theorem c3_never_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    flagStatus presets f ≠ .v2Proved := by rw [flagStatus_c3 presets f h]; decide

theorem c3_note (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    (flagStatus presets f).note = some c3Note := by rw [flagStatus_c3 presets f h]; rfl

theorem slotChar_alphabet (c : Char) : ('a' ≤ slotChar c ∧ slotChar c ≤ 'z') ∨ ('0' ≤ slotChar c ∧ slotChar c ≤ '9') ∨ slotChar c = '-' := by
  unfold slotChar
  split
  · rename_i h
    simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
    rcases h with h | h
    · exact Or.inl h
    · exact Or.inr (Or.inl h)
  · exact Or.inr (Or.inr rfl)

/-! ## Picker -/

/-- A preset search: `?preset=` and a valid preset name. -/
def isPresetKey (s : String) : Bool := s.startsWith "?preset=" && Fw.Gate.Search.validPreset (String.ofList (s.toList.drop 8))

/-- A flag search: `?fw=` and a valid flag set. -/
def isFwKey (s : String) : Bool := s.startsWith "?fw=" && Fw.Gate.Search.validFw (String.ofList (s.toList.drop 4))

/-- The picker offers the default, a preset search or a flag search. -/
def offered (s : String) : Bool := s.isEmpty || isPresetKey s || isFwKey s

/-- The searches a build's picker lists, from its prerendered keys: default, presets, flags, each in key order. -/
def picker (keys : List String) : List String :=
  keys.filter (·.isEmpty) ++ keys.filter isPresetKey ++ keys.filter isFwKey

/-- The search the compare view loads for a requested one: itself when offered, else the default. -/
def choose (keys : List String) (cur : String) : String := if (picker keys).contains cur then cur else ""

theorem picker_prerendered (keys : List String) (s : String) (h : s ∈ picker keys) : s ∈ keys := by
  simp only [picker, List.mem_append, List.mem_filter] at h
  rcases h with (h | h) | h
  · exact h.1
  · exact h.1
  · exact h.1

theorem picker_offered (keys : List String) (s : String) (h : s ∈ picker keys) : offered s = true := by
  simp only [picker, List.mem_append, List.mem_filter] at h
  simp only [offered, Bool.or_eq_true]
  rcases h with (h | h) | h
  · exact Or.inl (Or.inl h.2)
  · exact Or.inl (Or.inr h.2)
  · exact Or.inr h.2

theorem picker_complete (keys : List String) (s : String) (hk : s ∈ keys) (ho : offered s = true) : s ∈ picker keys := by
  simp only [picker, List.mem_append, List.mem_filter]
  simp only [offered, Bool.or_eq_true] at ho
  rcases ho with (h | h) | h
  · exact Or.inl (Or.inl ⟨hk, h⟩)
  · exact Or.inl (Or.inr ⟨hk, h⟩)
  · exact Or.inr ⟨hk, h⟩

theorem picker_default_first (keys : List String) (h : "" ∈ keys) : (picker keys).head? = some "" := by
  have hne : keys.filter (·.isEmpty) ≠ [] := by
    intro he
    have := List.filter_eq_nil_iff.1 he "" h
    simp at this
  obtain ⟨a, l, hal⟩ := List.exists_cons_of_ne_nil hne
  have ha : a ∈ keys.filter (·.isEmpty) := by rw [hal]; exact List.mem_cons_self
  have hae : a.isEmpty = true := (List.mem_filter.1 ha).2
  have : a = "" := String.isEmpty_iff.1 hae
  simp [picker, hal, this]

theorem choose_offered (keys : List String) (cur : String) (h : (picker keys).contains cur = true) : choose keys cur = cur := by
  unfold choose; simp only [h]; simp

theorem choose_unknown (keys : List String) (cur : String) (h : (picker keys).contains cur = false) : choose keys cur = "" := by
  unfold choose; simp only [h]; simp

theorem preset_key_chars (s : String) (h : isPresetKey s = true) : ∀ c ∈ s.toList.drop 8, Fw.Gate.Search.presetChar c = true := by
  simp only [isPresetKey, Bool.and_eq_true, Fw.Gate.Search.validPreset, Bool.not_eq_true', List.all_eq_true] at h
  simpa using h.2.2

theorem fw_key_chars (s : String) (h : isFwKey s = true) : ∀ c ∈ s.toList.drop 4, Fw.Gate.Search.fwChar c = true := by
  simp only [isFwKey, Bool.and_eq_true, Fw.Gate.Search.validFw, Bool.not_eq_true', List.all_eq_true] at h
  simpa using h.2.2

end Fw.Console.Builds
