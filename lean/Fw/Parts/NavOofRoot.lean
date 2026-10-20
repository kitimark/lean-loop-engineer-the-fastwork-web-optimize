/-!
# The layout root of a dirty out-of-flow box ignores every boundary below its containing block
Note: `research/notes/2026/10-20-nav-oof-root-finding.md`.
-/

namespace Fw.Parts.NavOofRoot

/-- A layout tree numbered so that a container or containing block has a smaller number than its object; object 0
is the view. `boundary` arguments elsewhere are the engine's relayout-boundary test per object. -/
structure Tree where
  container : Nat → Option Nat
  containingBlock : Nat → Option Nat
  oof : Nat → Bool
  container_lt : ∀ a p, container a = some p → p < a
  containingBlock_lt : ∀ a p, containingBlock a = some p → p < a

def view : Nat := 0

/-- The layout pass a dirty object schedules: the whole view, or a subtree root. -/
inductive Pass where
  | full
  | subtree (root : Nat)
deriving DecidableEq, Repr

namespace Tree

/-- The object the marking walk visits after `a`: the containing block when `a` is out of flow, else the container. -/
def next (t : Tree) (a : Nat) : Option Nat :=
  if t.oof a then t.containingBlock a else t.container a

theorem next_lt (t : Tree) (a p : Nat) (h : t.next a = some p) : p < a := by
  unfold next at h
  split at h
  · exact t.containingBlock_lt a p h
  · exact t.container_lt a p h

/-- The first object from `a` upward that is a boundary, or the top of the chain. -/
def climb (t : Tree) (boundary : Nat → Bool) (a : Nat) : Nat :=
  if boundary a then a
  else
    match t.next a, t.next_lt a with
    | none, _ => a
    | some p, hp =>
      have : p < a := hp p rfl
      t.climb boundary p
termination_by a

/-- The root a dirty `x` schedules: the walk starts at `next x` and never tests `x` itself. -/
def layoutRoot (t : Tree) (boundary : Nat → Bool) (x : Nat) : Nat :=
  match t.next x with
  | none => x
  | some a => t.climb boundary a

def pass (t : Tree) (boundary : Nat → Bool) (x : Nat) : Pass :=
  let r := t.layoutRoot boundary x
  if r = view then .full else .subtree r

theorem next_oof (t : Tree) (a : Nat) (h : t.oof a = true) : t.next a = t.containingBlock a := by
  simp [next, h]

theorem next_flow (t : Tree) (a : Nat) (h : t.oof a = false) : t.next a = t.container a := by
  simp [next, h]

theorem next_view (t : Tree) : t.next view = none := by
  cases h : t.next view with
  | none => rfl
  | some p => exact absurd (t.next_lt view p h) (Nat.not_lt_zero p)

theorem climb_stop (t : Tree) (boundary : Nat → Bool) (a : Nat) (h : boundary a = true) :
    t.climb boundary a = a := by
  rw [climb]; simp [h]

theorem climb_top (t : Tree) (boundary : Nat → Bool) (a : Nat) (hb : boundary a = false)
    (hn : t.next a = none) : t.climb boundary a = a := by
  rw [climb]; simp [hb]; split <;> simp_all

theorem climb_step (t : Tree) (boundary : Nat → Bool) (a p : Nat) (hb : boundary a = false)
    (hn : t.next a = some p) : t.climb boundary a = t.climb boundary p := by
  rw [climb]; simp [hb]; split <;> simp_all

theorem climb_view (t : Tree) (boundary : Nat → Bool) : t.climb boundary view = view := by
  cases hb : boundary view
  · exact t.climb_top boundary view hb t.next_view
  · exact t.climb_stop boundary view hb

