import Fw.Sup.Core

/-! Properties of the fw-sup model (`Fw.Sup.Core`): the invariant, each design theorem on its own, and the trace
theorems over `run`. OS assumptions S1–S6 are prose in `docs/team/handoffs/sup-model.md`, never axioms. -/
namespace Fw.Sup

open Fw.Sched.Admit (Vec Res)

/-! ## List lemmas -/

theorem filterMap_sub {α β : Type} (f g : α → Option β) :
    ∀ l : List α, (∀ x ∈ l, g x = f x ∨ g x = none) → (l.filterMap g).Sublist (l.filterMap f)
  | [], _ => List.Sublist.slnil
  | x :: xs, h => by
    have ih := filterMap_sub f g xs fun y hy => h y (List.mem_cons_of_mem _ hy)
    rcases h x List.mem_cons_self with e | e
    · rw [List.filterMap_cons, List.filterMap_cons, e]
      cases f x with
      | none => exact ih
      | some b => exact ih.cons₂ b
    · rw [List.filterMap_cons, List.filterMap_cons, e]
      cases f x with
      | none => exact ih
      | some b => exact ih.cons b

theorem eq_of_nodup_filterMap {α β : Type} (f : α → Option β) :
    ∀ (l : List α), (l.filterMap f).Nodup → ∀ a ∈ l, ∀ b ∈ l, ∀ v, f a = some v → f b = some v → a = b
  | [], _, a, ha, _, _, _, _, _ => absurd ha List.not_mem_nil
  | x :: xs, hn, a, ha, b, hb, v, hfa, hfb => by
    cases hx : f x with
    | none =>
      rw [List.filterMap_cons, hx] at hn
      rcases List.mem_cons.1 ha with rfl | ha
      · rw [hx] at hfa; cases hfa
      rcases List.mem_cons.1 hb with rfl | hb
      · rw [hx] at hfb; cases hfb
      exact eq_of_nodup_filterMap f xs hn a ha b hb v hfa hfb
    | some w =>
      rw [List.filterMap_cons, hx] at hn
      have hn' := List.nodup_cons.1 hn
      rcases List.mem_cons.1 ha with ha' | ha' <;> rcases List.mem_cons.1 hb with hb' | hb'
      · rw [ha', hb']
      · exfalso; rw [ha', hx] at hfa; cases hfa
        exact hn'.1 (List.mem_filterMap.2 ⟨b, hb', hfb⟩)
      · exfalso; rw [hb', hx] at hfb; cases hfb
        exact hn'.1 (List.mem_filterMap.2 ⟨a, ha', hfa⟩)
      · exact eq_of_nodup_filterMap f xs hn'.2 a ha' b hb' v hfa hfb

theorem eq_of_nodup_map {α β : Type} (f : α → β) (l : List α) (hn : (l.map f).Nodup) (a b : α) (ha : a ∈ l)
    (hb : b ∈ l) (he : f a = f b) : a = b := by
  have e : l.filterMap (fun x => some (f x)) = l.map f := by
    induction l with
    | nil => rfl
    | cons x xs ih => simp [List.filterMap_cons, ih]
  exact eq_of_nodup_filterMap (fun x => some (f x)) l (by rw [e]; exact hn) a ha b hb (f a) rfl (by rw [he])

