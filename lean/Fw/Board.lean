import Fw.Console
/-!
# The board: a projection of the console state (every field derived, nothing stored)

Ported from console-mvp's `apps/console-api/src/core/board.ts` so status derivation runs in Lean
(`fwcore console.board`). Strings are the exact ones the TypeScript stand-in produced.
-/
namespace Fw.Console

/-- A card counts as stale after 30 minutes without an event (ms). -/
def staleMs : Nat := 30 * 60 * 1000

/-- Who must act next on a card, and the typed command they send, by stage. -/
def next (c : Card) : Stage → String × String
  | .question => ("lead or user", "card.approve")
  | .build => ("owner " ++ c.owner, "commit (git fact card.build)")
  | .screen => ("script", "card.screen")
  | .review => ("reviewer (not the owner or a builder)", "card.review")
  | .device => ("script (device swipe)", "card.swipe")
  | .land_ready =>
    if c.landReq == c.head then ("git", "card.landed (fact)") else ("lead or user", "card.land_request")
  | .land => ("nobody", "done")

/-- The exact action the user must take on a step (first match wins). -/
def stepAction (s : Step) : String :=
  if s.status = .waiting && s.kind = .action then "Press Start"
  else if s.status = .started && s.kind = .action then "Do it, then press Done"
  else if s.kind = .yes_no then "Answer yes or no"
  else if s.kind = .choice then "Choose one: " ++ " | ".intercalate (s.options.getD [])
  else if s.kind = .text then "Type an answer"
  else "Press Done"

/-- A needs-you entry: the step, its title and the exact action. -/
structure NeedsYou where
  step   : String
  title  : String
  action : String
deriving Repr, DecidableEq

/-- The needs-you entry of a step. -/
def needs (s : Step) : NeedsYou := ⟨s.id, s.title, stepAction s⟩

/-- One board row, every field derived from the card, its steps and its runs. -/
structure BoardCard where
  id          : String
  owner       : String
  stage       : Stage
  next        : String × String
  lastAt      : Nat
  needsYou    : Option NeedsYou
  runningRuns : Nat
  head        : Option String
  landed      : Bool
  violation   : Bool
  stale       : Bool
deriving Repr, DecidableEq

/-- The board row of card `c` at time `now`: its first open step (if any) is what it needs from
you; it is stale only when it has not landed, no run on it is running, no step on it is open and
no event came for `staleMs`.
-/
def boardCard (s : State) (now : Nat) (c : Card) : BoardCard :=
  let st := stage c
  let mine := s.steps.find? (fun x => x.status.isOpen && x.card == some c.id)
  let running := (s.runs.filter (fun r => r.card == c.id && r.status == .running)).length
  { id := c.id, owner := c.owner, stage := st, next := next c st, lastAt := c.lastAt,
    needsYou := mine.map needs, runningRuns := running, head := c.head, landed := c.landed,
    violation := c.violation,
    stale := !c.landed && running == 0 && mine.isNone && decide (staleMs ≤ now - c.lastAt) }

/-- The board: the sequence number and server clock it was computed at, one row per card (in
card order), all steps, and the needs-you list (every open step, in step order); `board` computes it.
-/
structure Board where
  seq      : Nat
  now      : Nat
  cards    : List BoardCard
  steps    : List Step
  needsYou : List NeedsYou

/-- Compute the board (see `Board`). -/
def board (s : State) (now seq : Nat) : Board :=
  { seq, now, cards := s.cards.map (boardCard s now), steps := s.steps,
    needsYou := (s.steps.filter (·.status.isOpen)).map needs }

#guard
  let s := project [⟨"k1", 1, .owner, .cardOpen "A" "o" false⟩, ⟨"k2", 2, .lead, .cardApprove "A"⟩,
                    ⟨"k3", 3, .git, .cardBuild "A" "s1" "b"⟩,
                    ⟨"k4", 4, .script, .stepPost "S" (some "A") "Plug in" .action none⟩]
  let b := board s 5000 9
  (b.cards.map (fun r => (r.stage, r.next.2, r.needsYou.map (·.action), r.stale)))
    == [(.screen, "card.screen", some "Press Start", false)]
  && ((board (project (s.steps.map (fun _ => ⟨"z", 0, .hook, .stepDone "S"⟩))) 0 0).cards.length == 0)
  && ((board { s with steps := [] } (3 + staleMs) 0).cards.map (·.stale)) == [true]

/-- A landed card is never stale. -/
theorem landed_not_stale (s : State) (now : Nat) (c : Card) (h : c.landed = true) :
    (boardCard s now c).stale = false := by
  simp [boardCard, h]

/-- A card with a running run is never stale (a live wait is not staleness). -/
theorem running_not_stale (s : State) (now : Nat) (c : Card) (r : Run) (hr : r ∈ s.runs)
    (hc : r.card = c.id) (hs : r.status = .running) : (boardCard s now c).stale = false := by
  have hpos : 0 < (s.runs.filter (fun r => r.card == c.id && r.status == .running)).length :=
    List.length_pos_of_mem (List.mem_filter.mpr ⟨hr, by simp [hc, hs]⟩)
  have h0 : ((s.runs.filter (fun r => r.card == c.id && r.status == .running)).length == 0) = false := by
    simp only [beq_eq_false_iff_ne, ne_eq]; omega
  simp only [boardCard, h0, Bool.and_false, Bool.false_and]

/-- The row's stage is `stage` of the card, so a row says "land" exactly when the card landed. -/
theorem row_land_iff (s : State) (now : Nat) (c : Card) :
    (boardCard s now c).stage = .land ↔ c.landed = true := by
  simp only [boardCard, stage]
  cases c.landed <;> simp <;> (repeat' split) <;> simp

/-- Every needs-you entry comes from an open step. -/
theorem needsYou_open (s : State) (now seq : Nat) (n : NeedsYou)
    (h : n ∈ (board s now seq).needsYou) :
    ∃ st ∈ s.steps, st.status.isOpen = true ∧ n = needs st := by
  simp only [board, List.mem_map, List.mem_filter] at h
  obtain ⟨st, ⟨hm, ho⟩, rfl⟩ := h
  exact ⟨st, hm, ho, rfl⟩

end Fw.Console
