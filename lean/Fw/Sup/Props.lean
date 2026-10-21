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

theorem refuseT_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (why : Why)
    (h : PJ c s0 a (q :: rest)) : PJ c s0 (refuseT a q why) rest :=
  answer_pj (a := { a with st := { a.st with tickets := a.st.tickets ++ [⟨q.owner, q.rid, q.age⟩] } })
    (.refused why) ⟨h.now, h.next, h.draining, h.shedding, h.obs, h.key, h.sub, h.perm, h.leases, h.gid, h.live, h.svc,
      h.dl⟩ fun _ e => Reply.noConfusion e

theorem noReply_nil : ∀ cs : List Cmd, (∀ x ∈ cs, ∀ n r, x ≠ .reply n r) → replyIds cs = [] ∧ grantsIn cs = []
  | [], _ => ⟨rfl, rfl⟩
  | x :: cs, h => by
    have ih := noReply_nil cs fun y hy => h y (List.mem_cons_of_mem _ hy)
    cases x with
    | reply n r => exact absurd rfl (h _ List.mem_cons_self n r)
    | _ => exact ih

theorem stopAll_sig {s : State} {xs : List Rsrc} {x : Cmd} (hx : x ∈ (stopAll s xs).2) :
    ∃ y ∈ s.res, ∃ i, y.proc = some i ∧ y.id ∈ xs.map (·.id) ∧ y.phase = .ready ∧ x = .signal (.group i) .term := by
  unfold stopAll mapRes at hx
  obtain ⟨y, hy, hm⟩ := List.mem_flatMap.1 hx
  refine ⟨y, hy, ?_⟩
  unfold stopRec at hm
  split at hm
  · rename_i i hi
    split at hm
    · rename_i hc
      simp only [Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem] at hc
      exact ⟨i, hi, hc.2, hc.1, List.mem_singleton.1 hm⟩
    · exact absurd hm List.not_mem_nil
  · exact absurd hm List.not_mem_nil

theorem stopRec_key (now : Nat) (ids : List Nat) (x : Rsrc) : key (stopRec now ids x).1 = key x := by
  unfold stopRec; split
  · split <;> rfl
  · rfl

theorem stopRec_ready (now : Nat) (ids : List Nat) (x : Rsrc) (h : (stopRec now ids x).1.phase = .ready) :
    x.phase = .ready := by
  unfold stopRec at h; split at h
  · split at h
    · cases h
    · exact h
  · exact h