theorem count_one {α : Type} [DecidableEq α] (a : α) : ∀ l : List α, l.Nodup → a ∈ l → l.count a = 1
  | [], _, h => absurd h List.not_mem_nil
  | x :: xs, hn, h => by
    have hn' := List.nodup_cons.1 hn
    rw [List.count_cons]
    rcases List.mem_cons.1 h with rfl | h
    · simp [List.count_eq_zero_of_not_mem hn'.1]
    · have hx : x ≠ a := fun e => hn'.1 (e ▸ h)
      simp [count_one a xs hn'.2 h, hx]

theorem foldl_ind {α β : Type} (f : β → α → β) (P : β → List α → Prop) (h : ∀ b x xs, P b (x :: xs) → P (f b x) xs) :
    ∀ (l : List α) (b : β), P b l → P (l.foldl f b) []
  | [], _, hb => hb
  | x :: xs, b, hb => foldl_ind f P h xs (f b x) (h b x xs hb)

theorem sum_le_of {α : Type} (f g : α → Nat) : ∀ l : List α, (∀ x ∈ l, f x ≤ g x) → (l.map f).sum ≤ (l.map g).sum
  | [], _ => Nat.le_refl _
  | x :: xs, h => by
    simp only [List.map_cons, List.sum_cons]
    exact Nat.add_le_add (h x List.mem_cons_self) (sum_le_of f g xs fun y hy => h y (List.mem_cons_of_mem _ hy))

theorem sum_zero {α : Type} (f : α → Nat) : ∀ l : List α, (∀ x ∈ l, f x = 0) → (l.map f).sum = 0
  | [], _ => rfl
  | x :: xs, h => by
    simp only [List.map_cons, List.sum_cons, h x List.mem_cons_self, sum_zero f xs fun y hy => h y (List.mem_cons_of_mem _ hy)]

theorem nodup_fresh {A B : List Nat} {n : Nat} (h : (A ++ B).Nodup) (hb : ∀ x ∈ A ++ B, x < n) :
    (A ++ n :: B).Nodup := by
  refine (List.perm_middle.symm).nodup (List.nodup_cons.2 ⟨fun hm => ?_, h⟩)
  exact Nat.lt_irrefl n (hb n hm)

theorem insertReq_perm (q : Req) : ∀ l, (insertReq q l).Perm (q :: l)
  | [] => List.Perm.refl _
  | p :: ps => by
    unfold insertReq
    split
    · exact List.Perm.refl _
    · exact ((insertReq_perm q ps).cons p).trans (List.Perm.swap q p ps)

theorem readyId_iff (rs : List Rsrc) (rid : Nat) : readyId rs rid = true ↔ ∃ r ∈ rs, r.id = rid ∧ r.phase = .ready := by
  simp [readyId, List.any_eq_true]

theorem svcOk_svc {rs : List Rsrc} {l : Lease} (hk : l.kind = .svc) (h : svcOk rs l = true) :
    readyId rs l.rid = true := by
  unfold svcOk at h; rw [hk] at h; revert h; cases readyId rs l.rid <;> decide

theorem vec_zero (d : Res) : ({} : Vec).get d = 0 := by cases d <;> rfl

/-! ## The invariant -/

/-- The lease ids, then the queued request ids. -/
def State.ids (s : State) : List Nat := s.leases.map (·.id) ++ s.pending.map (·.id)

/-- The state facts every step keeps: unique resource ids and groups, unique lease and request ids below `next`,
requests within `maxWait` with a hold in `[1, hmax]`, leases alive with a capped renew count, and service leases
of cost zero on ready resources. -/
structure Wf (c : Cfg) (s : State) : Prop where
  rids : (s.res.map (·.id)).Nodup
  procs : (s.res.filterMap (·.proc)).Nodup
  ids : s.ids.Nodup
  below : ∀ n ∈ s.ids, n < s.next
  preq : ∀ q ∈ s.pending, q.deadline ≤ q.born + c.maxWait ∧ 1 ≤ q.hold ∧ q.hold ≤ hmax c
  live : ∀ l ∈ s.leases, s.now < l.deadline ∧ l.granted ≤ s.now ∧ l.deadline ≤ l.granted + (l.renews + 1) * hmax c
    ∧ l.renews ≤ c.renewCap
  svc : ∀ l ∈ s.leases, l.kind = .svc → l.cost = {} ∧ ∃ r ∈ s.res, r.id = l.rid ∧ r.phase = .ready

/-- The invariant: `Wf` and every queued request before its deadline. -/
def Inv (c : Cfg) (s : State) : Prop := Wf c s ∧ ∀ q ∈ s.pending, s.now < q.deadline

/-- The general preservation rule: resources mapped keeping ids and keeping or forgetting groups, leases filtered,
the queue a sublist, `next` and `now` not decreasing, kept leases alive and kept service leases on ready resources. -/
theorem wf_of {c : Cfg} {s s2 : State} (h : Wf c s) (f : Rsrc → Rsrc) (p : Lease → Bool)
    (hres : s2.res = s.res.map f) (hf : ∀ x ∈ s.res, (f x).id = x.id ∧ ((f x).proc = x.proc ∨ (f x).proc = none))
    (hl : s2.leases = s.leases.filter p) (hp : s2.pending.Sublist s.pending) (hn : s.next ≤ s2.next)
    (ht : s.now ≤ s2.now) (hlive : ∀ l ∈ s.leases, p l = true → s2.now < l.deadline)
    (hsvc : ∀ l ∈ s.leases, p l = true → l.kind = .svc → ∃ r ∈ s2.res, r.id = l.rid ∧ r.phase = .ready) :
    Wf c s2 := by
  have hsub : s2.ids.Sublist s.ids := by
    simp only [State.ids, hl]
    exact (List.filter_sublist.map _).append (hp.map _)
  refine ⟨?_, ?_, hsub.nodup h.ids, fun n hn' => Nat.lt_of_lt_of_le (h.below n (hsub.subset hn')) hn,
    fun q hq => h.preq q (hp.subset hq), ?_, ?_⟩
  · have : (s.res.map f).map (·.id) = s.res.map (·.id) := by
      rw [List.map_map]; exact List.map_congr_left fun x hx => (hf x hx).1
    rw [hres, this]; exact h.rids
  · rw [hres, List.filterMap_map]
    exact (filterMap_sub _ _ _ fun x hx => (hf x hx).2).nodup h.procs
  · intro l hl'
    rw [hl] at hl'
    have hm := List.mem_filter.1 hl'
    obtain ⟨_, h2, h3, h4⟩ := h.live l hm.1
    exact ⟨hlive l hm.1 hm.2, Nat.le_trans h2 ht, h3, h4⟩
  · intro l hl' hk
    rw [hl] at hl'
    have hm := List.mem_filter.1 hl'
    exact ⟨(h.svc l hm.1 hk).1, hsvc l hm.1 hm.2 hk⟩

/-- Resources unchanged, leases and queue the same, `next` not decreasing. -/
theorem wf_same {c : Cfg} {s s2 : State} (h : Wf c s) (hr : s2.res = s.res) (hl : s2.leases = s.leases)
    (hp : s2.pending = s.pending) (hn : s.next ≤ s2.next) (ht : s2.now = s.now) : Wf c s2 := by
  refine wf_of h id (fun _ => true) (by rw [hr, List.map_id]) (fun _ _ => ⟨rfl, Or.inl rfl⟩)
    (by rw [hl]; exact (List.filter_eq_self.2 fun _ _ => rfl).symm) (by rw [hp]; exact List.Sublist.refl _) hn (by rw [ht]; exact Nat.le_refl _)
    (fun l hl' _ => by rw [ht]; exact (h.live l hl').1) (fun l hl' _ hk => by rw [hr]; exact (h.svc l hl' hk).2)

/-! ## Per-resource transitions -/

/-- Same id, kind, cost and group. -/
def Same (x y : Rsrc) : Prop := y.id = x.id ∧ y.kind = x.kind ∧ y.cost = x.cost ∧ y.proc = x.proc

theorem Same.refl (x : Rsrc) : Same x x := ⟨rfl, rfl, rfl, rfl⟩

