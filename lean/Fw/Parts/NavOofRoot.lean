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

end Fw.Parts.NavOofRoot