theorem stop_pj {c : Cfg} {s0 : State} {a : Acc} {rest : List Req} (xs : List Rsrc) (h : PJ c s0 a rest)
    (hx : ∀ x ∈ xs, x ∈ cands c a.st) :
    PJ c s0 { a with st := (stopAll a.st xs).1, out := a.out ++ (stopAll a.st xs).2 } rest := by
  have hn := noReply_nil (stopAll a.st xs).2 fun y hy n r e => by
    obtain ⟨_, _, _, _, _, _, e'⟩ := stopAll_sig hy
    rw [e'] at e; cases e
  refine { h with key := ?_, perm := ?_, leases := ?_, gid := ?_, svc := ?_ }
  · show (a.st.res.map fun x => (stopRec a.st.now (xs.map (·.id)) x).1).map key = _
    rw [List.map_map, ← h.key]
    exact List.map_congr_left fun x _ => stopRec_key _ _ x
  · show (replyIds (a.out ++ (stopAll a.st xs).2) ++ _).Perm _
    rw [replyIds_append, hn.1, List.append_nil]; exact h.perm
  · show a.st.leases = s0.leases ++ grantsIn (a.out ++ (stopAll a.st xs).2)
    rw [grantsIn_append, hn.2, List.append_nil]; exact h.leases
  · intro n l hm
    rcases List.mem_append.1 hm with hm | hm
    · exact h.gid n l hm
    · obtain ⟨_, _, _, _, _, _, e'⟩ := stopAll_sig hm; cases e'
  · intro l hl hk
    obtain ⟨h0, r, hr, h1, h2⟩ := h.svc l hl hk
    refine ⟨h0, r, List.mem_map.2 ⟨r, hr, stopRec_keep _ _ _ ?_⟩, h1, h2⟩
    cases hc : (xs.map (·.id)).contains r.id
    · rfl
    · obtain ⟨y, hy, e⟩ := List.mem_map.1 (List.contains_iff_mem.1 hc)
      exact absurd (h1.symm.trans e.symm) (cands_unleased (hx y hy) hl hk)

theorem block_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (add : Res → Nat)
    (h : PJ c s0 a (q :: rest)) (hd : s0.now < q.deadline) : PJ c s0 (block c a q add) rest := by
  unfold block
  split
  · exact keepQ_pj true h hd
  · exact keepQ_pj true (stop_pj _ h fun _ hx => evictPick_cands hx) hd

theorem find_mem {s : State} {rid : Nat} {r : Rsrc} (h : find s rid = some r) : r ∈ s.res ∧ r.id = rid := by
  unfold find at h
  exact ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

theorem grant_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (h : PJ c s0 a (q :: rest))
    (hw : Wf c s0) (hs : q.kind = .svc → ∃ r, find a.st q.rid = some r ∧ r.phase = .ready) :
    PJ c s0 (grant a q) rest := by
  have hq : q ∈ s0.pending := h.sub.subset (List.mem_append_right _ List.mem_cons_self)
  have hp := hw.preq q hq
  have hf : ∀ x : Rsrc, key (if (q.kind == .svc && x.id == q.rid) = true then { x with lastUse := a.st.now } else x)
      = key x := fun x => ite_field key _ _ _ rfl
  have hph : ∀ x : Rsrc, (if (q.kind == .svc && x.id == q.rid) = true then { x with lastUse := a.st.now } else x).phase
      = x.phase := fun x => ite_field (·.phase) _ _ _ rfl
  have hid : ∀ x : Rsrc, (if (q.kind == .svc && x.id == q.rid) = true then { x with lastUse := a.st.now } else x).id
      = x.id := fun x => ite_field (·.id) _ _ _ rfl
  have e1 : replyIds [Cmd.reply q.id (.granted (leaseOf q a.st.now (if q.kind == .svc then {} else q.cost)))] = [q.id] :=
    rfl
  refine { h with key := ?_, sub := ?_, perm := ?_, leases := ?_, gid := ?_, live := ?_, svc := ?_ }
  · show (a.st.res.map _).map key = _
    rw [List.map_map, ← h.key]
    exact List.map_congr_left fun x _ => hf x
  · show (a.st.pending ++ rest).Sublist s0.pending
    exact (List.Sublist.append_left (List.sublist_cons_self q rest) a.st.pending).trans h.sub
  · show (replyIds (a.out ++ [_]) ++ (a.st.pending ++ rest).map (·.id)).Perm _
    rw [replyIds_append, e1, List.map_append]
    refine (perm_move _ _ _ _).trans ?_
    simpa using h.perm
  · show a.st.leases ++ [_] = s0.leases ++ grantsIn (a.out ++ [_])
    rw [grantsIn_append, h.leases, List.append_assoc]; rfl
  · intro n l hm
    rcases List.mem_append.1 hm with hm | hm
    · exact h.gid n l hm
    · simp only [List.mem_singleton, Cmd.reply.injEq, Reply.granted.injEq] at hm
      obtain ⟨e1, e2⟩ := hm
      subst e2; subst e1
      exact ⟨rfl, h.now, q, hq, rfl, rfl, rfl, rfl⟩
  · intro l hl
    rcases List.mem_append.1 hl with hl | hl
    · exact h.live l hl
    · rw [List.mem_singleton.1 hl]
      simp only [leaseOf, h.now]
      refine ⟨by omega, Nat.le_refl _, by omega, Nat.zero_le _⟩
  · intro l hl hk
    rcases List.mem_append.1 hl with hl | hl
    · obtain ⟨h0, r, hr, h1, h2⟩ := h.svc l hl hk
      exact ⟨h0, _, List.mem_map.2 ⟨r, hr, rfl⟩, (hid r).trans h1, (hph r).trans h2⟩
    · rw [List.mem_singleton.1 hl] at hk ⊢
      have hk' : q.kind = .svc := hk
      obtain ⟨r, hr, h2⟩ := hs hk'
      obtain ⟨hm, h1⟩ := find_mem hr
      refine ⟨by simp [leaseOf, hk'], _, List.mem_map.2 ⟨r, hm, rfl⟩, (hid r).trans h1, (hph r).trans h2⟩

theorem start_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} {r : Rsrc}
    (h : PJ c s0 a (q :: rest)) (hw : Wf c s0) (hd : s0.now < q.deadline) (hr : find a.st q.rid = some r)
    (hp : r.phase = .absent) : PJ c s0 (start a q r) rest := by
  obtain ⟨hm, _⟩ := find_mem hr
  have hnd : (a.st.res.map (·.id)).Nodup := by rw [rids_of_key h.key]; exact hw.rids
  have hn := noReply_nil [Cmd.spawn r.id r.kind] fun y hy n r' e => by
    rw [List.mem_singleton.1 hy] at e; cases e
  refine keepQ_pj false { h with key := ?_, perm := ?_, leases := ?_, gid := ?_, svc := ?_ } hd
  · show (a.st.res.map _).map key = _
    rw [List.map_map, ← h.key]
    exact List.map_congr_left fun x _ => ite_field key _ _ _ rfl
  · show (replyIds (a.out ++ [_]) ++ _).Perm _
    rw [replyIds_append, hn.1, List.append_nil]; exact h.perm
  · show a.st.leases = s0.leases ++ grantsIn (a.out ++ [_])
    rw [grantsIn_append, hn.2, List.append_nil]; exact h.leases
  · intro n l hm'
    rcases List.mem_append.1 hm' with hm' | hm'
    · exact h.gid n l hm'
    · cases List.mem_singleton.1 hm'
  · intro l hl hk
    obtain ⟨h0, r', hr', h1, h2⟩ := h.svc l hl hk
    refine ⟨h0, r', List.mem_map.2 ⟨r', hr', ?_⟩, h1, h2⟩
    have hne : (r'.id == r.id) = false := by
      cases hc : r'.id == r.id
      · rfl
      · have := eq_of_nodup_map (·.id) _ hnd r' r hr' hm (by simpa using hc)
        rw [this, hp] at h2; cases h2
    simp [hne]

theorem pumpOne_pj {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (hw : Wf c s0)
    (h : PJ c s0 a (q :: rest)) : PJ c s0 (pumpOne c a q) rest := by
  have hn : a.st.now = s0.now := h.now
  refine pumpOne_cases c a q (fun a' => PJ c s0 a' rest) (fun w _ => answer_pj _ h fun _ e => Reply.noConfusion e)
    (fun _ _ _ hc => grant_pj h hw fun hk => ?_) (fun hd _ add _ => block_pj add h (hn ▸ hd))
    (fun hd _ _ => keepQ_pj false h (hn ▸ hd)) (fun _ _ _ _ _ why _ _ => refuseT_pj why h)
    (fun hd _ _ _ _ r hr hp _ _ _ => start_pj h hw (hn ▸ hd) hr hp)
  rcases hc with hc | hc
  · rw [hc.1] at hk; cases hk
  · exact hc.2

/-- The pump started from `s0`, as an accumulator. -/
def pumpAcc (c : Cfg) (s0 : State) : Acc := s0.pending.foldl (pumpOne c) ⟨{ s0 with pending := [] }, [], false⟩

theorem pump_eq (c : Cfg) (s0 : State) : pump c s0 = ((pumpAcc c s0).st, (pumpAcc c s0).out) := rfl

/-- The accumulator the pump starts from. -/
def acc0 (s0 : State) : Acc := ⟨{ s0 with pending := [] }, [], false⟩

theorem pj_init {c : Cfg} {s0 : State} (hw : Wf c s0) : PJ c s0 (acc0 s0) s0.pending := by
  refine ⟨rfl, rfl, rfl, rfl, rfl, rfl, by simp [acc0], by simp [replyIds, acc0], by simp [grantsIn, acc0],
    fun _ _ hm => ?_, hw.live, hw.svc, fun _ hq => ?_⟩
  · cases hm
  · cases hq

theorem pump_pj {c : Cfg} {s0 : State} (hw : Wf c s0) : PJ c s0 (pumpAcc c s0) [] :=
  foldl_ind (pumpOne c) (PJ c s0) (fun _ _ _ h => pumpOne_pj hw h) s0.pending _ (pj_init hw)

/-- Induction over the pump: a property of the start accumulator kept by every request step. -/
theorem pump_ind {c : Cfg} {s0 : State} (hw : Wf c s0) (Q : Acc → Prop) (h0 : Q (acc0 s0))
    (hs : ∀ a q rest, PJ c s0 a (q :: rest) → Q a → Q (pumpOne c a q)) : Q (pumpAcc c s0) :=
  (foldl_ind (pumpOne c) (fun a rest => PJ c s0 a rest ∧ Q a) (fun a q rest h => ⟨pumpOne_pj hw h.1, hs a q rest h.1 h.2⟩)
    s0.pending _ ⟨pj_init hw, h0⟩).2

theorem pj_wf {c : Cfg} {s0 : State} {a : Acc} (hw : Wf c s0) (h : PJ c s0 a []) : Wf c a.st := by
  have hsub : a.st.ids.Sublist (s0.leases.map (·.id) ++ (replyIds a.out ++ a.st.pending.map (·.id))) := by
    simp only [State.ids, h.leases, List.map_append, List.append_assoc]
    exact (List.Sublist.refl _).append ((grantIds_sub a.out fun n l hm => (h.gid n l hm).1).append (List.Sublist.refl _))
  have hp : (s0.leases.map (·.id) ++ (replyIds a.out ++ a.st.pending.map (·.id))).Perm s0.ids :=
    List.Perm.append_left _ (by simpa using h.perm)
  have hpend : a.st.pending.Sublist s0.pending := by simpa using h.sub
  refine ⟨by rw [rids_of_key h.key]; exact hw.rids, by rw [procs_of_key h.key]; exact hw.procs,
    hsub.nodup (hp.nodup_iff.2 hw.ids), fun n hn => ?_, fun q hq => hw.preq q (hpend.subset hq), ?_, h.svc⟩
  · rw [h.next]; exact hw.below n (hp.subset (hsub.subset hn))
  · intro l hl
    rw [h.now]; exact h.live l hl

/-- The pump keeps the invariant. -/
theorem pump_inv {c : Cfg} {s : State} (hw : Wf c s) : Inv c (pump c s).1 := by
  have h := pump_pj (c := c) hw
  rw [pump_eq]
  exact ⟨pj_wf hw h, fun q hq => by rw [h.now]; exact h.dl q hq⟩

/-! ## Restart -/

theorem nubRes_nodup : ∀ l : List Rsrc, ((nubRes l).map (·.id)).Nodup
  | [] => List.nodup_nil
  | x :: xs => by
    simp only [nubRes, List.map_cons, List.nodup_cons]
    refine ⟨fun hm => ?_, (List.filter_sublist.map _).nodup (nubRes_nodup xs)⟩
    obtain ⟨y, hy, e⟩ := List.mem_map.1 hm
    have := (List.mem_filter.1 hy).2
    simp [e] at this

theorem nubLease_nodup : ∀ l : List Lease, ((nubLease l).map (·.id)).Nodup
  | [] => List.nodup_nil
  | x :: xs => by
    simp only [nubLease, List.map_cons, List.nodup_cons]
    refine ⟨fun hm => ?_, (List.filter_sublist.map _).nodup (nubLease_nodup xs)⟩
    obtain ⟨y, hy, e⟩ := List.mem_map.1 hm
    have := (List.mem_filter.1 hy).2
    simp [e] at this

theorem nubLease_sub : ∀ l : List Lease, (nubLease l).Sublist l
  | [] => List.Sublist.slnil
  | x :: xs => (List.filter_sublist.trans (nubLease_sub xs)).cons₂ x

theorem adopt_ids (rows : List Fw.Ops.Reap.Row) : ∀ (seen : List Ident) (xs : List Rsrc),
    (adopt rows seen xs).map (·.id) = xs.map (·.id)
  | _, [] => rfl
  | seen, x :: xs => by
    unfold adopt
    split
    · split
      · exact congrArg (x.id :: ·) (adopt_ids rows _ xs)
      · exact congrArg (x.id :: ·) (adopt_ids rows _ xs)
    · exact congrArg (x.id :: ·) (adopt_ids rows _ xs)

theorem adopt_procs (rows : List Fw.Ops.Reap.Row) : ∀ (seen : List Ident) (xs : List Rsrc),
    ((adopt rows seen xs).filterMap (·.proc)).Nodup ∧ ∀ i ∈ (adopt rows seen xs).filterMap (·.proc), i ∉ seen
  | _, [] => ⟨List.nodup_nil, fun _ h => absurd h List.not_mem_nil⟩
  | seen, x :: xs => by
    unfold adopt
    split
    · rename_i i hi
      split
      · rename_i hc
        have hs : i ∉ seen := by
          simp only [Bool.and_eq_true, Bool.not_eq_true'] at hc
          exact fun hm => by rw [List.contains_iff_mem.2 hm] at hc; exact Bool.noConfusion hc.2
        obtain ⟨ih1, ih2⟩ := adopt_procs rows (i :: seen) xs
        have e : (({ x with adopted := true } :: adopt rows (i :: seen) xs).filterMap (·.proc))
            = i :: (adopt rows (i :: seen) xs).filterMap (·.proc) := by simp [hi]
        rw [e]
        refine ⟨List.nodup_cons.2 ⟨fun hm => ih2 i hm List.mem_cons_self, ih1⟩, fun j hj => ?_⟩
        rcases List.mem_cons.1 hj with e | hj
        · rw [e]; exact hs
        · exact fun hm => ih2 j hj (List.mem_cons_of_mem _ hm)
      · exact adopt_procs rows seen xs
    · exact adopt_procs rows seen xs

theorem foldr_max_lt (b : Nat) : ∀ (ls : List Lease), ∀ l ∈ ls, l.id < ls.foldr (fun l n => max n (l.id + 1)) b
  | [], _, h => absurd h List.not_mem_nil
  | x :: xs, l, h => by
    simp only [List.foldr_cons]
    rcases List.mem_cons.1 h with e | h
    · rw [e]; exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) (Nat.le_max_right _ _)
    · exact Nat.lt_of_lt_of_le (foldr_max_lt b xs l h) (Nat.le_max_left _ _)

/-- restart_inv: recovery from any snapshot gives a well-formed state. -/
theorem restart_inv (c : Cfg) (now : Nat) (snap : State) (inp : Fw.Ops.Reap.Input) : Wf c (recover c now snap inp).1 := by
  unfold recover
  dsimp only
  refine ⟨?_, (adopt_procs _ _ _).1, ?_, ?_, fun q hq => absurd hq List.not_mem_nil, ?_, ?_⟩
  · rw [adopt_ids]; exact nubRes_nodup _
  · simp only [State.ids, List.map_nil, List.append_nil]; exact nubLease_nodup _
  · intro n hn
    simp only [State.ids, List.map_nil, List.append_nil] at hn
    obtain ⟨l, hl, e⟩ := List.mem_map.1 hn
    rw [← e]; exact foldr_max_lt _ _ l hl
  · intro l hl
    have := (List.mem_filter.1 ((nubLease_sub _).subset hl)).2
    simp only [validLease, Bool.and_eq_true, decide_eq_true_eq] at this
    exact ⟨this.1.1.1.2, this.1.1.1.1, this.1.1.2, this.1.2⟩
  · intro l hl hk
    have := (List.mem_filter.1 ((nubLease_sub _).subset hl)).2
    simp only [validLease, Bool.and_eq_true, hk] at this
    have h2 := this.2
    simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, reduceCtorEq, false_or] at h2
    exact ⟨h2.2, (readyId_iff _ _).1 h2.1⟩

/-! ## The step -/

theorem wf_pre {c : Cfg} {s : State} (e : Event) (h : Wf c s) : Wf c (pre c s e).1 := by
  cases e with
  | request _ o a => exact wf_request o a h
  | release _ o l => exact wf_release o l h
  | renew _ o l => exact wf_renew o l h
  | op _ _ => exact wf_next h
  | drain _ _ => exact wf_same h rfl rfl rfl (Nat.le_succ _) rfl
  | spawned rid i => exact wf_spawned rid i h
  | ready rid => exact wf_readyEv rid h
  | childExit i => exact wf_childExit i h
  | tick now smp => exact wf_tick now smp h
  | clientGone o => exact wf_gone o h
  | restart now snap inp => exact restart_inv c now snap inp

theorem step_eq {c : Cfg} {s : State} {e : Event} (h : authed c e = true) :
    step c s e = ((pump c (pre c s e).1).1, (pre c s e).2 ++ (pump c (pre c s e).1).2) := by
  simp [step, h, andThen]

/-- step_inv: every step keeps the invariant. -/
theorem step_inv {c : Cfg} {s : State} (e : Event) (h : Inv c s) : Inv c (step c s e).1 := by
  cases ha : authed c e
  · simp only [step, ha]; exact h
  · rw [step_eq ha]; exact pump_inv (wf_pre e h.1)

/-- The start state satisfies the invariant. -/
theorem init_inv (c : Cfg) : Inv c (init c) :=
  ⟨restart_inv c 0 _ _, fun _ hq => absurd hq List.not_mem_nil⟩

/-- Every state a run reaches satisfies the invariant. -/
theorem run_inv {c : Cfg} : ∀ (es : List Event) (s : State), Inv c s → Inv c (run c s es).1 := by
  intro es s h
  unfold run
  suffices ∀ (es : List Event) (a : State × List Cmd), Inv c a.1 →
      Inv c (es.foldl (fun a e => let r := step c a.1 e; (r.1, a.2 ++ r.2)) a).1 from this es _ h
  intro es
  induction es with
  | nil => exact fun _ h => h
  | cons e es ih => exact fun a h => ih _ (step_inv e h)

/-! ## Command shapes -/

/-- Whether a command is neither a reply nor a spawn. -/
def quiet : Cmd → Bool
  | .reply _ _ | .spawn _ _ => false
  | _ => true

#guard quiet .exit && quiet (.probe 1) && !quiet (.spawn 1 2) && !quiet (.reply 3 .op)
#guard replyIds [.reply 3 .op, .exit, .reply 5 .released] == [3, 5]
#guard grantsIn [.reply 3 .op, .exit] == []

theorem killG_sig {p : Option Ident} {x : Cmd} (h : x ∈ killG p) : ∃ i, p = some i ∧ x = .signal (.group i) .kill := by
  cases p with
  | none => cases h
  | some i => exact ⟨i, rfl, List.mem_singleton.1 h⟩

theorem ageRec_sig {c : Cfg} {now : Nat} {y : Rsrc} {x : Cmd} (h : x ∈ (ageRec c now y).2) :
    ∃ i, y.proc = some i ∧ x = .signal (.group i) .kill := by
  unfold ageRec at h
  split at h
  · cases h
  · split at h
    · exact killG_sig h
    · cases h
  · split at h
    · exact killG_sig h
    · cases h
  · cases h

theorem auditRec_sig {rows : List Fw.Ops.Reap.Row} {y : Rsrc} {x : Cmd} (h : x ∈ (auditRec rows y).2) :
    ∃ r ∈ rows, x = .signal (.member r.pid r.start) .kill := by
  unfold auditRec at h
  split at h
  · split at h
    · cases h
    · dsimp only at h
      split at h
      · cases h
      · obtain ⟨r, hr, e⟩ := List.mem_map.1 h
        exact ⟨r, (List.mem_filter.1 hr).1, e.symm⟩
  · cases h

/-- The commands of one resource's tick: KILL to its own group, or KILL to a member row of the sample. -/
theorem tickRec_sig {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {y : Rsrc} {x : Cmd}
    (h : x ∈ (tickRec c ls now smp y).2) :
    (∃ i, y.proc = some i ∧ x = .signal (.group i) .kill) ∨ ∃ r ∈ smp.rows, x = .signal (.member r.pid r.start) .kill := by
  simp only [tickRec] at h
  rcases List.mem_append.1 h with h | h
  · obtain ⟨i, hi, e⟩ := ageRec_sig h
    exact Or.inl ⟨i, hi, e⟩
  · exact Or.inr (auditRec_sig h)

theorem cut_cmd {p : Lease → Bool} {s : State} {x : Cmd} (h : x ∈ (cut p s).2) :
    ∃ l ∈ s.leases, p l = false ∧ x = .revoke l.owner l.id := by
  obtain ⟨l, hl, e⟩ := List.mem_map.1 h
  have := List.mem_filter.1 hl
  exact ⟨l, this.1, by simpa using this.2, e.symm⟩

theorem mem_tickRes {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {s1 : State} {y : Rsrc} {i : Ident}
    (hy : y ∈ (mapRes (tickRec c ls now smp) s1).1.res) (hp : y.proc = some i) : ∃ x ∈ s1.res, x.proc = some i := by
  obtain ⟨x, hx, e⟩ := List.mem_map.1 hy
  have := tickRec_same c ls now smp x
  rw [e, hp] at this
  rcases this.2 with h | h
  · exact ⟨x, hx, h.symm⟩
  · cases h

theorem mem_stopRes {s : State} {xs : List Rsrc} {y : Rsrc} (hy : y ∈ (stopAll s xs).1.res) :
    ∃ x ∈ s.res, Same x y := by
  obtain ⟨x, hx, e⟩ := List.mem_map.1 hy
  exact ⟨x, hx, e ▸ stopRec_same _ _ x⟩

theorem observe_res (c : Cfg) (s : State) (now : Nat) (smp : Sample) :
    (observe c s now smp).1.res = s.res.map fun x => (tickRec c s.leases (max s.now now) smp x).1 := rfl

theorem observe_procs {c : Cfg} {s : State} {now : Nat} {smp : Sample} {y : Rsrc} {i : Ident}
    (hy : y ∈ (observe c s now smp).1.res) (hp : y.proc = some i) : ∃ x ∈ s.res, x.proc = some i := by
  rw [observe_res] at hy
  obtain ⟨x, hx, e⟩ := List.mem_map.1 hy
  have := tickRec_same c s.leases (max s.now now) smp x
  rw [e, hp] at this
  rcases this.2 with h | h
  · exact ⟨x, hx, h.symm⟩
  · cases h

theorem observe_cmds {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Cmd} (h : x ∈ (observe c s now smp).2) :
    (∃ y ∈ s.res, ∃ i, y.proc = some i ∧ x = .signal (.group i) .kill)
    ∨ (∃ r ∈ smp.rows, x = .signal (.member r.pid r.start) .kill) ∨ (∃ l ∈ s.leases, x = .revoke l.owner l.id) := by
  unfold observe at h
  dsimp only at h
  rcases List.mem_append.1 h with h | h
  · obtain ⟨y, hy, hm⟩ := List.mem_flatMap.1 h
    rcases tickRec_sig hm with ⟨i, hi, e⟩ | hr
    · exact Or.inl ⟨y, hy, i, hi, e⟩
    · exact Or.inr (Or.inl hr)
  · obtain ⟨l, hl, _, e⟩ := cut_cmd h
    exact Or.inr (Or.inr ⟨l, hl, e⟩)

theorem stop_procs {s : State} {xs : List Rsrc} {y : Rsrc} {i : Ident} (hy : y ∈ (stopAll s xs).1.res)
    (hp : y.proc = some i) : ∃ x ∈ s.res, x.proc = some i := by
  obtain ⟨x, hx, hs⟩ := mem_stopRes hy
  exact ⟨x, hx, hs.2.2.2.symm.trans hp⟩

theorem shedStage_eq (c : Cfg) (s : State) : shedStage c s = stopAll s (shedPick c s) ∨ shedStage c s = (s, []) := by
  unfold shedStage; split
  · exact Or.inl rfl
  · exact Or.inr rfl

/-- The commands of a tick: a signal to a group recorded in `s`, a KILL to a member row of the sample, a revoke of a
lease of `s`, or the exit. -/
theorem tick_cmds {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Cmd} (h : x ∈ (tick c s now smp).2) :
    (∃ y ∈ s.res, ∃ i g, y.proc = some i ∧ x = .signal (.group i) g)
    ∨ (∃ r ∈ smp.rows, x = .signal (.member r.pid r.start) .kill) ∨ (∃ l ∈ s.leases, x = .revoke l.owner l.id)
    ∨ x = .exit := by
  unfold tick at h
  dsimp only at h
  generalize hb : idleStage c (observe c s now smp).1 = b at h
  generalize hd : shedStage c b.1 = d at h
  rcases List.mem_append.1 h with h | h
  · rcases List.mem_append.1 h with h | h
    · rcases List.mem_append.1 h with h | h
      · rcases observe_cmds h with ⟨y, hy, i, hi, e⟩ | hr | hl
        · exact Or.inl ⟨y, hy, i, .kill, hi, e⟩
        · exact Or.inr (Or.inl hr)
        · exact Or.inr (Or.inr (Or.inl hl))
      · rw [← hb] at h
        obtain ⟨y, hy, i, hi, _, _, e⟩ := stopAll_sig h
        obtain ⟨z, hz, hp⟩ := observe_procs hy hi
        exact Or.inl ⟨z, hz, i, .term, hp, e⟩
    · rw [← hd] at h
      rcases shedStage_eq c b.1 with e | e <;> rw [e] at h
      · obtain ⟨y, hy, i, hi, _, _, e⟩ := stopAll_sig h
        rw [← hb] at hy
        obtain ⟨y', hy', hp'⟩ := stop_procs hy hi
        obtain ⟨z, hz, hp⟩ := observe_procs hy' hp'
        exact Or.inl ⟨z, hz, i, .term, hp, e⟩
      · cases h
  · split at h
    · exact Or.inr (Or.inr (Or.inr (List.mem_singleton.1 h)))
    · cases h

/-- The commands of the stage before the pump: quiet ones, or the event's own reply, and a granted lease there is a
nested job join of cost zero. -/
theorem pre_cmds {c : Cfg} {s : State} {e : Event} {x : Cmd} (h : x ∈ (pre c s e).2) :
    quiet x = true ∨ ∃ r, x = .reply s.next r ∧ ∀ l, r = .granted l → l.kind = .job ∧ l.cost = {} := by
  cases e with
  | request t o a =>
    simp only [pre, request] at h
    split at h
    · split at h
      · split at h
        · exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
        · refine Or.inr ⟨_, List.mem_singleton.1 h, fun l e => ?_⟩
          cases e; exact ⟨rfl, rfl⟩
      · exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
    · cases h
  | release t o l =>
    simp only [pre, release] at h
    split at h <;> exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
  | renew t o l =>
    simp only [pre, renew] at h
    split at h
    · split at h <;> exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
    · exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
  | op t o => exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
  | drain t o => exact Or.inr ⟨_, List.mem_singleton.1 h, fun _ e => Reply.noConfusion e⟩
  | spawned rid i =>
    simp only [pre] at h
    unfold spawned at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h
        · rw [List.mem_singleton.1 h]; exact Or.inl rfl
        · rw [List.mem_singleton.1 h]; exact Or.inl rfl
  | ready rid => cases h
  | childExit i =>
    simp only [pre, childExit] at h
    obtain ⟨_, _, _, e⟩ := cut_cmd h
    rw [e]; exact Or.inl rfl
  | tick now smp =>
    rcases tick_cmds h with ⟨_, _, _, _, _, e⟩ | ⟨_, _, e⟩ | ⟨_, _, e⟩ | e <;> (rw [e]; exact Or.inl rfl)
  | clientGone o => cases h
  | restart now snap inp =>
    simp only [pre, recover] at h
    rcases List.mem_append.1 h with h | h
    · obtain ⟨_, _, e⟩ := List.mem_map.1 h
      rw [← e]; exact Or.inl rfl
    · obtain ⟨_, _, e⟩ := List.mem_map.1 h
      rw [← e]; exact Or.inl rfl

/-! ## What the pump does to resources and which commands it sends -/

/-- One pump change of a resource, keys kept: none, an absent resource without a group starts at `now`, or a ready
one stops with TERM at `now`. -/
def Moved (now : Nat) (x y : Rsrc) : Prop :=
  key y = key x ∧ (y.phase = x.phase ∨ (x.phase = .absent ∧ x.proc = none ∧ y.phase = .starting now)
    ∨ (x.phase = .ready ∧ y.phase = .stopping now .term))

theorem key_proc {x y : Rsrc} (h : key y = key x) : y.proc = x.proc := congrArg (·.2.2.2.1) h

theorem key_id {x y : Rsrc} (h : key y = key x) : y.id = x.id := congrArg (·.1) h

theorem key_kind {x y : Rsrc} (h : key y = key x) : y.kind = x.kind := congrArg (·.2.1) h

theorem Moved.refl (now : Nat) (x : Rsrc) : Moved now x x := ⟨rfl, Or.inl rfl⟩

theorem Moved.trans {now : Nat} {x y z : Rsrc} (h1 : Moved now x y) (h2 : Moved now y z) : Moved now x z := by
  refine ⟨h2.1.trans h1.1, ?_⟩
  rcases h2.2 with e2 | ⟨a2, n2, e2⟩ | ⟨a2, e2⟩
  · rcases h1.2 with e1 | ⟨a1, n1, e1⟩ | ⟨a1, e1⟩
    · exact Or.inl (e2.trans e1)
    · exact Or.inr (Or.inl ⟨a1, n1, e2.trans e1⟩)
    · exact Or.inr (Or.inr ⟨a1, e2.trans e1⟩)
  · rcases h1.2 with e1 | ⟨_, _, e1⟩ | ⟨_, e1⟩
    · exact Or.inr (Or.inl ⟨e1 ▸ a2, (key_proc h1.1) ▸ n2, e2⟩)
    · rw [e1] at a2; cases a2
    · rw [e1] at a2; cases a2
  · rcases h1.2 with e1 | ⟨_, _, e1⟩ | ⟨_, e1⟩
    · exact Or.inr (Or.inr ⟨e1 ▸ a2, e2⟩)
    · rw [e1] at a2; cases a2
    · rw [e1] at a2; cases a2

/-- A pump command: a reply, a spawn of a resource now starting without a group, or TERM to the group of a resource
now stopping. -/
def Shp (now : Nat) (rs : List Rsrc) (x : Cmd) : Prop :=
  (∃ n r, x = .reply n r) ∨ (∃ y ∈ rs, x = .spawn y.id y.kind ∧ y.phase = .starting now ∧ y.proc = none)
  ∨ (∃ y ∈ rs, ∃ i, y.proc = some i ∧ y.phase = .stopping now .term ∧ x = .signal (.group i) .term)

theorem moved_phase {now : Nat} {y z : Rsrc} (h : Moved now y z) (ha : y.phase ≠ .absent) (hr : y.phase ≠ .ready) :
    z.phase = y.phase := by
  rcases h.2 with e1 | ⟨a1, _, _⟩ | ⟨a1, _⟩
  · exact e1
  · exact absurd a1 ha
  · exact absurd a1 hr

theorem shp_map {now : Nat} {rs : List Rsrc} {G : Rsrc → Rsrc} {x : Cmd} (h : Shp now rs x)
    (hg : ∀ y ∈ rs, Moved now y (G y)) : Shp now (rs.map G) x := by
  rcases h with h | ⟨y, hy, e, hp, hn⟩ | ⟨y, hy, i, hi, hp, e⟩
  · exact Or.inl h
  · have hk := (hg y hy).1
    have hp' := moved_phase (hg y hy) (by rw [hp]; exact fun e => Phase.noConfusion e)
      (by rw [hp]; exact fun e => Phase.noConfusion e)
    exact Or.inr (Or.inl ⟨G y, List.mem_map_of_mem hy, by rw [key_id hk, key_kind hk]; exact e, hp'.trans hp,
      (key_proc hk).trans hn⟩)
  · have hk := (hg y hy).1
    have hp' := moved_phase (hg y hy) (by rw [hp]; exact fun e => Phase.noConfusion e)
      (by rw [hp]; exact fun e => Phase.noConfusion e)
    exact Or.inr (Or.inr ⟨G y, List.mem_map_of_mem hy, i, (key_proc hk).trans hi, hp'.trans hp, e⟩)

/-- The pump resource and command invariant against the start state `s0`. -/
def PM (s0 : State) (a : Acc) : Prop :=
  (∃ F : Rsrc → Rsrc, a.st.res = s0.res.map F ∧ ∀ x ∈ s0.res, Moved s0.now x (F x)) ∧ ∀ x ∈ a.out, Shp s0.now a.st.res x

theorem pm_step {s0 : State} {a a' : Acc} (G : Rsrc → Rsrc) (cs : List Cmd) (h : PM s0 a)
    (hr : a'.st.res = a.st.res.map G) (hg : ∀ y ∈ a.st.res, Moved s0.now y (G y)) (ho : a'.out = a.out ++ cs)
    (hc : ∀ x ∈ cs, Shp s0.now a'.st.res x) : PM s0 a' := by
  obtain ⟨⟨F, hF, hFm⟩, hs⟩ := h
  refine ⟨⟨G ∘ F, by rw [hr, hF, List.map_map], fun x hx => (hFm x hx).trans (hg _ ?_)⟩, fun x hx => ?_⟩
  · rw [hF]; exact List.mem_map_of_mem hx
  · rw [ho] at hx
    rcases List.mem_append.1 hx with hx | hx
    · rw [hr]; exact shp_map (hs x hx) hg
    · exact hc x hx

theorem pm_same {s0 : State} {a a' : Acc} (cs : List Cmd) (h : PM s0 a) (hr : a'.st.res = a.st.res)
    (ho : a'.out = a.out ++ cs) (hc : ∀ x ∈ cs, ∃ n r, x = .reply n r) : PM s0 a' :=
  pm_step id cs h (by rw [hr, List.map_id]) (fun y _ => Moved.refl _ y) ho fun x hx => Or.inl (hc x hx)

theorem stopRec_moved (now : Nat) (ids : List Nat) (x : Rsrc) : Moved now x (stopRec now ids x).1 := by
  refine ⟨stopRec_key now ids x, ?_⟩
  unfold stopRec; split
  · split
    · rename_i hc
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      exact Or.inr (Or.inr ⟨hc.1, rfl⟩)
    · exact Or.inl rfl
  · exact Or.inl rfl

theorem stopRec_stops {now : Nat} {ids : List Nat} {y : Rsrc} {i : Ident} (hi : y.proc = some i) (hm : y.id ∈ ids)
    (hp : y.phase = .ready) : (stopRec now ids y).1.phase = .stopping now .term := by
  unfold stopRec; split
  · rw [if_pos (by simp [hp, hm])]
  · rename_i hj; rw [hi] at hj; cases hj

theorem pm_stop {c : Cfg} {s0 : State} {a : Acc} {rest : List Req} (xs : List Rsrc) (hj : PJ c s0 a rest)
    (h : PM s0 a) : PM s0 { a with st := (stopAll a.st xs).1, out := a.out ++ (stopAll a.st xs).2 } := by
  have hn : a.st.now = s0.now := hj.now
  refine pm_step _ _ h rfl (fun y _ => hn ▸ stopRec_moved _ _ y) rfl fun x hx => ?_
  obtain ⟨y, hy, i, hi, hm, hp, e⟩ := stopAll_sig hx
  refine Or.inr (Or.inr ⟨_, List.mem_map_of_mem hy, i, (stopRec_same _ _ y).2.2.2.trans hi, ?_, e⟩)
  rw [← hn]; exact stopRec_stops hi hm hp

theorem pumpOne_pm {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (hw : Wf c s0)
    (hj : PJ c s0 a (q :: rest)) (h : PM s0 a) : PM s0 (pumpOne c a q) := by
  have hn : a.st.now = s0.now := hj.now
  have hkeep : ∀ (a : Acc) b, PM s0 a → PM s0 (keepQ a q b) := fun a b h =>
    pm_same [] h rfl (List.append_nil _).symm fun _ hx => absurd hx List.not_mem_nil
  refine pumpOne_cases c a q (PM s0) (fun w _ => pm_same _ h rfl rfl fun x hx => ⟨_, _, List.mem_singleton.1 hx⟩)
    (fun _ _ _ _ => pm_step _ _ h rfl (fun y _ => ⟨ite_field key _ _ _ rfl, Or.inl (ite_field (·.phase) _ _ _ rfl)⟩) rfl
      fun x hx => Or.inl ⟨_, _, List.mem_singleton.1 hx⟩)
    (fun _ _ add _ => ?_) (fun _ _ _ => hkeep a false h)
    (fun _ _ _ _ _ why _ _ => pm_same _ h rfl rfl fun x hx => ⟨_, _, List.mem_singleton.1 hx⟩)
    (fun _ _ _ _ _ r hr hp hpr _ _ => ?_)
  · unfold block
    split
    · exact hkeep a true h
    · exact hkeep _ true (pm_stop _ hj h)
  · obtain ⟨hm, _⟩ := find_mem hr
    have hnd : (a.st.res.map (·.id)).Nodup := by rw [rids_of_key hj.key]; exact hw.rids
    refine hkeep _ false (pm_step _ _ h rfl (fun y hy => ⟨ite_field key _ _ _ rfl, ?_⟩) rfl fun x hx => ?_)
    · by_cases e : y.id = r.id
      · have := eq_of_nodup_map (·.id) _ hnd y r hy hm e
        subst this
        refine Or.inr (Or.inl ⟨hp, hpr, ?_⟩)
        simp [hn]
      · exact Or.inl (by simp [e])
    · rw [List.mem_singleton.1 hx]
      refine Or.inr (Or.inl ⟨_, List.mem_map_of_mem hm, by simp, by simp [hn], by simp [hpr]⟩)

theorem pump_pm {c : Cfg} {s0 : State} (hw : Wf c s0) : PM s0 (pumpAcc c s0) :=
  pump_ind hw (PM s0) ⟨⟨id, (List.map_id _).symm, fun x _ => Moved.refl _ x⟩, fun _ hx => absurd hx List.not_mem_nil⟩
    fun _ _ _ hj h => pumpOne_pm hw hj h

/-! ## Step decomposition -/

theorem step_mem {c : Cfg} {s : State} {e : Event} {x : Cmd} (h : x ∈ (step c s e).2) :
    authed c e = true ∧ (x ∈ (pre c s e).2 ∨ x ∈ (pumpAcc c (pre c s e).1).out) := by
  cases ha : authed c e
  · simp [step, ha] at h
  · rw [step_eq ha] at h
    exact ⟨rfl, List.mem_append.1 h⟩

theorem step_st {c : Cfg} {s : State} {e : Event} (ha : authed c e = true) :
    (step c s e).1 = (pumpAcc c (pre c s e).1).st := by
  rw [step_eq ha]; rfl

theorem step_out {c : Cfg} {s : State} {e : Event} (ha : authed c e = true) :
    (step c s e).2 = (pre c s e).2 ++ (pumpAcc c (pre c s e).1).out := by
  rw [step_eq ha]; rfl

theorem not_reply_pre {c : Cfg} {s : State} {e : Event} {n : Nat} {l : Lease} (h : .reply n (.granted l) ∈ (pre c s e).2) :
    l.kind = .job := by
  rcases pre_cmds h with hq | ⟨r, e', hr⟩
  · simp [quiet] at hq
  · simp only [Cmd.reply.injEq] at e'
    obtain ⟨_, rfl⟩ := e'
    exact (hr l rfl).1

theorem no_spawn_pre {c : Cfg} {s : State} {e : Event} {rid k : Nat} (h : .spawn rid k ∈ (pre c s e).2) : False := by
  rcases pre_cmds h with hq | ⟨r, e', _⟩
  · simp [quiet] at hq
  · cases e'

theorem pending_ids_nodup {c : Cfg} {s : State} (h : Wf c s) : (s.pending.map (·.id)).Nodup :=
  (List.nodup_append.1 h.ids).2.1

/-! ## Theorems -/

/-- sup_auth: an event that needs the token and lacks it changes nothing and sends nothing. -/
theorem sup_auth (c : Cfg) (s : State) (e : Event) (h : authed c e = false) : step c s e = (s, []) := by
  simp [step, h]

/-- run_eq_fold: one more event is the step from the state so far, its commands appended to the log. -/
theorem run_eq_fold (c : Cfg) (s : State) (es : List Event) (e : Event) :
    run c s (es ++ [e]) = ((step c (run c s es).1 e).1, (run c s es).2 ++ (step c (run c s es).1 e).2) := by
  simp [run, List.foldl_append]

/-- owner_unique: a process group belongs to at most one resource. -/
theorem owner_unique {c : Cfg} {s : State} (h : Inv c s) {x y : Rsrc} {i : Ident} (hx : x ∈ s.res) (hy : y ∈ s.res)
    (hxi : x.proc = some i) (hyi : y.proc = some i) : x = y :=
  eq_of_nodup_filterMap (·.proc) s.res h.1.procs x hx y hy i hxi hyi

/-- grant_ready: a granted service lease is held in the new state and its resource is ready there. -/
theorem grant_ready {c : Cfg} {s : State} {e : Event} {n : Nat} {l : Lease} (h : Inv c s)
    (hm : .reply n (.granted l) ∈ (step c s e).2) (hk : l.kind = .svc) :
    l ∈ (step c s e).1.leases ∧ ∃ r ∈ (step c s e).1.res, r.id = l.rid ∧ r.phase = .ready := by
  obtain ⟨ha, hm⟩ := step_mem hm
  have hw := wf_pre e h.1
  have hl : l ∈ (step c s e).1.leases := by
    rcases hm with hm | hm
    · rw [not_reply_pre hm] at hk; cases hk
    · rw [step_st ha, (pump_pj hw).leases]
      exact List.mem_append_right _ (List.mem_filterMap.2 ⟨_, hm, rfl⟩)
  exact ⟨hl, ((step_inv e h).1.svc l hl hk).2⟩

/-- spawned_recorded (spawn): a spawned resource is starting now in the new state, with no group yet. -/
theorem spawned_recorded {c : Cfg} {s : State} {e : Event} {rid k : Nat} (h : Inv c s)
    (hm : .spawn rid k ∈ (step c s e).2) :
    ∃ r ∈ (step c s e).1.res, r.id = rid ∧ r.kind = k ∧ r.phase = .starting (step c s e).1.now ∧ r.proc = none := by
  obtain ⟨ha, hm⟩ := step_mem hm
  have hw := wf_pre e h.1
  rcases hm with hm | hm
  · exact (no_spawn_pre hm).elim
  · rw [step_st ha]
    rcases (pump_pm hw).2 _ hm with ⟨_, _, e'⟩ | ⟨y, hy, e', hp, hn⟩ | ⟨_, _, _, _, _, e'⟩
    · cases e'
    · simp only [Cmd.spawn.injEq] at e'
      exact ⟨y, hy, e'.1.symm, e'.2.symm, by rw [(pump_pj hw).now]; exact hp, hn⟩
    · cases e'

theorem pre_spawned {c : Cfg} {s : State} {rid : Nat} {i : Ident}
    (hw : ∃ x ∈ s.res, x.id = rid ∧ x.proc = none ∧ ∃ t, x.phase = .starting t) (hf : ∀ x ∈ s.res, x.proc ≠ some i) :
    pre c s (.spawned rid (some i)) =
      ({ s with res := s.res.map fun x => if x.id == rid then { x with proc := some i, adopted := false } else x },
       [.probe rid]) := by
  simp only [pre, spawned]
  rw [if_neg, if_pos]
  · obtain ⟨x, hx, h1, h2, t, h3⟩ := hw
    exact List.any_eq_true.2 ⟨x, hx, by simp [h1, h2, h3]⟩
  · intro ha
    obtain ⟨x, hx, e⟩ := List.any_eq_true.1 ha
    exact hf x hx (by simpa using e)

/-- spawned_recorded (spawn result): a group reported for a waiting resource is set on exactly the records of that
id, and a probe follows. -/
theorem spawned_sets {c : Cfg} {s : State} {rid : Nat} {i : Ident} (h : Inv c s)
    (hw : ∃ x ∈ s.res, x.id = rid ∧ x.proc = none ∧ ∃ t, x.phase = .starting t) (hf : ∀ x ∈ s.res, x.proc ≠ some i) :
    (∀ y ∈ (step c s (.spawned rid (some i))).1.res, y.proc = some i ↔ y.id = rid)
    ∧ (∃ y ∈ (step c s (.spawned rid (some i))).1.res, y.id = rid)
    ∧ Cmd.probe rid ∈ (step c s (.spawned rid (some i))).2 := by
  have ha : authed c (.spawned rid (some i)) = true := rfl
  have hw' := wf_pre (.spawned rid (some i)) h.1
  obtain ⟨⟨F, hF, hFm⟩, _⟩ := pump_pm hw'
  have hpre := pre_spawned (c := c) hw hf
  refine ⟨fun y hy => ?_, ?_, ?_⟩
  · rw [step_st ha, hF] at hy
    obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hy
    have hk := (hFm x hx).1
    rw [key_proc hk, key_id hk]
    rw [hpre] at hx
    obtain ⟨z, hz, rfl⟩ := List.mem_map.1 hx
    by_cases e : z.id = rid
    · simp [e]
    · simp only [e, beq_iff_eq, if_false]
      exact ⟨fun h' => absurd h' (hf z hz), fun h' => h'.elim⟩
  · obtain ⟨x, hx, h1, _⟩ := hw
    have hx' : (if x.id == rid then { x with proc := some i, adopted := false } else x) ∈ (pre c s (.spawned rid (some i))).1.res := by
      rw [hpre]; exact List.mem_map_of_mem hx
    obtain ⟨y0, hy0, hid⟩ : ∃ y0 ∈ (pre c s (.spawned rid (some i))).1.res, y0.id = rid := ⟨_, hx', by simp [h1]⟩
    refine ⟨F y0, ?_, ?_⟩
    · rw [step_st ha, hF]; exact List.mem_map_of_mem hy0
    · rw [key_id (hFm _ hy0).1, hid]
  · rw [step_out ha, hpre]
    exact List.mem_append_left _ List.mem_cons_self

theorem adopt_live (rows : List Fw.Ops.Reap.Row) : ∀ (seen : List Ident) (xs : List Rsrc), ∀ y ∈ adopt rows seen xs,
    (y.phase.live = true ↔ ∃ i, y.proc = some i ∧ alive rows i = true)
  | _, [], _, h => absurd h List.not_mem_nil
  | seen, x :: xs, y, hy => by
    have hclear : ∀ y, y = adopt.clear x → (y.phase.live = true ↔ ∃ i, y.proc = some i ∧ alive rows i = true) := by
      intro y e
      subst e
      constructor
      · intro hl
        simp only [adopt.clear] at hl
        split at hl
        · cases hl
        · rename_i hn; exact absurd hl hn
      · intro ⟨_, hi, _⟩; cases hi
    unfold adopt at hy
    split at hy
    · rename_i i hi
      split at hy
      · rename_i hc
        rcases List.mem_cons.1 hy with e | hy
        · subst e
          simp only [Bool.and_eq_true] at hc
          exact ⟨fun _ => ⟨i, hi, hc.1.2⟩, fun _ => hc.1.1⟩
        · exact adopt_live rows _ xs y hy
      · rcases List.mem_cons.1 hy with e | hy
        · exact hclear y e
        · exact adopt_live rows _ xs y hy
    · rcases List.mem_cons.1 hy with e | hy
      · exact hclear y e
      · exact adopt_live rows _ xs y hy

theorem step_restart (c : Cfg) (s : State) (now : Nat) (snap : State) (inp : Fw.Ops.Reap.Input) :
    step c s (.restart now snap inp) = recover c now snap inp := by
  rw [step_eq rfl]
  exact Prod.ext rfl (List.append_nil _)

/-- recover_adopt_or_reap: after a restart a resource is live exactly when it keeps a group whose leader row is
alive; each reap plan target that no record owns gets TERM; each snapshot lease that is not well formed is revoked. -/
theorem recover_adopt_or_reap (c : Cfg) (s : State) (now : Nat) (snap : State) (inp : Fw.Ops.Reap.Input) :
    (∀ y ∈ (step c s (.restart now snap inp)).1.res,
      y.phase.live = true ↔ ∃ i, y.proc = some i ∧ alive inp.rows i = true)
    ∧ (∀ p ∈ Fw.Ops.Reap.plan inp, (∀ y ∈ (step c s (.restart now snap inp)).1.res, y.proc.map (·.pgid) ≠ some p.pid) →
        .signal (.reap p) .term ∈ (step c s (.restart now snap inp)).2)
    ∧ ∀ l ∈ snap.leases,
        validLease c (step c s (.restart now snap inp)).1.res (step c s (.restart now snap inp)).1.now l = false →
        .revoke l.owner l.id ∈ (step c s (.restart now snap inp)).2 := by
  rw [step_restart]
  refine ⟨fun y hy => adopt_live _ _ _ y hy, fun p hp ho => ?_, fun l hl hv => ?_⟩
  · have hn : ((recover c now snap inp).1.res.any fun x => x.proc.map (·.pgid) == some p.pid) = false :=
      List.any_eq_false.2 fun y hy e => ho y hy (by simpa using e)
    simp only [recover] at hn ⊢
    exact List.mem_append_right _ (List.mem_map.2 ⟨p, List.mem_filter.2 ⟨hp, by simp [hn]⟩, rfl⟩)
  · simp only [recover] at hv ⊢
    exact List.mem_append_left _ (List.mem_map.2 ⟨l, List.mem_filter.2 ⟨hl, by simp [hv]⟩, rfl⟩)

/-- client_gone_releases: a gone client holds no lease, has no queued request, and none of its queued requests gets a
reply. -/
theorem client_gone_releases {c : Cfg} {s : State} {o : Nat} (h : Inv c s) :
    (∀ l ∈ (step c s (.clientGone o)).1.leases, l.owner ≠ o)
    ∧ (∀ q ∈ (step c s (.clientGone o)).1.pending, q.owner ≠ o)
    ∧ ∀ q ∈ s.pending, q.owner = o → ∀ r, .reply q.id r ∉ (step c s (.clientGone o)).2 := by
  have ha : authed c (.clientGone o) = true := rfl
  have hw := wf_pre (.clientGone o) h.1
  have hj := pump_pj hw
  have hpend : ∀ q ∈ (pre c s (.clientGone o)).1.pending, q ∈ s.pending ∧ q.owner ≠ o := fun q hq => by
    have := List.mem_filter.1 hq
    exact ⟨this.1, by simpa using this.2⟩
  refine ⟨fun l hl => ?_, fun q hq => ?_, fun q hq ho r hr => ?_⟩
  · rw [step_st ha, hj.leases] at hl
    rcases List.mem_append.1 hl with hl | hl
    · have := (List.mem_filter.1 hl).2
      simpa using this
    · obtain ⟨x, hx, hl'⟩ := List.mem_filterMap.1 hl
      cases x with
      | reply n r' =>
        cases r' with
        | granted l' =>
          cases hl'
          obtain ⟨_, _, q', hq', _, e, _⟩ := hj.gid n l hx
          rw [← e]; exact (hpend q' hq').2
        | _ => cases hl'
      | _ => cases hl'
  · rw [step_st ha] at hq
    have := hj.sub.subset (List.mem_append_left _ hq)
    exact (hpend q this).2
  · obtain ⟨_, hr⟩ := step_mem hr
    rcases hr with hr | hr
    · cases hr
    · have hm : q.id ∈ replyIds (pumpAcc c (pre c s (.clientGone o)).1).out := List.mem_filterMap.2 ⟨_, hr, rfl⟩
      have := hj.perm.subset (List.mem_append_left _ hm)
      obtain ⟨q', hq', e⟩ := List.mem_map.1 this
      have h2 := hpend q' hq'
      have := eq_of_nodup_map (·.id) _ (pending_ids_nodup h.1) q' q h2.1 hq e
      rw [this] at h2
      exact h2.2 ho

theorem pre_nested {c : Cfg} {s : State} {o p : Nat} {a : Ask} (hp : a.parent = some p) :
    (pre c s (.request c.token o a)).1.pending = s.pending ∧
    ∃ r, (pre c s (.request c.token o a)).2 = [.reply s.next r] := by
  simp only [pre, request, hp]
  split
  · split
    · exact ⟨rfl, _, rfl⟩
    · exact ⟨rfl, _, rfl⟩
  · exact ⟨rfl, _, rfl⟩

/-- nested_no_wait: a nested request is answered in the step that receives it and never queued. -/
theorem nested_no_wait {c : Cfg} {s : State} {o p : Nat} {a : Ask} (h : Inv c s) (hp : a.parent = some p) :
    (∃ r, .reply s.next r ∈ (step c s (.request c.token o a)).2)
    ∧ ∀ q ∈ (step c s (.request c.token o a)).1.pending, q.id ≠ s.next := by
  have ha : authed c (.request c.token o a) = true := by simp [authed]
  obtain ⟨hpq, r, hr⟩ := pre_nested (c := c) (s := s) (o := o) hp
  refine ⟨⟨r, ?_⟩, fun q hq => ?_⟩
  · rw [step_out ha, hr]; exact List.mem_append_left _ List.mem_cons_self
  · have hj := pump_pj (wf_pre (.request c.token o a) h.1)
    rw [step_st ha] at hq
    have hq' := hj.sub.subset (List.mem_append_left _ hq)
    rw [hpq] at hq'
    have := h.1.below q.id (List.mem_append_right _ (List.mem_map_of_mem hq'))
    exact Nat.ne_of_lt this

/-! ## Pump decisions -/

/-- Load plus external footprint within budget in every dimension. -/
def Fits (c : Cfg) (s : State) : Prop := ∀ d, used s d + s.obs.ext.get d ≤ c.budget.get d

/-- Some command admits load: a job grant or a spawn. -/
def Adm (cs : List Cmd) : Prop :=
  ∃ x ∈ cs, (∃ n l, x = .reply n (.granted l) ∧ l.kind = .job) ∨ ∃ rid k, x = .spawn rid k

/-- A command allowed while shedding: a reply that grants nothing, or TERM to a group. -/
def ShedOk (x : Cmd) : Prop := (∃ n r, x = .reply n r ∧ ∀ l, r ≠ .granted l) ∨ ∃ i, x = .signal (.group i) .term

theorem adm_append {a b : List Cmd} (h : Adm (a ++ b)) : Adm a ∨ Adm b := by
  obtain ⟨x, hx, hp⟩ := h
  rcases List.mem_append.1 hx with hx | hx
  · exact Or.inl ⟨x, hx, hp⟩
  · exact Or.inr ⟨x, hx, hp⟩

theorem not_adm {cs : List Cmd} (h : ∀ x ∈ cs, ShedOk x) : ¬ Adm cs := by
  rintro ⟨x, hx, ⟨n, l, e, _⟩ | ⟨rid, k, e⟩⟩ <;> rcases h x hx with ⟨n', r, e', hr⟩ | ⟨i, e'⟩ <;> rw [e] at e'
  · simp only [Cmd.reply.injEq] at e'; exact hr l e'.2.symm
  · cases e'
  · cases e'
  · cases e'

theorem fitsB_le {c : Cfg} {s : State} {add : Res → Nat} (h : fitsB c s add = true) (d : Res) :
    used s d + add d + s.obs.ext.get d ≤ c.budget.get d := by
  have := List.all_eq_true.1 h d (Res.mem_all d)
  simpa using this

theorem resLoad_cons (y : Rsrc) (ys : List Rsrc) (d : Res) :
    resLoad (y :: ys) d = (if y.phase.live then charge y d else 0) + resLoad ys d := by
  unfold resLoad
  cases h : y.phase.live <;> simp [List.filter_cons, h]

theorem resLoad_map_eq (f : Rsrc → Rsrc) (d : Res) : ∀ l : List Rsrc,
    (∀ x ∈ l, (f x).phase.live = x.phase.live ∧ charge (f x) d = charge x d) → resLoad (l.map f) d = resLoad l d
  | [], _ => rfl
  | x :: xs, h => by
    rw [List.map_cons, resLoad_cons, resLoad_cons, (h x List.mem_cons_self).1, (h x List.mem_cons_self).2,
      resLoad_map_eq f d xs fun y hy => h y (List.mem_cons_of_mem _ hy)]

theorem resLoad_map_one (f : Rsrc → Rsrc) (r : Rsrc) (d : Res) : ∀ l : List Rsrc, (l.map (·.id)).Nodup → r ∈ l →
    (∀ x ∈ l, x.id ≠ r.id → f x = x) → charge (f r) d ≤ charge r d → resLoad (l.map f) d ≤ resLoad l d + charge r d
  | [], _, h, _, _ => absurd h List.not_mem_nil
  | x :: xs, hn, hr, hf, hc => by
    rw [List.map_cons, List.nodup_cons] at hn
    rw [List.map_cons, resLoad_cons, resLoad_cons]
    rcases List.mem_cons.1 hr with e | hr'
    · have hfix : xs.map f = xs := by
        refine (List.map_congr_left fun y hy => hf y (List.mem_cons_of_mem _ hy) fun e' => ?_).trans (List.map_id xs)
        have hm : y.id ∈ xs.map (·.id) := List.mem_map_of_mem hy
        rw [e', e] at hm
        exact hn.1 hm
      rw [hfix, ← e]
      have : (if (f r).phase.live then charge (f r) d else 0) ≤ charge r d := by
        split
        · exact hc
        · exact Nat.zero_le _
      omega
    · have hx : x.id ≠ r.id := fun e => by
        have hm : r.id ∈ xs.map (·.id) := List.mem_map_of_mem hr'
        rw [← e] at hm
        exact hn.1 hm
      rw [hf x List.mem_cons_self hx]
      have := resLoad_map_one f r d xs hn.2 hr' (fun y hy => hf y (List.mem_cons_of_mem _ hy)) hc
      omega

theorem used_grant (a : Acc) (q : Req) (d : Res) :
    used (grant a q).st d = used a.st d + (if q.kind == .svc then ({} : Vec) else q.cost).get d := by
  simp only [grant, used, leaseLoad, List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons,
    List.sum_nil, leaseOf]
  have e : resLoad (a.st.res.map fun x =>
      if (q.kind == .svc && x.id == q.rid) = true then { x with lastUse := a.st.now } else x) d = resLoad a.st.res d :=
    resLoad_map_eq _ d _ fun x _ => by split <;> exact ⟨rfl, rfl⟩
  rw [e]
  omega

theorem stopRec_live (now : Nat) (ids : List Nat) (x : Rsrc) (d : Res) :
    (stopRec now ids x).1.phase.live = x.phase.live ∧ charge (stopRec now ids x).1 d = charge x d := by
  unfold stopRec; split
  · split
    · rename_i hc
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      exact ⟨by rw [hc.1]; rfl, rfl⟩
    · exact ⟨rfl, rfl⟩
  · exact ⟨rfl, rfl⟩

theorem used_stop (s : State) (xs : List Rsrc) (d : Res) : used (stopAll s xs).1 d = used s d := by
  simp only [stopAll, mapRes, used]
  rw [resLoad_map_eq _ d _ fun x _ => stopRec_live _ _ x d]

theorem used_start {a : Acc} {q : Req} {r : Rsrc} (hn : (a.st.res.map (·.id)).Nodup) (hr : r ∈ a.st.res) (d : Res) :
    used (start a q r).st d ≤ used a.st d + charge r d := by
  simp only [start, keepQ, used]
  have := resLoad_map_one (fun x => if x.id == r.id then { x with phase := .starting a.st.now, foot := {} } else x) r d
    a.st.res hn hr (fun x _ hx => by simp [hx]) (by simp [charge, vec_zero]; exact Nat.le_max_left _ _)
  omega

theorem fits_of {c : Cfg} {st st' : State} {add : Res → Nat} (h : fitsB c st add = true)
    (hu : ∀ d, used st' d ≤ used st d + add d) (ho : st'.obs = st.obs) : Fits c st' := fun d => by
  have := fitsB_le h d
  have := hu d
  rw [ho]
  omega

/-- The pump decision invariant against the start state `s0`. -/
structure PD (c : Cfg) (s0 : State) (a : Acc) : Prop where
  spawn : ∀ rid k, .spawn rid k ∈ a.out → ∃ x ∈ s0.res, x.id = rid ∧ x.phase = .absent ∧ x.proc = none ∧
    (recent c s0.now x.crashes).length < c.maxRestarts
  shed : s0.shedding = true → ∀ x ∈ a.out, ShedOk x
  drain : s0.draining = true → ∀ x ∈ a.out, ∃ n w, x = .reply n (.refused w)
  fits : Adm a.out → Fits c a.st

theorem pd_step {c : Cfg} {s0 : State} {a a' : Acc} (cs : List Cmd) (h : PD c s0 a) (ho : a'.out = a.out ++ cs)
    (hsp : ∀ rid k, .spawn rid k ∈ cs → ∃ x ∈ s0.res, x.id = rid ∧ x.phase = .absent ∧ x.proc = none ∧
      (recent c s0.now x.crashes).length < c.maxRestarts)
    (hsh : s0.shedding = true → ∀ x ∈ cs, ShedOk x)
    (hdr : s0.draining = true → ∀ x ∈ cs, ∃ n w, x = .reply n (.refused w))
    (hf : (Adm a.out → Fits c a.st) → Adm a'.out → Fits c a'.st) : PD c s0 a' := by
  refine ⟨fun rid k hm => ?_, fun hs x hx => ?_, fun hd x hx => ?_, hf h.fits⟩
  · rw [ho] at hm
    rcases List.mem_append.1 hm with hm | hm
    · exact h.spawn rid k hm
    · exact hsp rid k hm
  · rw [ho] at hx
    rcases List.mem_append.1 hx with hx | hx
    · exact h.shed hs x hx
    · exact hsh hs x hx
  · rw [ho] at hx
    rcases List.mem_append.1 hx with hx | hx
    · exact h.drain hd x hx
    · exact hdr hd x hx

theorem fits_keep {c : Cfg} {a a' : Acc} {cs : List Cmd} (ho : a'.out = a.out ++ cs) (hq : ∀ x ∈ cs, ShedOk x)
    (hu : ∀ d, used a'.st d = used a.st d) (hob : a'.st.obs = a.st.obs) :
    (Adm a.out → Fits c a.st) → Adm a'.out → Fits c a'.st := fun hf hA d => by
  rw [ho] at hA
  rcases adm_append hA with hA | hA
  · have := hf hA d; rw [hu d, hob]; exact this
  · exact absurd hA (not_adm hq)

theorem refused_ok (n : Nat) (w : Why) : ShedOk (.reply n (.refused w)) := Or.inl ⟨n, _, rfl, fun _ e => Reply.noConfusion e⟩

theorem pd_refuse {c : Cfg} {s0 : State} {a a' : Acc} (n : Nat) (w : Why) (h : PD c s0 a)
    (ho : a'.out = a.out ++ [.reply n (.refused w)]) (hu : ∀ d, used a'.st d = used a.st d) (hob : a'.st.obs = a.st.obs) :
    PD c s0 a' :=
  pd_step _ h ho (fun _ _ hm => by cases List.mem_singleton.1 hm) (fun _ x hx => List.mem_singleton.1 hx ▸ refused_ok n w)
    (fun _ x hx => ⟨n, w, List.mem_singleton.1 hx⟩)
    (fits_keep ho (fun x hx => List.mem_singleton.1 hx ▸ refused_ok n w) hu hob)

theorem pd_keepQ {c : Cfg} {s0 : State} {a : Acc} {q : Req} (b : Bool) (h : PD c s0 a) : PD c s0 (keepQ a q b) :=
  pd_step [] h (List.append_nil _).symm (fun _ _ hm => absurd hm List.not_mem_nil) (fun _ _ hx => absurd hx List.not_mem_nil)
    (fun _ _ hx => absurd hx List.not_mem_nil) (fits_keep (List.append_nil _).symm (fun _ hx => absurd hx List.not_mem_nil)
      (fun _ => rfl) rfl)

theorem key_crashes {x y : Rsrc} (h : key y = key x) : y.crashes = x.crashes := congrArg (·.2.2.2.2.2) h

theorem pumpOne_pd {c : Cfg} {s0 : State} {a : Acc} {q : Req} {rest : List Req} (hw : Wf c s0)
    (hj : PJ c s0 a (q :: rest)) (hm : PM s0 a) (h : PD c s0 a) : PD c s0 (pumpOne c a q) := by
  have hn : a.st.now = s0.now := hj.now
  have hsh : a.st.shedding = s0.shedding := hj.shedding
  have hdr : a.st.draining = s0.draining := hj.draining
  refine pumpOne_cases c a q (PD c s0) (fun w _ => pd_refuse q.id w h rfl (fun _ => rfl) rfl)
    (fun _ hd hs hc => ?_) (fun _ hd add _ => ?_) (fun _ _ _ => pd_keepQ false h)
    (fun _ _ _ _ _ why _ _ => pd_refuse q.id why h rfl (fun _ => rfl) rfl)
    (fun _ hd hs _ _ r hr hp hpr hcr hfit => ?_)
  · refine pd_step _ h rfl (fun _ _ hm => by cases List.mem_singleton.1 hm) (fun e => ?_) (fun e => ?_) ?_
    · rw [← hsh, hs] at e; cases e
    · rw [← hdr, hd] at e; cases e
    · intro hf hA d
      rw [used_grant]
      rcases hc with ⟨hk, _, hfit⟩ | ⟨hk, _⟩
      · have := fitsB_le hfit d
        simp only [hk]
        show used a.st d + q.cost.get d + a.st.obs.ext.get d ≤ c.budget.get d
        exact this
      · rcases adm_append hA with hA | ⟨x, hx, ⟨n, l, e, hl⟩ | ⟨_, _, e⟩⟩
        · have := hf hA d
          have e2 : (if (q.kind == LKind.svc) = true then ({} : Vec) else q.cost).get d = 0 := by
            simp [hk, vec_zero]
          rw [e2]
          show used a.st d + 0 + a.st.obs.ext.get d ≤ c.budget.get d
          omega
        · rw [List.mem_singleton.1 hx] at e
          simp only [Cmd.reply.injEq, Reply.granted.injEq] at e
          rw [← e.2] at hl
          simp [leaseOf, hk] at hl
        · rw [List.mem_singleton.1 hx] at e; cases e
  · unfold block
    split
    · exact pd_keepQ true h
    · refine pd_keepQ true (pd_step _ h rfl (fun _ _ hm => ?_) (fun _ x hx => ?_) (fun e => ?_)
        (fits_keep rfl (fun x hx => ?_) (fun d => used_stop _ _ d) rfl))
      · obtain ⟨_, _, _, _, _, _, e⟩ := stopAll_sig hm; cases e
      · obtain ⟨_, _, i, _, _, _, e⟩ := stopAll_sig hx; exact Or.inr ⟨i, e⟩
      · rw [← hdr, hd] at e; cases e
      · obtain ⟨_, _, i, _, _, _, e⟩ := stopAll_sig hx; exact Or.inr ⟨i, e⟩
  · obtain ⟨hmem, _⟩ := find_mem hr
    have hnd : (a.st.res.map (·.id)).Nodup := by rw [rids_of_key hj.key]; exact hw.rids
    refine pd_step _ h rfl (fun rid k hm' => ?_) (fun e => ?_) (fun e => ?_)
      fun _ _ => fits_of hfit (fun d => used_start hnd hmem d) rfl
    · obtain ⟨⟨F, hF, hFm⟩, _⟩ := hm
      simp only [List.mem_singleton, Cmd.spawn.injEq] at hm'
      rw [hF] at hmem
      obtain ⟨x, hx, e⟩ := List.mem_map.1 hmem
      have hmv := hFm x hx
      rw [e] at hmv
      have hpx : x.phase = .absent := by
        rcases hmv.2 with e1 | ⟨_, _, e1⟩ | ⟨_, e1⟩
        · rw [← e1, hp]
        · rw [hp] at e1; cases e1
        · rw [hp] at e1; cases e1
      refine ⟨x, hx, by rw [← key_id hmv.1, hm'.1], hpx, by rw [← key_proc hmv.1, hpr], ?_⟩
      rw [← key_crashes hmv.1, ← hn]; exact hcr
    · rw [← hsh, hs] at e; cases e
    · rw [← hdr, hd] at e; cases e

theorem pump_pd {c : Cfg} {s0 : State} (hw : Wf c s0) : PD c s0 (pumpAcc c s0) := by
  have := pump_ind hw (fun a => PM s0 a ∧ PD c s0 a)
    ⟨⟨⟨id, (List.map_id _).symm, fun x _ => Moved.refl _ x⟩, fun _ hx => absurd hx List.not_mem_nil⟩,
      ⟨fun _ _ hm => absurd hm List.not_mem_nil, fun _ _ hx => absurd hx List.not_mem_nil,
        fun _ _ hx => absurd hx List.not_mem_nil, fun ⟨_, hx, _⟩ => absurd hx List.not_mem_nil⟩⟩
    fun _ _ _ hj h => ⟨pumpOne_pm hw hj h.1, pumpOne_pd hw hj h.1 h.2⟩
  exact this.2

/-! ## Admission, shedding and draining -/

/-- A command that admits nothing: no grant and no spawn. -/
def NoAdm (x : Cmd) : Prop := (∀ n l, x ≠ .reply n (.granted l)) ∧ ∀ rid k, x ≠ .spawn rid k

theorem shedOk_noAdm {x : Cmd} (h : ShedOk x) : NoAdm x := by
  rcases h with ⟨n, r, rfl, hr⟩ | ⟨i, rfl⟩
  · exact ⟨fun _ l e => (by simp only [Cmd.reply.injEq] at e; exact hr l e.2), fun _ _ e => by cases e⟩
  · exact ⟨fun _ _ e => (by cases e), fun _ _ e => by cases e⟩

theorem tick_quiet {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Cmd} (h : x ∈ (tick c s now smp).2) :
    quiet x = true := by
  rcases tick_cmds h with ⟨_, _, _, _, _, e⟩ | ⟨_, _, e⟩ | ⟨_, _, e⟩ | e <;> (rw [e]; rfl)

theorem quiet_noAdm {x : Cmd} (h : quiet x = true) : NoAdm x :=
  ⟨fun _ _ e => (by subst e; simp [quiet] at h), fun _ _ e => by subst e; simp [quiet] at h⟩

theorem shedStage_st (c : Cfg) (s : State) : (shedStage c s).1 = { s with res := (shedStage c s).1.res } := by
  unfold shedStage; split <;> rfl

theorem shedStage_on {c : Cfg} {s : State} (hs : s.shedding = true) : shedStage c s = stopAll s (shedPick c s) := by
  unfold shedStage; rw [if_pos hs]

theorem tick_st (c : Cfg) (s : State) (now : Nat) (smp : Sample) :
    (tick c s now smp).1 = { (observe c s now smp).1 with res := (tick c s now smp).1.res } := by
  show (shedStage c (idleStage c (observe c s now smp).1).1).1 = _
  rw [shedStage_st]
  rfl

theorem observe_shed {c : Cfg} {s : State} {now : Nat} {smp : Sample}
    (ho : c.warn ≤ smp.pressure ∨ ∃ d, c.budget.get d < used (observe c s now smp).1 d + smp.ext.get d) :
    (observe c s now smp).1.shedding = true := by
  show shedOn c _ = true
  unfold shedOn
  rcases ho with ho | ⟨d, hd⟩
  · simp only [Bool.or_eq_true, decide_eq_true_eq]
    exact Or.inl (Or.inl ho)
  · have hf : fitsB c (observe c s now smp).1 (fun _ => 0) = false := by
      cases hf : fitsB c (observe c s now smp).1 (fun _ => 0)
      · rfl
      · have := fitsB_le hf d
        have ho : (observe c s now smp).1.obs = smp := rfl
        rw [ho] at this
        omega
    have hn : (!fitsB c (observe c s now smp).1 (fun _ => 0)) = true := by rw [hf]; rfl
    simp only [Bool.or_eq_true]
    exact Or.inl (Or.inr hn)

theorem stopAll_emits {s : State} {xs : List Rsrc} {y : Rsrc} {i : Ident} (hy : y ∈ s.res) (hx : y ∈ xs)
    (hp : y.phase = .ready) (hi : y.proc = some i) : Cmd.signal (.group i) .term ∈ (stopAll s xs).2 := by
  unfold stopAll mapRes
  refine List.mem_flatMap.2 ⟨y, hy, ?_⟩
  have hm : y.id ∈ xs.map (·.id) := List.mem_map_of_mem hx
  simp [stopRec, hi, hp, hm]

theorem cands_ready {c : Cfg} {s : State} {y : Rsrc} (h : y ∈ cands c s) : y ∈ s.res ∧ y.phase = .ready := by
  have := List.mem_filter.1 h
  refine ⟨this.1, ?_⟩
  have h2 := this.2
  simp only [Bool.and_eq_true, beq_iff_eq] at h2
  exact h2.1.1.1

theorem step_pd {c : Cfg} {s : State} {e : Event} (h : Inv c s) : PD c (pre c s e).1 (pumpAcc c (pre c s e).1) :=
  pump_pd (wf_pre e h.1)

theorem grantsIn_nil : ∀ cs : List Cmd, (∀ x ∈ cs, ∃ n w, x = .reply n (.refused w)) → grantsIn cs = []
  | [], _ => rfl
  | x :: xs, h => by
    obtain ⟨n, w, rfl⟩ := h x List.mem_cons_self
    simp only [grantsIn, List.filterMap_cons]
    exact grantsIn_nil xs fun y hy => h y (List.mem_cons_of_mem _ hy)

theorem request_draining (c : Cfg) (s : State) (o : Nat) (a : Ask) : (request c s o a).1.draining = s.draining := by
  unfold request
  dsimp only
  split
  · split
    · split <;> rfl
    · rfl
  · rfl

theorem pre_drain {c : Cfg} {s : State} {e : Event} {n : Nat} {l : Lease} (hd : (pre c s e).1.draining = true)
    (h : .reply n (.granted l) ∈ (pre c s e).2) : False := by
  cases e with
  | request t o a =>
    have hd' : s.draining = true := by rw [← request_draining c s o a]; exact hd
    simp only [pre, request] at h
    split at h
    · split at h
      · split at h
        · simp at h
        · rename_i hn; exact hn hd'
      · simp at h
    · cases h
  | release t o lid => simp only [pre, release] at h; split at h <;> simp at h
  | renew t o lid =>
    simp only [pre, renew] at h
    split at h
    · split at h <;> simp at h
    · simp at h
  | op t o => simp [pre] at h
  | drain t o => simp [pre] at h
  | spawned rid i =>
    simp only [pre] at h
    unfold spawned at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h <;> simp at h
  | ready rid => cases h
  | childExit i => simp only [pre, childExit] at h; obtain ⟨_, _, _, e⟩ := cut_cmd h; cases e
  | tick now smp => rcases tick_cmds h with ⟨_, _, _, _, _, e⟩ | ⟨_, _, e⟩ | ⟨_, _, e⟩ | e <;> cases e
  | clientGone o => cases h
  | restart now snap inp =>
    simp only [pre, recover] at h
    rcases List.mem_append.1 h with h | h <;> (obtain ⟨_, _, e⟩ := List.mem_map.1 h; cases e)

theorem tick_exit {c : Cfg} {s : State} {now : Nat} {smp : Sample} (h : .exit ∈ (tick c s now smp).2) :
    (tick c s now smp).1.draining = true ∧ (tick c s now smp).1.leases = [] := by
  unfold tick at h ⊢
  dsimp only at h ⊢
  generalize hb : idleStage c (observe c s now smp).1 = b at h ⊢
  generalize hd : shedStage c b.1 = d at h ⊢
  rcases List.mem_append.1 h with h | h
  · exfalso
    rcases List.mem_append.1 h with h | h
    · rcases List.mem_append.1 h with h | h
      · rcases observe_cmds h with ⟨_, _, _, _, e⟩ | ⟨_, _, e⟩ | ⟨_, _, e⟩ <;> cases e
      · rw [← hb] at h; obtain ⟨_, _, _, _, _, _, e⟩ := stopAll_sig h; cases e
    · rw [← hd] at h
      rcases shedStage_eq c b.1 with e | e <;> rw [e] at h
      · obtain ⟨_, _, _, _, _, _, e⟩ := stopAll_sig h; cases e
      · cases h
  · split at h
    · rename_i hc
      simp only [Bool.and_eq_true, List.isEmpty_iff] at hc
      exact hc
    · cases h

theorem pre_exit {c : Cfg} {s : State} {e : Event} (h : Cmd.exit ∈ (pre c s e).2) :
    (pre c s e).1.draining = true ∧ (pre c s e).1.leases = [] := by
  cases e with
  | request t o a =>
    exfalso
    simp only [pre, request] at h
    split at h
    · split at h
      · split at h <;> simp at h
      · simp at h
    · cases h
  | release t o lid => exfalso; simp only [pre, release] at h; split at h <;> simp at h
  | renew t o lid =>
    exfalso
    simp only [pre, renew] at h
    split at h
    · split at h <;> simp at h
    · simp at h
  | op t o => simp [pre] at h
  | drain t o => simp [pre] at h
  | spawned rid i =>
    exfalso
    simp only [pre] at h
    unfold spawned at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h <;> simp at h
  | ready rid => cases h
  | childExit i => exfalso; simp only [pre, childExit] at h; obtain ⟨_, _, _, e⟩ := cut_cmd h; cases e
  | tick now smp => exact tick_exit h
  | clientGone o => cases h
  | restart now snap inp =>
    exfalso
    simp only [pre, recover] at h
    rcases List.mem_append.1 h with h | h <;> (obtain ⟨_, _, e⟩ := List.mem_map.1 h; cases e)

/-- admit_fits: a step that grants a costed job lease leaves load plus external footprint within budget. -/
theorem admit_fits {c : Cfg} {s : State} {e : Event} {n : Nat} {l : Lease} (h : Inv c s)
    (hm : .reply n (.granted l) ∈ (step c s e).2) (hk : l.kind = .job) (hc : l.cost ≠ {}) : Fits c (step c s e).1 := by
  obtain ⟨ha, hm⟩ := step_mem hm
  rw [step_st ha]
  rcases hm with hm | hm
  · rcases pre_cmds hm with hq | ⟨r, e', hr⟩
    · simp [quiet] at hq
    · simp only [Cmd.reply.injEq] at e'
      exact absurd (hr l e'.2.symm).2 hc
  · exact (step_pd h).fits ⟨_, hm, Or.inl ⟨n, l, rfl, hk⟩⟩

/-- spawn_fits: a step that spawns leaves load plus external footprint within budget. -/
theorem spawn_fits {c : Cfg} {s : State} {e : Event} {rid k : Nat} (h : Inv c s) (hm : .spawn rid k ∈ (step c s e).2) :
    Fits c (step c s e).1 := by
  obtain ⟨ha, hm⟩ := step_mem hm
  rw [step_st ha]
  rcases hm with hm | hm
  · exact (no_spawn_pre hm).elim
  · exact (step_pd h).fits ⟨_, hm, Or.inr ⟨rid, k, rfl⟩⟩

/-- restart_bounded (spawn): a spawned resource has fewer than `maxRestarts` crashes within the window. -/
theorem restart_bounded {c : Cfg} {s : State} {e : Event} {rid k : Nat} (h : Inv c s)
    (hm : .spawn rid k ∈ (step c s e).2) :
    ∃ r ∈ (step c s e).1.res, r.id = rid ∧ r.phase = .starting (step c s e).1.now ∧
      (recent c (step c s e).1.now r.crashes).length < c.maxRestarts := by
  obtain ⟨y, hy, hid, _, hph, _⟩ := spawned_recorded h hm
  obtain ⟨ha, hm'⟩ := step_mem hm
  have hw := wf_pre e h.1
  rcases hm' with hm' | hm'
  · exact (no_spawn_pre hm').elim
  obtain ⟨x, hx, hxid, _, _, hrc⟩ := (pump_pd hw).spawn rid k hm'
  have hj := pump_pj hw
  have hy' : y ∈ (pumpAcc c (pre c s e).1).st.res := by rw [← step_st ha]; exact hy
  have hk : key y ∈ (pre c s e).1.res.map key := by rw [← hj.key]; exact List.mem_map_of_mem hy'
  obtain ⟨x', hx', hkx⟩ := List.mem_map.1 hk
  have e1 : x' = x := eq_of_nodup_map (·.id) _ hw.rids x' x hx' hx ((key_id hkx).trans (hid.trans hxid.symm))
  refine ⟨y, hy, hid, hph, ?_⟩
  rw [step_st ha, hj.now, key_crashes hkx.symm, e1]
  exact hrc

/-- restart_bounded (cap): a crash that reaches the cap fails the resource with `restartCap` until the window ends. -/
theorem crash_cap (c : Cfg) (now : Nat) (f : Bool) (x : Rsrc) (h : c.maxRestarts ≤ (crash c now f x).crashes.length) :
    (crash c now f x).phase = .failed (now + c.window) .restartCap := by
  simp only [crash] at h ⊢
  rw [if_pos h]

/-- overrun_sheds: a tick that sees pressure at warn or load plus external footprint over budget sheds, admits nothing,
and sends TERM to the group of every resource the shed pick names. -/
theorem overrun_sheds {c : Cfg} {s : State} {now : Nat} {smp : Sample} (h : Inv c s)
    (ho : c.warn ≤ smp.pressure ∨ ∃ d, c.budget.get d < used (observe c s now smp).1 d + smp.ext.get d) :
    (step c s (.tick now smp)).1.shedding = true ∧ (∀ x ∈ (step c s (.tick now smp)).2, NoAdm x) ∧
    ∀ y ∈ shedPick c (idleStage c (observe c s now smp).1).1, ∀ i, y.proc = some i →
      Cmd.signal (.group i) .term ∈ (step c s (.tick now smp)).2 := by
  have hs : (observe c s now smp).1.shedding = true := observe_shed ho
  have hp : (pre c s (.tick now smp)).1.shedding = true := (congrArg State.shedding (tick_st c s now smp)).trans hs
  have hw := wf_pre (.tick now smp) h.1
  refine ⟨by rw [step_st (e := .tick now smp) rfl, (pump_pj hw).shedding]; exact hp, fun x hx => ?_, fun y hy i hi => ?_⟩
  · rw [step_out (e := .tick now smp) rfl] at hx
    rcases List.mem_append.1 hx with hx | hx
    · exact quiet_noAdm (tick_quiet hx)
    · exact shedOk_noAdm ((pump_pd hw).shed hp x hx)
  · have hB : (idleStage c (observe c s now smp).1).1.shedding = true := hs
    obtain ⟨hr, hrd⟩ := cands_ready (shedPick_cands hy)
    rw [step_out (e := .tick now smp) rfl]
    refine List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ ?_))
    show _ ∈ (shedStage c (idleStage c (observe c s now smp).1).1).2
    rw [shedStage_on hB]
    exact stopAll_emits hr hy hrd hi

/-- starvation_limit: while the new state sheds, the step spawns nothing and grants only nested job joins of cost zero,
so queued requests wait until shedding ends. -/
theorem starvation_limit {c : Cfg} {s : State} {e : Event} {x : Cmd} (h : Inv c s)
    (hs : (step c s e).1.shedding = true) (hx : x ∈ (step c s e).2) :
    (∀ rid k, x ≠ .spawn rid k) ∧ ∀ n l, x = .reply n (.granted l) → n = s.next ∧ l.kind = .job ∧ l.cost = {} := by
  obtain ⟨ha, hx⟩ := step_mem hx
  have hw := wf_pre e h.1
  rw [step_st ha, (pump_pj hw).shedding] at hs
  rcases hx with hx | hx
  · refine ⟨fun rid k e' => (by subst e'; exact no_spawn_pre hx), fun n l e' => ?_⟩
    rcases pre_cmds hx with hq | ⟨r, e2, hr⟩
    · rw [e'] at hq; simp [quiet] at hq
    · rw [e'] at e2
      simp only [Cmd.reply.injEq] at e2
      exact ⟨e2.1, hr l e2.2.symm⟩
  · have := shedOk_noAdm ((pump_pd hw).shed hs x hx)
    exact ⟨this.2, fun n l e' => absurd e' (this.1 n l)⟩

/-- drain_quiet: a step whose new state drains spawns nothing and grants nothing. -/
theorem drain_quiet {c : Cfg} {s : State} {e : Event} {x : Cmd} (h : Inv c s) (hd : (step c s e).1.draining = true)
    (hx : x ∈ (step c s e).2) : NoAdm x := by
  obtain ⟨ha, hx⟩ := step_mem hx
  have hw := wf_pre e h.1
  rw [step_st ha, (pump_pj hw).draining] at hd
  rcases hx with hx | hx
  · exact ⟨fun n l e' => (by subst e'; exact pre_drain hd hx), fun rid k e' => by subst e'; exact no_spawn_pre hx⟩
  · obtain ⟨n, w, e'⟩ := (pump_pd hw).drain hd x hx
    subst e'
    exact shedOk_noAdm (refused_ok n w)

/-- drain_quiet (exit): the exit command leaves a draining state with no lease. -/
theorem drain_exit {c : Cfg} {s : State} {e : Event} (h : Inv c s) (hx : Cmd.exit ∈ (step c s e).2) :
    (step c s e).1.draining = true ∧ (step c s e).1.leases = [] := by
  obtain ⟨ha, hx⟩ := step_mem hx
  have hw := wf_pre e h.1
  have hj := pump_pj hw
  rcases hx with hx | hx
  · obtain ⟨hd, hl⟩ := pre_exit hx
    rw [step_st ha, hj.draining, hj.leases, hl, grantsIn_nil _ ((pump_pd hw).drain hd)]
    exact ⟨hd, rfl⟩
  · rcases (pump_pm hw).2 _ hx with ⟨_, _, e'⟩ | ⟨_, _, e', _, _⟩ | ⟨_, _, _, _, _, e'⟩ <;> cases e'

/-! ## Signals -/

theorem crash_not_ready (c : Cfg) (now : Nat) (f : Bool) (x : Rsrc) : (crash c now f x).phase ≠ .ready := by
  unfold crash
  dsimp only
  split
  · intro h; cases h
  · split <;> (intro h; cases h)

theorem ageRec_ready {c : Cfg} {now : Nat} {x : Rsrc} (h : (ageRec c now x).1.phase = .ready) : x.phase = .ready := by
  unfold ageRec at h
  split at h <;> (try split at h) <;> first | exact h | exact absurd h (crash_not_ready _ _ _ _) | cases h

theorem goneRec_ready {c : Cfg} {now : Nat} {rows : List Fw.Ops.Reap.Row} {x : Rsrc}
    (h : (goneRec c now rows x).phase = .ready) : x.phase = .ready := by
  unfold goneRec at h
  split at h
  · split at h
    · unfold exits at h
      split at h <;> first | exact h | exact absurd h (crash_not_ready _ _ _ _) | cases h
    · exact h
  · exact h

theorem auditRec_phase (rows : List Fw.Ops.Reap.Row) (x : Rsrc) : (auditRec rows x).1.phase = x.phase := by
  unfold auditRec
  split
  · split
    · rfl
    · dsimp only
      split <;> rfl
  · rfl

theorem tickRec_ready {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {x : Rsrc}
    (h : (tickRec c ls now smp x).1.phase = .ready) : x.phase = .ready := by
  simp only [tickRec] at h
  rw [auditRec_phase] at h
  have h2 := ageRec_ready (goneRec_ready h)
  exact h2

theorem ageRec_nr {c : Cfg} {now : Nat} {y : Rsrc} {x : Cmd} (h : x ∈ (ageRec c now y).2) :
    (ageRec c now y).1.phase ≠ .ready := by
  unfold ageRec at h ⊢
  cases hp : y.phase with
  | absent => simp [hp] at h
  | ready => simp [hp] at h
  | starting t =>
    simp only [hp] at h ⊢
    split at h
    · rw [if_pos (by assumption)]; exact crash_not_ready _ _ _ _
    · cases h
  | stopping t g =>
    cases g with
    | term =>
      simp only [hp] at h ⊢
      split at h
      · rw [if_pos (by assumption)]; intro e; cases e
      · cases h
    | kill => simp [hp] at h
  | failed u w => simp [hp] at h

theorem tickRec_grp {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {x : Rsrc} {i : Ident} {g : Sig}
    (h : Cmd.signal (.group i) g ∈ (tickRec c ls now smp x).2) :
    x.proc = some i ∧ (tickRec c ls now smp x).1.phase ≠ .ready := by
  simp only [tickRec] at h ⊢
  rcases List.mem_append.1 h with h | h
  · obtain ⟨j, hj, e⟩ := ageRec_sig h
    simp only [Cmd.signal.injEq, Target.group.injEq] at e
    refine ⟨by rw [e.1]; exact hj, ?_⟩
    rw [auditRec_phase]
    intro e2
    exact ageRec_nr h (goneRec_ready e2)
  · obtain ⟨r, _, e⟩ := auditRec_sig h
    cases e

/-- No record with group `i` is ready. -/
def NR (i : Ident) (rs : List Rsrc) : Prop := ∀ r ∈ rs, r.proc = some i → r.phase ≠ .ready

theorem nr_map {i : Ident} {rs : List Rsrc} {f : Rsrc → Rsrc} (h : NR i rs)
    (hr : ∀ x ∈ rs, (f x).phase = .ready → x.phase = .ready) (hp : ∀ x ∈ rs, (f x).proc = some i → x.proc = some i) :
    NR i (rs.map f) := by
  intro r hr' hi
  obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hr'
  exact fun e => h x hx (hp x hx hi) (hr x hx e)

theorem nr_stop {i : Ident} {s : State} {xs : List Rsrc} (h : NR i s.res) : NR i (stopAll s xs).1.res := by
  show NR i (s.res.map fun x => (stopRec s.now (xs.map (·.id)) x).1)
  exact nr_map h (fun x _ e => stopRec_ready _ _ x e) (fun x _ e => by rw [← (stopRec_same _ _ x).2.2.2]; exact e)

theorem nr_stop_sig {i : Ident} {g : Sig} {s : State} {xs : List Rsrc} (hn : (s.res.filterMap (·.proc)).Nodup)
    (hx : Cmd.signal (.group i) g ∈ (stopAll s xs).2) : NR i (stopAll s xs).1.res := by
  obtain ⟨y, hy, j, hj, hm, hp, e⟩ := stopAll_sig hx
  simp only [Cmd.signal.injEq, Target.group.injEq] at e
  show NR i (s.res.map fun x => (stopRec s.now (xs.map (·.id)) x).1)
  intro r hr hi
  obtain ⟨x, hx', rfl⟩ := List.mem_map.1 hr
  have hxp : x.proc = some i := by rw [← (stopRec_same _ _ x).2.2.2]; exact hi
  have hxy : x = y := eq_of_nodup_filterMap (·.proc) s.res hn x hx' y hy i hxp (by show y.proc = some i; rw [hj, e.1])
  rw [hxy, stopRec_stops hj hm hp]
  intro e2; cases e2

theorem observe_nr {c : Cfg} {s : State} {now : Nat} {smp : Sample} {i : Ident} {g : Sig} (hw : Wf c s)
    (h : Cmd.signal (.group i) g ∈ (observe c s now smp).2) : NR i (observe c s now smp).1.res := by
  unfold observe at h
  dsimp only at h
  rcases List.mem_append.1 h with h | h
  · obtain ⟨x, hx, hm⟩ := List.mem_flatMap.1 h
    obtain ⟨hxi, hnr⟩ := tickRec_grp hm
    rw [observe_res]
    intro r hr hi
    obtain ⟨y, hy, rfl⟩ := List.mem_map.1 hr
    have hyi : y.proc = some i := by
      rcases (tickRec_same c s.leases _ smp y).2 with e | e
      · rw [← e]; exact hi
      · rw [e] at hi; cases hi
    have : y = x := eq_of_nodup_filterMap (·.proc) s.res hw.procs y hy x hx i hyi hxi
    subst this
    exact hnr
  · obtain ⟨_, _, _, e⟩ := cut_cmd h
    cases e

theorem tick_nr {c : Cfg} {s : State} {now : Nat} {smp : Sample} {i : Ident} {g : Sig} (hw : Wf c s)
    (h : Cmd.signal (.group i) g ∈ (tick c s now smp).2) : NR i (tick c s now smp).1.res := by
  have h1 := wf_observe now smp hw
  have h2 := wf_stopAll _ h1 fun _ hx => idle_cands hx
  have hD : ∀ st, NR i st.res → NR i (shedStage c st).1.res := fun st hst => by
    rcases shedStage_eq c st with e | e <;> rw [e]
    · exact nr_stop hst
    · exact hst
  show NR i (shedStage c (idleStage c (observe c s now smp).1).1).1.res
  unfold tick at h
  dsimp only at h
  rcases List.mem_append.1 h with h | h
  · rcases List.mem_append.1 h with h | h
    · rcases List.mem_append.1 h with h | h
      · exact hD _ (nr_stop (observe_nr hw h))
      · exact hD _ (nr_stop_sig h1.procs h)
    · rcases shedStage_eq c (idleStage c (observe c s now smp).1).1 with e | e <;> rw [e] at h ⊢
      · exact nr_stop_sig h2.procs h
      · cases h
  · split at h <;> simp at h

theorem pump_nr {c : Cfg} {s0 : State} {i : Ident} (hw : Wf c s0) (h : NR i s0.res) : NR i (pumpAcc c s0).st.res := by
  obtain ⟨⟨F, hF, hFm⟩, _⟩ := pump_pm hw
  rw [hF]
  refine nr_map h (fun x hx e => ?_) (fun x hx e => by rw [← key_proc (hFm x hx).1]; exact e)
  rcases (hFm x hx).2 with e' | ⟨_, _, e'⟩ | ⟨hr, _⟩
  · rw [← e']; exact e
  · rw [e'] at e; cases e
  · exact hr

theorem request_res (c : Cfg) (s : State) (o : Nat) (a : Ask) : (request c s o a).1.res = s.res := by
  unfold request
  dsimp only
  split
  · split
    · split <;> rfl
    · rfl
  · rfl

/-- The commands of the stage before the pump, by event. -/
theorem pre_out {c : Cfg} {s : State} {e : Event} {x : Cmd} (h : x ∈ (pre c s e).2) :
    (∃ n r, x = .reply n r)
    ∨ (∃ now smp, e = .tick now smp ∧ x ∈ (tick c s now smp).2)
    ∨ (∃ rid i, e = .spawned rid i ∧ (x = .probe rid ∨ ∃ j, i = some j ∧ x = .signal (.group j) .kill ∧
        (∀ r ∈ s.res, r.proc ≠ some j) ∧ (pre c s e).1 = s))
    ∨ (∃ l ∈ s.leases, x = .revoke l.owner l.id)
    ∨ (∃ now snap inp, e = .restart now snap inp ∧
        ((∃ l ∈ snap.leases, x = .revoke l.owner l.id) ∨ ∃ p ∈ Fw.Ops.Reap.plan inp, x = .signal (.reap p) .term)) := by
  cases e with
  | request t o a =>
    simp only [pre, request] at h
    split at h
    · split at h
      · split at h <;> exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
      · exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
    · cases h
  | release t o lid =>
    simp only [pre, release] at h
    split at h <;> exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
  | renew t o lid =>
    simp only [pre, renew] at h
    split at h
    · split at h <;> exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
    · exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
  | op t o => exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
  | drain t o => exact Or.inl ⟨_, _, List.mem_singleton.1 h⟩
  | spawned rid i =>
    cases i with
    | none => simp [pre, spawned] at h
    | some j =>
      refine Or.inr (Or.inr (Or.inl ⟨rid, some j, rfl, ?_⟩))
      simp only [pre] at h ⊢
      simp only [spawned] at h ⊢
      split at h
      · cases h
      · rename_i ha
        split at h
        · exact Or.inl (List.mem_singleton.1 h)
        · rename_i hb
          refine Or.inr ⟨j, rfl, List.mem_singleton.1 h, fun r hr e => ha (List.any_eq_true.2 ⟨r, hr, by simp [e]⟩), ?_⟩
          rw [if_neg ha, if_neg hb]
  | ready rid => cases h
  | childExit i =>
    simp only [pre, childExit] at h
    obtain ⟨l, hl, _, e⟩ := cut_cmd h
    exact Or.inr (Or.inr (Or.inr (Or.inl ⟨l, hl, e⟩)))
  | tick now smp => exact Or.inr (Or.inl ⟨now, smp, rfl, h⟩)
  | clientGone o => cases h
  | restart now snap inp =>
    refine Or.inr (Or.inr (Or.inr (Or.inr ⟨now, snap, inp, rfl, ?_⟩)))
    simp only [pre, recover] at h
    rcases List.mem_append.1 h with h | h
    · obtain ⟨l, hl, e⟩ := List.mem_map.1 h
      exact Or.inl ⟨l, (List.mem_filter.1 hl).1, e.symm⟩
    · obtain ⟨p, hp, e⟩ := List.mem_map.1 h
      exact Or.inr ⟨p, (List.mem_filter.1 hp).1, e.symm⟩

theorem pre_nr {c : Cfg} {s : State} {e : Event} {i : Ident} {g : Sig} (hw : Wf c s)
    (h : Cmd.signal (.group i) g ∈ (pre c s e).2) : NR i (pre c s e).1.res := by
  rcases pre_out h with ⟨_, _, e'⟩ | ⟨now, smp, rfl, h⟩ | ⟨rid, _, rfl, e' | ⟨j, rfl, e', hno, hs⟩⟩ | ⟨_, _, e'⟩ |
      ⟨now, snap, inp, rfl, ⟨_, _, e'⟩ | ⟨_, _, e'⟩⟩
  · cases e'
  · exact tick_nr hw h
  · cases e'
  · simp only [Cmd.signal.injEq, Target.group.injEq] at e'
    rw [hs, e'.1]
    intro r hr hri
    exact absurd hri (hno r hr)
  · cases e'
  · cases e'
  · cases e'

theorem step_nr {c : Cfg} {s : State} {e : Event} {i : Ident} {g : Sig} (h : Inv c s)
    (hx : Cmd.signal (.group i) g ∈ (step c s e).2) : NR i (step c s e).1.res := by
  obtain ⟨ha, hx⟩ := step_mem hx
  have hw := wf_pre e h.1
  rw [step_st ha]
  rcases hx with hx | hx
  · exact pump_nr hw (pre_nr h.1 hx)
  · rcases (pump_pm hw).2 _ hx with ⟨_, _, e'⟩ | ⟨_, _, e', _, _⟩ | ⟨y, hy, j, hj, hph, e'⟩
    · cases e'
    · cases e'
    · simp only [Cmd.signal.injEq, Target.group.injEq] at e'
      have hw' := pj_wf hw (pump_pj hw)
      intro r hr hri
      have : r = y := eq_of_nodup_filterMap (·.proc) _ hw'.procs r hr y hy i hri (by show y.proc = some i; rw [hj, e'.1])
      subst this
      rw [hph]
      intro e2; cases e2

/-- stop_never_leased: after a step that signals a group, no service lease names a resource with that group. -/
theorem stop_never_leased {c : Cfg} {s : State} {e : Event} {i : Ident} {g : Sig} (h : Inv c s)
    (hx : Cmd.signal (.group i) g ∈ (step c s e).2) :
    ∀ r ∈ (step c s e).1.res, r.proc = some i → leasesOn (step c s e).1 r.id = [] := by
  have hnr := step_nr h hx
  have hi := step_inv e h
  intro r hr hri
  apply List.eq_nil_iff_forall_not_mem.2
  intro l hl
  obtain ⟨hl1, hl2⟩ := List.mem_filter.1 hl
  simp only [Bool.and_eq_true, beq_iff_eq] at hl2
  obtain ⟨r', hr', hid, hrd⟩ := (hi.1.svc l hl1 hl2.1).2
  have : r' = r := eq_of_nodup_map (·.id) _ hi.1.rids r' r hr' hr (hid.trans hl2.2)
  subst this
  exact hnr r' hr' hri hrd

theorem adopt_proc (rows : List Fw.Ops.Reap.Row) : ∀ (seen : List Ident) (xs : List Rsrc) (y : Rsrc) (i : Ident),
    y ∈ adopt rows seen xs → y.proc = some i → alive rows i = true
  | _, [], _, _, h, _ => absurd h List.not_mem_nil
  | seen, x :: xs, y, i, hy, hi => by
    unfold adopt at hy
    split at hy
    · rename_i j hj
      split at hy
      · rename_i hc
        rcases List.mem_cons.1 hy with e | hy
        · subst e
          simp only [Bool.and_eq_true] at hc
          have : j = i := Option.some.inj (hj.symm.trans hi)
          subst this
          exact hc.1.2
        · exact adopt_proc rows _ xs y i hy hi
      · rcases List.mem_cons.1 hy with e | hy
        · subst e; simp [adopt.clear] at hi
        · exact adopt_proc rows _ xs y i hy hi
    · rcases List.mem_cons.1 hy with e | hy
      · subst e; simp [adopt.clear] at hi
      · exact adopt_proc rows _ xs y i hy hi

theorem ite_proc {p : Prop} [Decidable p] {a b : Rsrc} (ha : a.proc = b.proc) : (if p then a else b).proc = b.proc := by
  by_cases h : p
  · rw [if_pos h]; exact ha
  · rw [if_neg h]

theorem procs_map {l : List Rsrc} {f : Rsrc → Rsrc} {x : Rsrc} {i : Ident} (hx : x ∈ l.map f) (hi : x.proc = some i)
    (hf : ∀ y ∈ l, (f y).proc = y.proc ∨ (f y).proc = none) : ∃ y ∈ l, y.proc = some i := by
  obtain ⟨y, hy, rfl⟩ := List.mem_map.1 hx
  rcases hf y hy with e | e
  · exact ⟨y, hy, by rw [← e]; exact hi⟩
  · rw [e] at hi; cases hi

theorem tick_procs {c : Cfg} {s : State} {now : Nat} {smp : Sample} {y : Rsrc} {i : Ident}
    (hy : y ∈ (tick c s now smp).1.res) (hp : y.proc = some i) : ∃ x ∈ s.res, x.proc = some i := by
  have hy' : y ∈ (shedStage c (idleStage c (observe c s now smp).1).1).1.res := hy
  rcases shedStage_eq c (idleStage c (observe c s now smp).1).1 with e | e <;> rw [e] at hy'
  · obtain ⟨z, hz, hz'⟩ := stop_procs hy' hp
    obtain ⟨w, hw, hw'⟩ := stop_procs hz hz'
    exact observe_procs hw hw'
  · obtain ⟨w, hw, hw'⟩ := stop_procs hy' hp
    exact observe_procs hw hw'

theorem pre_procs {c : Cfg} {s : State} {e : Event} {x : Rsrc} {i : Ident} (hx : x ∈ (pre c s e).1.res)
    (hi : x.proc = some i) :
    (∃ y ∈ s.res, y.proc = some i) ∨ (∃ rid, e = .spawned rid (some i)) ∨
    (∃ now snap inp, e = .restart now snap inp ∧ alive inp.rows i = true) := by
  cases e with
  | request t o a => exact Or.inl ⟨x, by rw [← request_res c s o a]; exact hx, hi⟩
  | release t o lid =>
    simp only [pre] at hx
    unfold release at hx
    dsimp only at hx
    split at hx
    · exact Or.inl (procs_map hx hi fun y _ => Or.inl (ite_proc rfl))
    · exact Or.inl ⟨x, hx, hi⟩
  | renew t o lid =>
    simp only [pre] at hx
    unfold renew at hx
    dsimp only at hx
    split at hx
    · split at hx <;> exact Or.inl ⟨x, hx, hi⟩
    · exact Or.inl ⟨x, hx, hi⟩
  | op t o => exact Or.inl ⟨x, hx, hi⟩
  | drain t o => exact Or.inl ⟨x, hx, hi⟩
  | spawned rid i' =>
    cases i' with
    | none =>
      simp only [pre, spawned] at hx
      exact Or.inl (procs_map hx hi fun y _ => Or.inl (ite_proc rfl))
    | some j =>
      simp only [pre, spawned] at hx
      split at hx
      · exact Or.inl ⟨x, hx, hi⟩
      · split at hx
        · obtain ⟨y, hy, rfl⟩ := List.mem_map.1 hx
          by_cases hid : (y.id == rid) = true
          · rw [if_pos hid] at hi
            have : j = i := Option.some.inj hi
            exact Or.inr (Or.inl ⟨rid, by rw [this]⟩)
          · rw [if_neg hid] at hi
            exact Or.inl ⟨y, hy, hi⟩
        · exact Or.inl ⟨x, hx, hi⟩
  | ready rid =>
    simp only [pre, readyEv] at hx
    exact Or.inl (procs_map hx hi fun y _ => Or.inl (ite_proc rfl))
  | childExit j =>
    simp only [pre, childExit, cut] at hx
    refine Or.inl (procs_map hx hi fun y _ => ?_)
    split
    · exact Or.inl (exits_same c s.now y).2.2.2
    · exact Or.inl rfl
  | tick now smp => exact Or.inl (tick_procs hx hi)
  | clientGone o => exact Or.inl ⟨x, hx, hi⟩
  | restart now snap inp => exact Or.inr (Or.inr ⟨now, snap, inp, rfl, adopt_proc inp.rows [] _ x i hx hi⟩)

/-- signal_identity: every signal goes to the group of a record of the state before the step, to a group reported by
the same spawn event, to an adopted group whose leader row is in the same restart sample, to a member row of the same
tick sample, or to a reap plan target of the same restart. -/
theorem signal_identity {c : Cfg} {s : State} {e : Event} {t : Target} {g : Sig} (h : Inv c s)
    (hx : Cmd.signal t g ∈ (step c s e).2) :
    (∃ i, t = .group i ∧ ((∃ y ∈ s.res, y.proc = some i) ∨ (∃ rid, e = .spawned rid (some i)) ∨
      (∃ now snap inp, e = .restart now snap inp ∧ alive inp.rows i = true)))
    ∨ (∃ now smp, e = .tick now smp ∧ ∃ r ∈ smp.rows, t = .member r.pid r.start)
    ∨ (∃ now snap inp, e = .restart now snap inp ∧ ∃ p ∈ Fw.Ops.Reap.plan inp, t = .reap p) := by
  obtain ⟨_, hx⟩ := step_mem hx
  rcases hx with hx | hx
  · rcases pre_out hx with ⟨_, _, e'⟩ | ⟨now, smp, rfl, hx⟩ | ⟨rid, _, rfl, e' | ⟨j, rfl, e', _, _⟩⟩ | ⟨_, _, e'⟩ |
        ⟨now, snap, inp, rfl, ⟨_, _, e'⟩ | ⟨p, hp, e'⟩⟩
    · cases e'
    · rcases tick_cmds hx with ⟨y, hy, i, _, hi, e'⟩ | ⟨r, hr, e'⟩ | ⟨_, _, e'⟩ | e'
      · simp only [Cmd.signal.injEq] at e'
        exact Or.inl ⟨i, e'.1, Or.inl ⟨y, hy, hi⟩⟩
      · simp only [Cmd.signal.injEq] at e'
        exact Or.inr (Or.inl ⟨now, smp, rfl, r, hr, e'.1⟩)
      · cases e'
      · cases e'
    · cases e'
    · simp only [Cmd.signal.injEq] at e'
      exact Or.inl ⟨j, e'.1, Or.inr (Or.inl ⟨rid, rfl⟩)⟩
    · cases e'
    · cases e'
    · simp only [Cmd.signal.injEq] at e'
      exact Or.inr (Or.inr ⟨now, snap, inp, rfl, p, hp, e'.1⟩)
  · obtain ⟨⟨F, hF, hFm⟩, hS⟩ := pump_pm (wf_pre e h.1)
    rcases hS _ hx with ⟨_, _, e'⟩ | ⟨_, _, e', _, _⟩ | ⟨y, hy, j, hj, _, e'⟩
    · cases e'
    · cases e'
    · simp only [Cmd.signal.injEq] at e'
      rw [hF] at hy
      obtain ⟨z, hz, rfl⟩ := List.mem_map.1 hy
      rw [key_proc (hFm z hz).1] at hj
      exact Or.inl ⟨j, e'.1, pre_procs hz hj⟩

/-! ## Timeouts and idle stops -/

theorem tick_out_observe {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Cmd} (h : x ∈ (observe c s now smp).2) :
    x ∈ (step c s (.tick now smp)).2 := by
  rw [step_out (e := .tick now smp) rfl]
  refine List.mem_append_left _ ?_
  show x ∈ (tick c s now smp).2
  unfold tick
  dsimp only
  exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ h))

theorem tickRec_out {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Rsrc} {y : Cmd} (hx : x ∈ s.res)
    (h : y ∈ (tickRec c s.leases (max s.now now) smp x).2) : y ∈ (step c s (.tick now smp)).2 := by
  apply tick_out_observe
  unfold observe mapRes
  dsimp only
  exact List.mem_append_left _ (List.mem_flatMap.2 ⟨x, hx, h⟩)

theorem observe_lease {c : Cfg} {s : State} {now : Nat} {smp : Sample} {l : Lease}
    (h : l ∈ (observe c s now smp).1.leases) : l ∈ s.leases := (List.mem_filter.1 h).1

theorem ageRec_term {c : Cfg} {now t : Nat} {z : Rsrc} (hp : z.phase = .stopping t .term) (ht : t + c.killAfter ≤ now) :
    (ageRec c now z).2 = killG z.proc := by
  unfold ageRec
  simp only [hp]
  rw [if_pos ht]

theorem ageRec_start {c : Cfg} {now t : Nat} {z : Rsrc} (hp : z.phase = .starting t) (ht : t + c.startMax ≤ now) :
    ageRec c now z = (crash c now true z, killG z.proc) := by
  unfold ageRec
  simp only [hp]
  rw [if_pos ht]

theorem crash_failed (c : Cfg) (now : Nat) (x : Rsrc) : ∃ u w, (crash c now true x).phase = .failed u w := by
  unfold crash
  dsimp only
  split
  · exact ⟨_, _, rfl⟩
  · exact ⟨_, _, rfl⟩

theorem goneRec_failed {c : Cfg} {now : Nat} {rows : List Fw.Ops.Reap.Row} {z : Rsrc} {u : Nat} {w : Why}
    (hp : z.phase = .failed u w) : goneRec c now rows z = z := by
  unfold goneRec
  split
  · simp [hp, Phase.live]
  · rfl

theorem stopRec_failed {now : Nat} {ids : List Nat} {y : Rsrc} {u : Nat} {w : Why} (hp : y.phase = .failed u w) :
    (stopRec now ids y).1 = y := by
  unfold stopRec
  split
  · rw [if_neg (by simp [hp])]
  · rfl

theorem stop_keep_failed {s : State} {xs : List Rsrc} {y : Rsrc} {u : Nat} {w : Why} (hy : y ∈ s.res)
    (hp : y.phase = .failed u w) : y ∈ (stopAll s xs).1.res :=
  List.mem_map.2 ⟨y, hy, stopRec_failed hp⟩

theorem tickRec_term {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {x : Rsrc} {t : Nat} {i : Ident}
    (hp : x.phase = .stopping t .term) (hi : x.proc = some i) (ht : t + c.killAfter ≤ now) :
    Cmd.signal (.group i) .kill ∈ (tickRec c ls now smp x).2 := by
  simp only [tickRec]
  generalize hx0 : ({ x with foot := footOf smp x.proc, lastUse := _ } : Rsrc) = x0
  have p0 : x0.phase = .stopping t .term := by rw [← hx0]; exact hp
  have i0 : x0.proc = some i := by rw [← hx0]; exact hi
  refine List.mem_append_left _ ?_
  rw [ageRec_term p0 ht, i0]
  exact List.mem_singleton_self _

theorem tickRec_start {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {x : Rsrc} {t : Nat}
    (hp : x.phase = .starting t) (ht : t + c.startMax ≤ now) :
    (∃ u w, (tickRec c ls now smp x).1.phase = .failed u w) ∧
    ∀ i, x.proc = some i → Cmd.signal (.group i) .kill ∈ (tickRec c ls now smp x).2 := by
  simp only [tickRec]
  generalize hx0 : ({ x with foot := footOf smp x.proc, lastUse := _ } : Rsrc) = x0
  have p0 : x0.phase = .starting t := by rw [← hx0]; exact hp
  have pr0 : x0.proc = x.proc := by rw [← hx0]
  rw [ageRec_start p0 ht]
  obtain ⟨u, w, hf⟩ := crash_failed c now x0
  rw [goneRec_failed hf, auditRec_phase]
  refine ⟨⟨u, w, hf⟩, fun i hi => List.mem_append_left _ ?_⟩
  rw [pr0, hi]
  exact List.mem_singleton_self _

theorem tickRec_keep {c : Cfg} {ls : List Lease} {now : Nat} {smp : Sample} {x : Rsrc} {i : Ident}
    (hp : x.phase = .ready) (hi : x.proc = some i) (ha : x.adopted = false ∨ alive smp.rows i = true)
    (hl : ∀ l ∈ ls, l.kind = .svc → l.rid ≠ x.id) :
    (tickRec c ls now smp x).1.phase = .ready ∧ (tickRec c ls now smp x).1.proc = some i ∧
    (tickRec c ls now smp x).1.kind = x.kind ∧ (tickRec c ls now smp x).1.id = x.id ∧
    (tickRec c ls now smp x).1.lastUse = x.lastUse := by
  have hn : (ls.any fun l => l.kind == .svc && l.rid == x.id) = false := by
    cases e : ls.any fun l => l.kind == .svc && l.rid == x.id
    · rfl
    · obtain ⟨l, hl', e2⟩ := List.any_eq_true.1 e
      simp only [Bool.and_eq_true, beq_iff_eq] at e2
      exact absurd e2.2 (hl l hl' e2.1)
  simp only [tickRec]
  generalize hx0 : ({ x with foot := footOf smp x.proc, lastUse := _ } : Rsrc) = x0
  have p0 : x0.phase = .ready := by rw [← hx0]; exact hp
  have i0 : x0.proc = some i := by rw [← hx0]; exact hi
  have a0 : x0.adopted = false ∨ alive smp.rows i = true := by rw [← hx0]; exact ha
  have u0 : x0.lastUse = x.lastUse := by rw [← hx0]; dsimp only; rw [hn]; rfl
  have k0 : x0.kind = x.kind ∧ x0.id = x.id := by rw [← hx0]; exact ⟨rfl, rfl⟩
  have e1 : (ageRec c now x0).1 = x0 := by unfold ageRec; simp only [p0]
  have e2 : goneRec c now smp.rows x0 = x0 := by
    unfold goneRec
    rw [i0]
    rcases a0 with a | a <;> simp [a, p0, Phase.live]
  have e3 : auditRec smp.rows x0 = (x0, []) := by
    unfold auditRec
    rw [i0]
    simp [p0, Phase.live]
  rw [e1, e2, e3]
  exact ⟨p0, i0, k0.1, k0.2, u0⟩

/-- stop_escalates: a TERM older than `killAfter` at the tick time is escalated to a KILL of the group. -/
theorem stop_escalates {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Rsrc} {t : Nat} {i : Ident}
    (hx : x ∈ s.res) (hp : x.phase = .stopping t .term) (hi : x.proc = some i) (ht : t + c.killAfter ≤ now) :
    Cmd.signal (.group i) .kill ∈ (step c s (.tick now smp)).2 :=
  tickRec_out hx (tickRec_term hp hi (Nat.le_trans ht (Nat.le_max_right _ _)))

/-- start_bounded: a start older than `startMax` at the tick time fails the record and KILLs its group. -/
theorem start_bounded {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Rsrc} {t : Nat} (h : Inv c s)
    (hx : x ∈ s.res) (hp : x.phase = .starting t) (ht : t + c.startMax ≤ now) :
    (∃ y ∈ (step c s (.tick now smp)).1.res, y.id = x.id ∧ ∃ u w, y.phase = .failed u w) ∧
    ∀ i, x.proc = some i → Cmd.signal (.group i) .kill ∈ (step c s (.tick now smp)).2 := by
  have ht' : t + c.startMax ≤ max s.now now := Nat.le_trans ht (Nat.le_max_right _ _)
  obtain ⟨⟨u, w, hf⟩, hk⟩ := tickRec_start (ls := s.leases) (smp := smp) hp ht'
  refine ⟨?_, fun i hi => tickRec_out hx (hk i hi)⟩
  have hw := wf_pre (.tick now smp) h.1
  rw [step_st (e := .tick now smp) rfl]
  obtain ⟨⟨F, hF, hFm⟩, _⟩ := pump_pm hw
  rw [hF]
  have d0 := (tickRec_same c s.leases (max s.now now) smp x).1
  have h1 : (tickRec c s.leases (max s.now now) smp x).1 ∈ (observe c s now smp).1.res := by
    rw [observe_res]; exact List.mem_map_of_mem hx
  generalize (tickRec c s.leases (max s.now now) smp x).1 = y0 at h1 hf d0
  have h2 : y0 ∈ (tick c s now smp).1.res := by
    show y0 ∈ (shedStage c (idleStage c (observe c s now smp).1).1).1.res
    have hb : y0 ∈ (idleStage c (observe c s now smp).1).1.res := stop_keep_failed h1 hf
    rcases shedStage_eq c (idleStage c (observe c s now smp).1).1 with e | e <;> rw [e]
    · exact stop_keep_failed hb hf
    · exact hb
  refine ⟨F y0, List.mem_map_of_mem h2, ?_, u, w, ?_⟩
  · rw [key_id (hFm y0 h2).1, d0]
  · rcases (hFm y0 h2).2 with e | ⟨e, _⟩ | ⟨e, _⟩
    · rw [e]; exact hf
    · rw [hf] at e; cases e
    · rw [hf] at e; cases e

/-- idle_stopped: a ready, unpinned, unleased resource with a live group, unused for its kind's grace at the tick time,
gets a TERM to its group on that tick. -/
theorem idle_stopped {c : Cfg} {s : State} {now : Nat} {smp : Sample} {x : Rsrc} {i : Ident} (hx : x ∈ s.res)
    (hp : x.phase = .ready) (hi : x.proc = some i) (hpin : c.pinned x.kind = false)
    (ha : x.adopted = false ∨ alive smp.rows i = true) (hl : ∀ l ∈ s.leases, l.kind = .svc → l.rid ≠ x.id)
    (hg : x.lastUse + c.grace x.kind ≤ now) :
    Cmd.signal (.group i) .term ∈ (step c s (.tick now smp)).2 := by
  obtain ⟨p1, i1, k1, d1, u1⟩ := tickRec_keep (c := c) (now := max s.now now) (smp := smp) hp hi ha hl
  have hy : (tickRec c s.leases (max s.now now) smp x).1 ∈ (observe c s now smp).1.res := by
    rw [observe_res]; exact List.mem_map_of_mem hx
  generalize (tickRec c s.leases (max s.now now) smp x).1 = y at p1 i1 k1 d1 u1 hy
  have hn : leasesOn (observe c s now smp).1 y.id = [] := List.eq_nil_iff_forall_not_mem.2 fun l hl' => by
    obtain ⟨hl1, hl2⟩ := List.mem_filter.1 hl'
    simp only [Bool.and_eq_true, beq_iff_eq] at hl2
    exact hl l (observe_lease hl1) hl2.1 (hl2.2.trans d1)
  have hc : y ∈ idle c (observe c s now smp).1 := by
    refine List.mem_filter.2 ⟨List.mem_filter.2 ⟨hy, ?_⟩, ?_⟩
    · simp [p1, i1, k1, hpin, hn]
    · show decide (y.lastUse + c.grace y.kind ≤ max s.now now) = true
      rw [u1, k1]
      exact decide_eq_true (Nat.le_trans hg (Nat.le_max_right _ _))
  rw [step_out (e := .tick now smp) rfl]
  refine List.mem_append_left _ ?_
  show _ ∈ (tick c s now smp).2
  unfold tick
  dsimp only
  exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ (stopAll_emits hy hc p1 i1)))

end Fw.Sup