theorem climb_below (t : Tree) (boundary boundary' : Nat → Bool) (x : Nat)
    (h : ∀ a, a < x → boundary a = boundary' a) :
    ∀ a, a < x → t.climb boundary a = t.climb boundary' a := by
  intro a
  induction a using Nat.strongRecOn with
  | ind a ih =>
    intro ha
    cases hb : boundary a
    · have hb' : boundary' a = false := (h a ha) ▸ hb
      cases hn : t.next a with
      | none => rw [t.climb_top _ a hb hn, t.climb_top _ a hb' hn]
      | some p =>
        have hp := t.next_lt a p hn
        rw [t.climb_step _ a p hb hn, t.climb_step _ a p hb' hn]
        exact ih p hp (Nat.lt_trans hp ha)
    · have hb' : boundary' a = true := (h a ha) ▸ hb
      rw [t.climb_stop _ a hb, t.climb_stop _ a hb']

/-- The root never depends on whether `x` itself is a boundary. -/
theorem layoutRoot_skips_self (t : Tree) (boundary : Nat → Bool) (x : Nat) (b : Bool) :
    t.layoutRoot (fun a => if a = x then b else boundary a) x = t.layoutRoot boundary x := by
  unfold layoutRoot
  cases hn : t.next x with
  | none => rfl
  | some p =>
    exact t.climb_below _ _ x (fun a ha => by simp [Nat.ne_of_lt ha]) p (t.next_lt x p hn)

theorem oof_root_indep (t : Tree) (boundary : Nat → Bool) (x c : Nat) (h : t.oof x = true)
    (hc : t.containingBlock x = some c) : t.layoutRoot boundary x = t.climb boundary c := by
  simp [layoutRoot, t.next_oof x h, hc]

theorem flow_root (t : Tree) (boundary : Nat → Bool) (x c : Nat) (h : t.oof x = false)
    (hc : t.container x = some c) : t.layoutRoot boundary x = t.climb boundary c := by
  simp [layoutRoot, t.next_flow x h, hc]

theorem oof_view_root (t : Tree) (x : Nat) (h : t.oof x = true) (hc : t.containingBlock x = some view) :
    ∀ boundary, t.layoutRoot boundary x = view := by
  intro boundary
  rw [t.oof_root_indep boundary x view h hc, t.climb_view]

theorem oof_view_full (t : Tree) (x : Nat) (h : t.oof x = true) (hc : t.containingBlock x = some view) :
    ∀ boundary, t.pass boundary x = .full := by
  intro boundary
  simp [pass, t.oof_view_root x h hc boundary]

theorem flow_boundary_subtree (t : Tree) (boundary : Nat → Bool) (x c : Nat) (h : t.oof x = false)
    (hc : t.container x = some c) (hb : boundary c = true) (hv : c ≠ view) :
    t.pass boundary x = .subtree c := by
  simp [pass, t.flow_root boundary x c h hc, t.climb_stop boundary c hb, hv]

/-- The first ancestor of `a`, from its container upward, for which `holds` is true, or the top of the chain. -/
def nearest (t : Tree) (holds : Nat → Bool) (a : Nat) : Nat :=
  match t.container a, t.container_lt a with
  | none, _ => a
  | some p, hp =>
    have : p < a := hp p rfl
    if holds p then p else t.nearest holds p
termination_by a

theorem nearest_top (t : Tree) (holds : Nat → Bool) (a : Nat) (h : t.container a = none) :
    t.nearest holds a = a := by
  rw [nearest]; split <;> simp_all

theorem nearest_hit (t : Tree) (holds : Nat → Bool) (a p : Nat) (h : t.container a = some p)
    (hp : holds p = true) : t.nearest holds a = p := by
  rw [nearest]; split <;> simp_all

theorem nearest_step (t : Tree) (holds : Nat → Bool) (a p : Nat) (h : t.container a = some p)
    (hp : holds p = false) : t.nearest holds a = t.nearest holds p := by
  rw [nearest]; split <;> simp_all

theorem nearest_le (t : Tree) (holds : Nat → Bool) (a : Nat) : t.nearest holds a ≤ a := by
  induction a using Nat.strongRecOn with
  | ind a ih =>
    cases h : t.container a with
    | none => rw [t.nearest_top holds a h]; exact Nat.le_refl a
    | some p =>
      have hp := t.container_lt a p h
      cases hh : holds p
      · rw [t.nearest_step holds a p h hh]; exact Nat.le_trans (ih p hp) (Nat.le_of_lt hp)
      · rw [t.nearest_hit holds a p h hh]; exact Nat.le_of_lt hp

theorem nearest_lt (t : Tree) (holds : Nat → Bool) (a p : Nat) (h : t.container a = some p) :
    t.nearest holds a < a := by
  cases hh : holds p
  · rw [t.nearest_step holds a p h hh]
    exact Nat.lt_of_le_of_lt (t.nearest_le holds p) (t.container_lt a p h)
  · rw [t.nearest_hit holds a p h hh]; exact t.container_lt a p h

/-- The same tree with each out-of-flow object's containing block recomputed as its nearest `fixedContainer`. -/
def fixedCb (t : Tree) (fixedContainer : Nat → Bool) : Tree where
  container := t.container
  containingBlock a :=
    if t.oof a then (t.container a).map (fun _ => t.nearest fixedContainer a) else t.containingBlock a
  oof := t.oof
  container_lt := t.container_lt
  containingBlock_lt a p h := by
    split at h
    · cases hc : t.container a with
      | none => simp [hc] at h
      | some q => simp [hc] at h; exact h ▸ t.nearest_lt fixedContainer a q hc
    · exact t.containingBlock_lt a p h

theorem fixedCb_oof (t : Tree) (fc : Nat → Bool) (a q : Nat) (h : t.oof a = true) (hc : t.container a = some q) :
    (t.fixedCb fc).containingBlock a = some (t.nearest fc a) := by
  simp [fixedCb, h, hc]

theorem fixedCb_flow (t : Tree) (fc : Nat → Bool) (a : Nat) (h : t.oof a = false) :
    (t.fixedCb fc).containingBlock a = t.containingBlock a := by
  simp [fixedCb, h]

/-- A partial pass from a dirty out-of-flow `x` means its containing block is no longer the view. -/
theorem fixedCb_partial_moved (t : Tree) (fc boundary : Nat → Bool) (x q r : Nat) (h : t.oof x = true)
    (hc : t.container x = some q) (hp : (t.fixedCb fc).pass boundary x = .subtree r) :
    t.nearest fc x ≠ view := by
  intro hv
  have hcb : (t.fixedCb fc).containingBlock x = some view := hv ▸ t.fixedCb_oof fc x q h hc
  rw [(t.fixedCb fc).oof_view_full x h hcb boundary] at hp
  exact Pass.noConfusion hp

theorem fixedCb_boundary_root (t : Tree) (fc boundary : Nat → Bool) (x q : Nat) (h : t.oof x = true)
    (hc : t.container x = some q) (hb : boundary (t.nearest fc x) = true) (hv : t.nearest fc x ≠ view) :
    (t.fixedCb fc).pass boundary x = .subtree (t.nearest fc x) := by
  simp [pass, (t.fixedCb fc).oof_root_indep boundary x _ h (t.fixedCb_oof fc x q h hc),
    (t.fixedCb fc).climb_stop boundary _ hb, hv]

end Tree

/-- The nav's chain: 1 html, 2 body, 3 the React root, 4 the fixed nav, 5 its bar, 6 page-root, 7 main. -/
def navContainer : Nat → Option Nat
  | 1 => some 0 | 2 => some 1 | 3 => some 2 | 4 => some 3 | 5 => some 4 | 6 => some 3 | 7 => some 6 | _ => none

def navContainingBlock : Nat → Option Nat
  | 4 => some 0 | a => navContainer a

def navTree (_ : Unit := ()) : Tree where
  container := navContainer
  containingBlock := navContainingBlock
  oof a := a == 4
  container_lt a p h := by
    unfold navContainer at h; split at h <;> simp_all <;> omega
  containingBlock_lt a p h := by
    unfold navContainingBlock navContainer at h; split at h <;> (try split at h) <;> simp_all <;> omega

def nav : Nat := 4

theorem nav_pass_full : ∀ boundary, (navTree ()).pass boundary nav = .full :=
  (navTree ()).oof_view_full nav rfl rfl

/-- The nav tree when every relayout boundary is also a fixed containing block, as layout and paint containment are. -/
def navContained (boundary : Nat → Bool) : Tree := (navTree ()).fixedCb boundary

theorem nav_contained_partial_moved (boundary : Nat → Bool) (r : Nat)
    (h : (navContained boundary).pass boundary nav = .subtree r) :
    (navContained boundary).containingBlock nav ≠ some view := by
  unfold navContained
  rw [(navTree ()).fixedCb_oof boundary nav 3 rfl rfl]
  intro hv
  exact (navTree ()).fixedCb_partial_moved boundary boundary nav 3 r rfl rfl h (Option.some.inj hv)

theorem nav_contained_root (boundary : Nat → Bool) (h : boundary 3 = true) :
    (navContained boundary).pass boundary nav = .subtree 3 := by
  unfold navContained
  have hn : (navTree ()).nearest boundary nav = 3 := (navTree ()).nearest_hit boundary nav 3 rfl h
  have := (navTree ()).fixedCb_boundary_root boundary boundary nav 3 rfl rfl (hn ▸ h) (by rw [hn]; decide)
  rwa [hn] at this

#guard (navTree ()).next nav == some view
#guard (navTree ()).next 5 == some nav
#guard (navTree ()).next view == none
#guard (navTree ()).layoutRoot (fun _ => true) nav == view
#guard (navTree ()).layoutRoot (· == nav) nav == view
#guard (navTree ()).layoutRoot (· == 3) nav == view
#guard (navTree ()).layoutRoot (fun _ => false) nav == view
#guard (navTree ()).pass (fun _ => true) nav == .full
#guard (navTree ()).pass (· == nav) 5 == .subtree nav
#guard (navTree ()).pass (· == 6) 7 == .subtree 6
#guard (navTree ()).pass (fun _ => false) 7 == .full
#guard (navTree ()).climb (· == 3) 7 == 3
#guard (navContained (· == 3)).containingBlock nav == some 3
#guard (navContained (· == 3)).pass (· == 3) nav == .subtree 3
#guard (navContained (· == 1)).pass (· == 1) nav == .subtree 1
#guard (navContained (· == nav)).containingBlock nav == some view
#guard (navContained (· == nav)).pass (· == nav) nav == .full
#guard (navContained (fun _ => false)).pass (fun _ => false) nav == .full
#guard (navContained (· == 6)).pass (· == 6) nav == .full
#guard (navContained (· == 6)).pass (· == 6) 7 == .subtree 6

end Fw.Parts.NavOofRoot