theorem Same.trans {x y z : Rsrc} (h1 : Same x y) (h2 : Same y z) : Same x z :=
  ⟨h2.1.trans h1.1, h2.2.1.trans h1.2.1, h2.2.2.1.trans h1.2.2.1, h2.2.2.2.trans h1.2.2.2⟩

theorem crash_same (c : Cfg) (now : Nat) (fail : Bool) (x : Rsrc) : Same x (crash c now fail x) := Same.refl x

theorem exits_same (c : Cfg) (now : Nat) (x : Rsrc) : Same x (exits c now x) := by
  unfold exits; split <;> exact Same.refl x

theorem ageRec_same (c : Cfg) (now : Nat) (x : Rsrc) : Same x (ageRec c now x).1 := by
  unfold ageRec; split
  · split <;> exact Same.refl x
  · split <;> exact Same.refl x
  · split
    · exact crash_same c now true x
    · exact Same.refl x
  · exact Same.refl x

theorem goneRec_same (c : Cfg) (now : Nat) (rows : List Fw.Ops.Reap.Row) (x : Rsrc) : Same x (goneRec c now rows x) := by
  unfold goneRec; split
  · split
    · exact exits_same c now x
    · exact Same.refl x
  · exact Same.refl x

theorem auditRec_same (rows : List Fw.Ops.Reap.Row) (x : Rsrc) :
    (auditRec rows x).1.id = x.id ∧ ((auditRec rows x).1.proc = x.proc ∨ (auditRec rows x).1.proc = none) := by
  unfold auditRec; split
  · split
    · exact ⟨rfl, Or.inl rfl⟩
    · dsimp only
      split
      · exact ⟨rfl, Or.inr rfl⟩
      · exact ⟨rfl, Or.inl rfl⟩
  · exact ⟨rfl, Or.inl rfl⟩

theorem tickRec_same (c : Cfg) (ls : List Lease) (now : Nat) (smp : Sample) (x : Rsrc) :
    (tickRec c ls now smp x).1.id = x.id ∧ ((tickRec c ls now smp x).1.proc = x.proc ∨ (tickRec c ls now smp x).1.proc = none) := by
  simp only [tickRec]
  generalize hx0 : ({ x with foot := footOf smp x.proc, lastUse := _ } : Rsrc) = x0
  have h0 : Same x x0 := by rw [← hx0]; exact Same.refl x
  have h1 := h0.trans ((ageRec_same c now x0).trans (goneRec_same c now smp.rows _))
  have h2 := auditRec_same smp.rows (goneRec c now smp.rows (ageRec c now x0).1)
  rw [h2.1, h1.1, ← h1.2.2.2]
  exact ⟨rfl, h2.2⟩

theorem stopRec_same (now : Nat) (ids : List Nat) (x : Rsrc) : Same x (stopRec now ids x).1 := by
  unfold stopRec; split
  · split <;> exact Same.refl x
  · exact Same.refl x

/-! ## Each stage keeps `Wf` -/

theorem wf_next {c : Cfg} {s : State} (h : Wf c s) : Wf c { s with next := s.next + 1 } :=
  wf_same h rfl rfl rfl (Nat.le_succ _) rfl

theorem wf_addLease {c : Cfg} {s : State} (l : Lease) (h : Wf c s) (hid : l.id = s.next) (h1 : s.now < l.deadline)
    (h2 : l.granted ≤ s.now) (h3 : l.deadline ≤ l.granted + (l.renews + 1) * hmax c) (h4 : l.renews ≤ c.renewCap)
    (h5 : l.kind = .svc → l.cost = {} ∧ ∃ r ∈ s.res, r.id = l.rid ∧ r.phase = .ready) :
    Wf c { s with leases := s.leases ++ [l], next := s.next + 1 } := by
  have hids : State.ids { s with leases := s.leases ++ [l], next := s.next + 1 }
      = s.leases.map (·.id) ++ l.id :: s.pending.map (·.id) := by
    simp [State.ids]
  refine ⟨h.rids, h.procs, ?_, ?_, h.preq, ?_, ?_⟩
  · rw [hids, hid]; exact nodup_fresh h.ids h.below
  · intro n hn
    rw [hids, hid] at hn
    rcases List.mem_append.1 hn with hn | hn
    · exact Nat.lt_succ_of_lt (h.below n (List.mem_append_left _ hn))
    · rcases List.mem_cons.1 hn with rfl | hn
      · exact Nat.lt_succ_self _
      · exact Nat.lt_succ_of_lt (h.below n (List.mem_append_right _ hn))
  · intro l' hl'
    rcases List.mem_append.1 hl' with hl' | hl'
    · exact h.live l' hl'
    · rw [List.mem_singleton.1 hl']; exact ⟨h1, h2, h3, h4⟩
  · intro l' hl' hk
    rcases List.mem_append.1 hl' with hl' | hl'
    · exact h.svc l' hl' hk
    · rw [List.mem_singleton.1 hl'] at hk ⊢; exact h5 hk

theorem wf_addReq {c : Cfg} {s : State} (q : Req) (ts : List Ticket) (h : Wf c s) (hid : q.id = s.next)
    (h1 : q.deadline ≤ q.born + c.maxWait) (h2 : 1 ≤ q.hold) (h3 : q.hold ≤ hmax c) :
    Wf c { s with pending := insertReq q s.pending, tickets := ts, next := s.next + 1 } := by
  have hp : (State.ids { s with pending := insertReq q s.pending, tickets := ts, next := s.next + 1 }).Perm
      (s.leases.map (·.id) ++ q.id :: s.pending.map (·.id)) := by
    simp only [State.ids]
    exact List.Perm.append_left _ (by simpa using (insertReq_perm q s.pending).map (·.id))
  refine ⟨h.rids, h.procs, ?_, ?_, ?_, h.live, h.svc⟩
  · rw [hp.nodup_iff, hid]; exact nodup_fresh h.ids h.below
  · intro n hn
    rw [hp.mem_iff, hid] at hn
    rcases List.mem_append.1 hn with hn | hn
    · exact Nat.lt_succ_of_lt (h.below n (List.mem_append_left _ hn))
    · rcases List.mem_cons.1 hn with rfl | hn
      · exact Nat.lt_succ_self _
      · exact Nat.lt_succ_of_lt (h.below n (List.mem_append_right _ hn))
  · intro q' hq'
    rcases List.mem_cons.1 ((insertReq_perm q s.pending).mem_iff.1 hq') with rfl | hq'
    · exact ⟨h1, h2, h3⟩
    · exact h.preq q' hq'

theorem holdOf_le (c : Cfg) (h : Nat) : 1 ≤ holdOf c h ∧ holdOf c h ≤ hmax c := by
  simp only [holdOf, hmax]; omega

theorem wf_request {c : Cfg} {s : State} (o : Nat) (a : Ask) (h : Wf c s) : Wf c (request c s o a).1 := by
  unfold request
  dsimp only
  split
  · split
    · split
      · exact wf_next h
      · rename_i pl hpl _
        have hm := List.mem_of_find?_eq_some hpl
        have hb := holdOf_le c a.hold
        obtain ⟨l1, l2, l3, _⟩ := h.live pl hm
        refine wf_addLease _ h rfl ?_ (Nat.le_refl _) ?_ (Nat.zero_le _) (fun hk => by cases hk)
        · simp only; omega
        · simp only; omega
    · exact wf_next h
  · have hb := holdOf_le c a.hold
    exact wf_addReq _ _ h rfl (by simp only; omega) hb.1 hb.2

theorem ready_map {l : List Rsrc} {f : Rsrc → Rsrc} {rid : Nat}
    (hf : ∀ x ∈ l, x.phase = .ready → (f x).id = x.id ∧ (f x).phase = .ready)
    (h : ∃ r ∈ l, r.id = rid ∧ r.phase = .ready) : ∃ r ∈ l.map f, r.id = rid ∧ r.phase = .ready := by
  obtain ⟨r, hr, h1, h2⟩ := h
  exact ⟨f r, List.mem_map_of_mem hr, by rw [(hf r hr h2).1, h1], (hf r hr h2).2⟩

theorem wf_release {c : Cfg} {s : State} (o lid : Nat) (h : Wf c s) : Wf c (release s o lid).1 := by
  unfold release
  dsimp only
  split
  · rename_i l _
    refine wf_of h (fun x => if l.kind == .svc && x.id == l.rid then { x with lastUse := s.now } else x)
      (fun l' => l'.id != lid) rfl (fun x _ => ?_) rfl (List.Sublist.refl _) (Nat.le_succ _) (Nat.le_refl _)
      (fun l' hl' _ => (h.live l' hl').1) (fun l' hl' _ hk => ready_map (fun x _ hx => ?_) (h.svc l' hl' hk).2)
    · split <;> exact ⟨rfl, Or.inl rfl⟩
    · split <;> exact ⟨rfl, hx⟩
  · exact wf_next h

theorem wf_renew {c : Cfg} {s : State} (o lid : Nat) (h : Wf c s) : Wf c (renew c s o lid).1 := by
  unfold renew
  dsimp only
  split
  · rename_i l hl
    split
    · rename_i hcap
      have hm := List.mem_of_find?_eq_some hl
      have hlid : l.id = lid := by
        have := List.find?_some hl; simp only [Bool.and_eq_true, beq_iff_eq] at this; exact this.1
      have hlids : (s.leases.map (·.id)).Nodup := (List.nodup_append.1 h.ids).1
      let d := max l.deadline (s.now + hmax c)
      let g := fun l' : Lease => if l'.id == lid then { l' with deadline := d, renews := l'.renews + 1 } else l'
      have hgid : s.leases.map (fun l' => (g l').id) = s.leases.map (·.id) :=
        List.map_congr_left fun l' _ => by simp only [g]; split <;> rfl
      have hids : State.ids { s with leases := s.leases.map g, next := s.next + 1 } = s.ids := by
        simp only [State.ids, List.map_map]; rw [← hgid]; rfl
      refine ⟨h.rids, h.procs, ?_, ?_, h.preq, ?_, ?_⟩
      · show (State.ids { s with leases := s.leases.map g, next := s.next + 1 }).Nodup
        rw [hids]; exact h.ids
      · intro n hn
        have hn' : n ∈ (State.ids { s with leases := s.leases.map g, next := s.next + 1 }) := hn
        rw [hids] at hn'
        exact Nat.lt_succ_of_lt (h.below n hn')
      · intro l' hl'
        obtain ⟨l0, hl0, rfl⟩ := List.mem_map.1 hl'
        simp only [g]
        split
        · rename_i he
          have : l0 = l := eq_of_nodup_map (·.id) _ hlids l0 l hl0 hm (by simp only [beq_iff_eq] at he; rw [he, hlid])
          subst this
          obtain ⟨a1, a2, a3, a4⟩ := h.live l0 hl0
          simp only [hmax] at *
          refine ⟨by omega, a2, ?_, by omega⟩
          simp only [Nat.add_mul, Nat.one_mul] at *
          omega
        · exact h.live l0 hl0
      · intro l' hl' hk
        obtain ⟨l0, hl0, rfl⟩ := List.mem_map.1 hl'
        simp only [g] at hk ⊢
        by_cases he : (l0.id == lid) = true
        · simp only [he, if_true] at hk ⊢; exact h.svc l0 hl0 hk
        · simp only [he, if_false] at hk ⊢; exact h.svc l0 hl0 hk
    · exact wf_next h
  · exact wf_next h

theorem ite_field {α : Type} (P : Rsrc → α) (b : Prop) [Decidable b] (x y : Rsrc) (h : P y = P x) :
    P (if b then y else x) = P x := by
  split
  · exact h
  · rfl

/-- Record a group on the resource with an id. -/
def setProc (rid : Nat) (i : Ident) (x : Rsrc) : Rsrc :=
  if x.id == rid then { x with proc := some i, adopted := false } else x

theorem mem_procs_set {rid : Nat} {i j : Ident} {xs : List Rsrc}
    (h : j ∈ (xs.map (setProc rid i)).filterMap (·.proc)) : j = i ∨ j ∈ xs.filterMap (·.proc) := by
  obtain ⟨y, hy, hj⟩ := List.mem_filterMap.1 h
  obtain ⟨z, hz, rfl⟩ := List.mem_map.1 hy
  unfold setProc at hj
  split at hj
  · simp only [Option.some.injEq] at hj; exact Or.inl hj.symm
  · exact Or.inr (List.mem_filterMap.2 ⟨z, hz, hj⟩)

theorem procs_set (rid : Nat) (i : Ident) : ∀ l : List Rsrc, (l.map (·.id)).Nodup → (l.filterMap (·.proc)).Nodup →
    (∀ x ∈ l, x.proc ≠ some i) → (∀ x ∈ l, x.id = rid → x.proc = none) →
    ((l.map (setProc rid i)).filterMap (·.proc)).Nodup
  | [], _, _, _, _ => List.nodup_nil
  | x :: xs, hid, hp, hi, hr => by
    rw [List.map_cons, List.nodup_cons] at hid
    have hi' : ∀ y ∈ xs, y.proc ≠ some i := fun y hy => hi y (List.mem_cons_of_mem _ hy)
    have hr' : ∀ y ∈ xs, y.id = rid → y.proc = none := fun y hy => hr y (List.mem_cons_of_mem _ hy)
    rw [List.map_cons, List.filterMap_cons]
    by_cases hx : x.id = rid
    · have hxp := hr x List.mem_cons_self hx
      rw [List.filterMap_cons, hxp] at hp
      have htail : xs.map (setProc rid i) = xs := by
        conv => rhs; rw [← List.map_id xs]
        refine List.map_congr_left fun y hy => ?_
        have : y.id ≠ rid := fun e => hid.1 (hx ▸ e ▸ List.mem_map_of_mem hy)
        simp [setProc, this]
      have hs : setProc rid i x = { x with proc := some i, adopted := false } := by simp [setProc, hx]
      rw [hs, htail]
      refine List.nodup_cons.2 ⟨fun hm => ?_, hp⟩
      obtain ⟨y, hy, hj⟩ := List.mem_filterMap.1 hm
      exact hi' y hy hj
    · have hs : setProc rid i x = x := by simp [setProc, hx]
      rw [hs]
      have ih := procs_set rid i xs hid.2 (by
        rw [List.filterMap_cons] at hp; split at hp
        · exact hp
        · exact (List.nodup_cons.1 hp).2) hi' hr'
      cases hxp : x.proc with
      | none => exact ih
      | some j =>
        rw [List.filterMap_cons, hxp] at hp
        refine List.nodup_cons.2 ⟨fun hm => ?_, ih⟩
        rcases mem_procs_set hm with e | e
        · exact hi x List.mem_cons_self (by rw [hxp, e])
        · exact (List.nodup_cons.1 hp).1 e

theorem wf_spawned {c : Cfg} {s : State} (rid : Nat) (i : Option Ident) (h : Wf c s) :
    Wf c (spawned c s rid i).1 := by
  unfold spawned
  split
  · refine wf_of h _ (fun _ => true) rfl (fun x _ => ?_) (List.filter_eq_self.2 fun _ _ => rfl).symm
      (List.Sublist.refl _) (Nat.le_refl _) (Nat.le_refl _) (fun l hl _ => (h.live l hl).1)
      (fun l hl _ hk => ready_map (fun x _ hx => ?_) (h.svc l hl hk).2)
    · exact ⟨ite_field (·.id) _ _ _ rfl, Or.inl (ite_field (·.proc) _ _ _ rfl)⟩
    · simp [hx]
  · rename_i j
    split
    · exact h
    · split
      · rename_i hno hyes
        have hmap : (fun x : Rsrc => if x.id == rid then { x with proc := some j, adopted := false } else x)
            = setProc rid j := rfl
        refine ⟨?_, ?_, h.ids, h.below, h.preq, h.live, ?_⟩
        · dsimp only
          rw [List.map_map]
          have : (fun x : Rsrc => x.id) ∘ (fun x : Rsrc => if x.id == rid then { x with proc := some j, adopted := false } else x)
              = fun x => x.id := by funext x; simp only [Function.comp]; split <;> rfl
          rw [this]; exact h.rids
        · dsimp only
          rw [hmap]
          refine procs_set rid j s.res h.rids h.procs (fun x hx e => hno (List.any_eq_true.2 ⟨x, hx, by simp [e]⟩))
            (fun x hx e => ?_)
          obtain ⟨y, hy, hc⟩ := List.any_eq_true.1 hyes
          simp only [Bool.and_eq_true, beq_iff_eq, Option.isNone_iff_eq_none] at hc
          have : x = y := eq_of_nodup_map (·.id) _ h.rids x y hx hy (by rw [e, hc.1.1])
          rw [this]; exact hc.1.2
        · intro l hl hk
          refine ⟨(h.svc l hl hk).1, ready_map (fun x _ hx => ?_) (h.svc l hl hk).2⟩
          exact ⟨ite_field (·.id) _ _ _ rfl, by split <;> exact hx⟩
      · exact h

theorem wf_readyEv {c : Cfg} {s : State} (rid : Nat) (h : Wf c s) : Wf c (readyEv s rid) := by
  unfold readyEv
  refine wf_of h _ (fun _ => true) rfl (fun x _ => ?_) (List.filter_eq_self.2 fun _ _ => rfl).symm
    (List.Sublist.refl _) (Nat.le_refl _) (Nat.le_refl _) (fun l hl _ => (h.live l hl).1)
    (fun l hl _ hk => ready_map (fun x _ hx => ?_) (h.svc l hl hk).2)
  · exact ⟨ite_field (·.id) _ _ _ rfl, Or.inl (ite_field (·.proc) _ _ _ rfl)⟩
  · simp [hx]

theorem wf_childExit {c : Cfg} {s : State} (i : Ident) (h : Wf c s) : Wf c (childExit c s i).1 := by
  unfold childExit cut
  dsimp only
  refine wf_of h (fun x => if x.proc == some i then exits c s.now x else x) _ rfl (fun x _ => ?_) rfl
    (List.Sublist.refl _) (Nat.le_refl _) (Nat.le_refl _) (fun l hl _ => (h.live l hl).1) (fun l _ hp hk => ?_)
  · split
    · have := exits_same c s.now x; exact ⟨this.1, Or.inl this.2.2.2⟩
    · exact ⟨rfl, Or.inl rfl⟩
  · exact (readyId_iff _ _).1 (svcOk_svc hk hp)

theorem wf_gone {c : Cfg} {s : State} (o : Nat) (h : Wf c s) : Wf c (gone s o) :=
  wf_of h id _ (List.map_id _).symm (fun _ _ => ⟨rfl, Or.inl rfl⟩) rfl List.filter_sublist (Nat.le_refl _)
    (Nat.le_refl _) (fun l hl _ => (h.live l hl).1) (fun l hl _ hk => (h.svc l hl hk).2)

theorem wf_observe {c : Cfg} {s : State} (now : Nat) (smp : Sample) (h : Wf c s) : Wf c (observe c s now smp).1 := by
  unfold observe cut mapRes
  dsimp only
  refine wf_of h _ _ rfl (fun x _ => tickRec_same c s.leases _ smp x) rfl List.filter_sublist (Nat.le_refl _)
    (Nat.le_max_left _ _) (fun l _ hp => ?_) (fun l _ hp hk => ?_)
  · simp only [Bool.and_eq_true, decide_eq_true_eq] at hp; exact hp.1.1
  · simp only [Bool.and_eq_true] at hp; exact (readyId_iff _ _).1 (svcOk_svc hk hp.2)

theorem mem_insRank {c : Cfg} {x y : Rsrc} : ∀ {l : List Rsrc}, x ∈ insRank c y l → x = y ∨ x ∈ l
  | [], h => Or.inl (List.mem_singleton.1 h)
  | z :: zs, h => by
    unfold insRank at h
    split at h
    · exact List.mem_cons.1 h
    · rcases List.mem_cons.1 h with rfl | h
      · exact Or.inr List.mem_cons_self
      · rcases mem_insRank h with e | e
        · exact Or.inl e
        · exact Or.inr (List.mem_cons_of_mem _ e)

theorem mem_foldr_insRank {c : Cfg} {x : Rsrc} : ∀ l : List Rsrc, x ∈ l.foldr (insRank c) [] → x ∈ l
  | [], h => absurd h List.not_mem_nil
  | y :: ys, h => by
    rw [List.foldr_cons] at h
    rcases mem_insRank h with rfl | h
    · exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (mem_foldr_insRank ys h)

theorem mem_byRank {c : Cfg} {s : State} {x : Rsrc} (h : x ∈ byRank c s) : x ∈ cands c s := mem_foldr_insRank _ h

theorem prefixFor_sub {c : Cfg} {s : State} {add : Res → Nat} {x : Rsrc} (h : x ∈ prefixFor c s add) : x ∈ byRank c s :=
  (List.take_sublist _ _).subset h

theorem shedPick_cands {c : Cfg} {s : State} {x : Rsrc} (h : x ∈ shedPick c s) : x ∈ cands c s := by
  unfold shedPick at h
  split at h
  · exact mem_byRank h
  · exact mem_byRank (prefixFor_sub h)

theorem evictPick_cands {c : Cfg} {s : State} {add : Res → Nat} {x : Rsrc} (h : x ∈ evictPick c s add) :
    x ∈ cands c s := by
  unfold evictPick at h
  split at h
  · exact mem_byRank (prefixFor_sub h)
  · exact absurd h List.not_mem_nil

theorem idle_cands {c : Cfg} {s : State} {x : Rsrc} (h : x ∈ idle c s) : x ∈ cands c s := (List.mem_filter.1 h).1

theorem cands_unleased {c : Cfg} {s : State} {y : Rsrc} (hy : y ∈ cands c s) {l : Lease} (hl : l ∈ s.leases)
    (hk : l.kind = .svc) : l.rid ≠ y.id := by
  intro e
  have := (List.mem_filter.1 hy).2
  simp only [Bool.and_eq_true, List.isEmpty_iff] at this
  have hm : l ∈ leasesOn s y.id := List.mem_filter.2 ⟨hl, by simp [hk, e]⟩
  rw [this.2] at hm
  exact List.not_mem_nil hm

theorem stopRec_keep (now : Nat) (ids : List Nat) (x : Rsrc) (h : ids.contains x.id = false) :
    (stopRec now ids x).1 = x := by
  have hn : ¬ x.id ∈ ids := fun hm => by rw [List.contains_iff_mem.2 hm] at h; cases h
  unfold stopRec; split
  · simp [hn]
  · rfl

theorem wf_stopAll {c : Cfg} {s : State} (xs : List Rsrc) (h : Wf c s) (hx : ∀ x ∈ xs, x ∈ cands c s) :
    Wf c (stopAll s xs).1 := by
  unfold stopAll mapRes
  refine wf_of h _ (fun _ => true) rfl (fun x _ => ?_) (List.filter_eq_self.2 fun _ _ => rfl).symm
    (List.Sublist.refl _) (Nat.le_refl _) (Nat.le_refl _) (fun l hl _ => (h.live l hl).1) (fun l hl _ hk => ?_)
  · have := stopRec_same s.now (xs.map (·.id)) x; exact ⟨this.1, Or.inl this.2.2.2⟩
  · obtain ⟨r, hr, h1, h2⟩ := (h.svc l hl hk).2
    refine ⟨r, List.mem_map.2 ⟨r, hr, stopRec_keep _ _ _ ?_⟩, h1, h2⟩
    cases hc : (xs.map (·.id)).contains r.id
    · rfl
    · obtain ⟨y, hy, e⟩ := List.mem_map.1 (List.contains_iff_mem.1 hc)
      exact absurd (h1.symm.trans e.symm) (cands_unleased (hx y hy) hl hk)

theorem wf_tick {c : Cfg} {s : State} (now : Nat) (smp : Sample) (h : Wf c s) : Wf c (tick c s now smp).1 := by
  unfold tick
  dsimp only
  have h1 := wf_observe now smp h
  have h2 := wf_stopAll _ h1 fun _ hx => idle_cands hx
  unfold shedStage
  split
  · exact wf_stopAll _ h2 fun _ hx => shedPick_cands hx
  · exact h2

/-! ## The pump -/

theorem pumpOne_cases (c : Cfg) (a : Acc) (q : Req) (P : Acc → Prop)
    (hans : ∀ w, (q.deadline ≤ a.st.now ∧ w = .deadline) ∨ (a.st.now < q.deadline ∧ a.st.draining = true ∧ w = .draining)
      ∨ (a.st.now < q.deadline ∧ a.st.draining = false ∧ q.kind = .svc ∧ find a.st q.rid = none ∧ w = .unknown) →
      P (answer a q (.refused w)))
    (hgrant : a.st.now < q.deadline → a.st.draining = false → a.st.shedding = false →
      (q.kind = .job ∧ a.blk = false ∧ fitsB c a.st q.cost.get = true) ∨
      (q.kind = .svc ∧ ∃ r, find a.st q.rid = some r ∧ r.phase = .ready) → P (grant a q))
    (hblock : a.st.now < q.deadline → a.st.draining = false → ∀ add,
      (q.kind = .job ∧ add = q.cost.get) ∨
      (q.kind = .svc ∧ ∃ r, find a.st q.rid = some r ∧ r.phase = .absent ∧ add = charge r) → P (block c a q add))
    (hkeep : a.st.now < q.deadline → a.st.draining = false → q.kind = .svc → P (keepQ a q false))
    (hfail : a.st.now < q.deadline → a.st.draining = false → q.kind = .svc → ∀ r u why, find a.st q.rid = some r →
      r.phase = .failed u why → P (refuseT a q why))
    (hstart : a.st.now < q.deadline → a.st.draining = false → a.st.shedding = false → a.blk = false →
      q.kind = .svc → ∀ r, find a.st q.rid = some r → r.phase = .absent → r.proc = none →
      (recent c a.st.now r.crashes).length < c.maxRestarts → fitsB c a.st (charge r) = true → P (start a q r)) :
    P (pumpOne c a q) := by
  unfold pumpOne
  dsimp only
  split
  · exact hans _ (Or.inl ⟨by assumption, rfl⟩)
  · rename_i hd
    have hd : a.st.now < q.deadline := Nat.lt_of_not_le hd
    split
    · exact hans _ (Or.inr (Or.inl ⟨hd, by assumption, rfl⟩))
    · rename_i hdr
      have hdr : a.st.draining = false := by simpa using hdr
      split
      · rename_i hk
        split
        · rename_i hc
          simp only [Bool.and_eq_true, Bool.not_eq_true'] at hc
          exact hgrant hd hdr hc.1.1 (Or.inl ⟨hk, hc.1.2, hc.2⟩)
        · exact hblock hd hdr _ (Or.inl ⟨hk, rfl⟩)
      · rename_i hk
        split
        · exact hans _ (Or.inr (Or.inr ⟨hd, hdr, hk, by assumption, rfl⟩))
        · rename_i r hr
          split
          · rename_i hp
            split
            · exact hkeep hd hdr hk
            · rename_i hs
              exact hgrant hd hdr (by simpa using hs) (Or.inr ⟨hk, r, hr, hp⟩)
          · rename_i u why hp
            exact hfail hd hdr hk r u why hr hp
          · rename_i hp
            split
            · rename_i hc
              simp only [Bool.and_eq_true, Bool.not_eq_true', Option.isNone_iff_eq_none, decide_eq_true_eq] at hc
              exact hstart hd hdr hc.1.1.1.2 hc.1.1.2 hk r hr hp hc.1.1.1.1 hc.1.2 hc.2
            · exact hblock hd hdr _ (Or.inr ⟨hk, r, hr, hp, rfl⟩)
          · exact hkeep hd hdr hk

/-- The request ids replied to in a command list. -/
def replyIds (cs : List Cmd) : List Nat := cs.filterMap fun
  | .reply n _ => some n
  | _ => none

/-- The leases granted in a command list. -/
def grantsIn (cs : List Cmd) : List Lease := cs.filterMap fun
  | .reply _ (.granted l) => some l
  | _ => none

/-- The resource fields the pump never changes: id, kind, cost, group, adopted flag and crash times. -/
def key (x : Rsrc) : Nat × Nat × Vec × Option Ident × Bool × List Nat := (x.id, x.kind, x.cost, x.proc, x.adopted, x.crashes)

theorem replyIds_append (a b : List Cmd) : replyIds (a ++ b) = replyIds a ++ replyIds b := List.filterMap_append

theorem grantsIn_append (a b : List Cmd) : grantsIn (a ++ b) = grantsIn a ++ grantsIn b := List.filterMap_append

theorem grantIds_sub : ∀ cs : List Cmd, (∀ n l, Cmd.reply n (.granted l) ∈ cs → l.id = n) →
    ((grantsIn cs).map (·.id)).Sublist (replyIds cs)
  | [], _ => List.Sublist.slnil
  | c :: cs, h => by
    have ih := grantIds_sub cs fun n l hm => h n l (List.mem_cons_of_mem _ hm)
    cases c with
    | reply n r =>
      cases r with
      | granted l =>
        have e := h n l List.mem_cons_self
        simp only [grantsIn, replyIds, List.filterMap_cons, List.map_cons] at ih ⊢
        rw [e]; exact ih.cons₂ n
      | _ => simp only [grantsIn, replyIds, List.filterMap_cons] at ih ⊢; exact ih.cons n
    | _ => simpa only [grantsIn, replyIds, List.filterMap_cons] using ih

theorem perm_move (R K T : List Nat) (x : Nat) : (R ++ [x] ++ (K ++ T)).Perm (R ++ (K ++ x :: T)) := by
  rw [List.append_assoc, List.singleton_append]
  exact List.Perm.append_left R List.perm_middle.symm

/-- The pump invariant against the state `s0` it started from, with `rest` still to process. -/
structure PJ (c : Cfg) (s0 : State) (a : Acc) (rest : List Req) : Prop where
  now : a.st.now = s0.now
  next : a.st.next = s0.next
  draining : a.st.draining = s0.draining
  shedding : a.st.shedding = s0.shedding
  obs : a.st.obs = s0.obs
  key : a.st.res.map key = s0.res.map key
  sub : (a.st.pending ++ rest).Sublist s0.pending
  perm : (replyIds a.out ++ (a.st.pending ++ rest).map (·.id)).Perm (s0.pending.map (·.id))
  leases : a.st.leases = s0.leases ++ grantsIn a.out
  gid : ∀ n l, Cmd.reply n (.granted l) ∈ a.out → l.id = n ∧ l.granted = s0.now ∧
    ∃ q ∈ s0.pending, q.id = n ∧ q.owner = l.owner ∧ q.kind = l.kind ∧ q.rid = l.rid
  live : ∀ l ∈ a.st.leases, s0.now < l.deadline ∧ l.granted ≤ s0.now ∧ l.deadline ≤ l.granted + (l.renews + 1) * hmax c
    ∧ l.renews ≤ c.renewCap
  svc : ∀ l ∈ a.st.leases, l.kind = .svc → l.cost = {} ∧ ∃ r ∈ a.st.res, r.id = l.rid ∧ r.phase = .ready
  dl : ∀ q ∈ a.st.pending, s0.now < q.deadline

theorem rids_of_key {xs ys : List Rsrc} (h : xs.map key = ys.map key) : xs.map (·.id) = ys.map (·.id) := by
  have := congrArg (List.map (·.1)) h
  simpa [List.map_map, Function.comp_def, key] using this

theorem procs_of_key {xs ys : List Rsrc} (h : xs.map key = ys.map key) :
    xs.filterMap (·.proc) = ys.filterMap (·.proc) := by
  have := congrArg (List.filterMap (·.2.2.2.1)) h
  simpa [List.filterMap_map, Function.comp_def, key] using this

theorem keepQ_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (b : Bool) (h : PJ c s0 a (q :: rest))
    (hd : s0.now < q.deadline) : PJ c s0 (keepQ a q b) rest := by
  have e : (a.st.pending ++ [q]) ++ rest = a.st.pending ++ q :: rest := by simp
  refine { h with sub := ?_, perm := ?_, dl := ?_ }
  · show ((a.st.pending ++ [q]) ++ rest).Sublist s0.pending
    rw [e]; exact h.sub
  · show (replyIds a.out ++ ((a.st.pending ++ [q]) ++ rest).map (·.id)).Perm _
    rw [e]; exact h.perm
  · intro q' hq'
    rcases List.mem_append.1 hq' with hq' | hq'
    · exact h.dl q' hq'
    · rw [List.mem_singleton.1 hq']; exact hd

theorem answer_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (r : Reply)
    (h : PJ c s0 a (q :: rest)) (hr : ∀ l, r ≠ .granted l) : PJ c s0 (answer a q r) rest := by
  have hg : grantsIn [Cmd.reply q.id r] = [] := by
    cases r with
    | granted l => exact absurd rfl (hr l)
    | _ => rfl
  refine { h with sub := ?_, perm := ?_, leases := ?_, gid := ?_ }
  · show (a.st.pending ++ rest).Sublist s0.pending
    exact (List.Sublist.append_left (List.sublist_cons_self q rest) a.st.pending).trans h.sub
  · show (replyIds (a.out ++ [.reply q.id r]) ++ (a.st.pending ++ rest).map (·.id)).Perm _
    have e1 : replyIds [Cmd.reply q.id r] = [q.id] := rfl
    rw [replyIds_append, e1, List.map_append]
    refine (perm_move _ _ _ _).trans ?_
    simpa using h.perm
  · show a.st.leases = s0.leases ++ grantsIn (a.out ++ [.reply q.id r])
    rw [grantsIn_append, hg, List.append_nil]; exact h.leases
  · intro n l hm
    rcases List.mem_append.1 hm with hm | hm
    · exact h.gid n l hm
    · simp only [List.mem_singleton, Cmd.reply.injEq] at hm; exact absurd hm.2.symm (hr l)

end Fw.Sup
