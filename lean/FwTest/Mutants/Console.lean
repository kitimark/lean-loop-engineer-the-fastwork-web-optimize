import Fw.Console

/-! # Mutant killers for `Fw.Console` (task m0-mutants)

Golden cases that pin every refusal branch of the reducer, the actor table, the names on the wire,
the transition effects of each accepted body, `stage`, `ready`, `touch` and `stale`. Each block
names the surviving mechanical mutants (`line:col:op`) of the round-1 run it kills. -/

namespace FwTest.Mutants.Console
open Fw.Console

/-- An event with key `k`, time `t`, actor `a` and body `b`. -/
def ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩

/-- The outcome of event `e` after replaying `log`. -/
def out (log : List Event) (e : Event) : Outcome := (step (project log) e).2

/-- Card `A` (owner `o`, no device) opened at time 1. -/
def opened : List Event := [ev "a1" 1 .owner (.cardOpen "A" "o" false)]
/-- `opened`, approved at 2 and built as `s1` by `b` at 3. -/
def built : List Event := opened ++ [ev "a2" 2 .lead (.cardApprove "A"), ev "a3" 3 .git (.cardBuild "A" "s1" "b")]
/-- `built`, screened and reviewed (by `r`) at `s1`: land-ready. -/
def readyLog : List Event :=
  built ++ [ev "a4" 4 .script (.cardScreen "A" "s1" true), ev "a5" 5 .reviewer (.cardReview "A" "s1" "r" true)]
/-- `built`, then observed landed at `s1` without a request. -/
def landedLog : List Event := built ++ [ev "a9" 9 .git (.cardLanded "A" "s1")]

/-- The refusal reason `w`. -/
abbrev no (w : String) : Outcome := .refused w
/-- Accepted, not a duplicate. -/
abbrev yes : Outcome := .accepted false

-- names on the wire (kills Actor.name / StepStatus.name / EvType.name `str` mutants)
#guard [Actor.user, .lead, .owner, .reviewer, .script, .git, .hook].map Actor.name
  == ["user", "lead", "owner", "reviewer", "script", "git", "hook"]
#guard [StepStatus.waiting, .started, .answered, .done, .cancelled].map StepStatus.name
  == ["waiting", "started", "answered", "done", "cancelled"]
#guard [EvType.cardOpen, .cardApprove, .cardBuild, .cardScreen, .cardReview, .cardSwipe, .cardLandRequest,
    .cardLanded, .stepPost, .stepStart, .stepAnswer, .stepDone, .stepCancel, .runStart, .runFinish].map EvType.name
  == ["card.open", "card.approve", "card.build", "card.screen", "card.review", "card.swipe", "card.land_request",
      "card.landed", "step.post", "step.start", "step.answer", "step.done", "step.cancel", "run.start", "run.finish"]

-- the MAY table, as the set of allowed actors per type
#guard
  let all := [Actor.user, .lead, .owner, .reviewer, .script, .git, .hook]
  let types := [EvType.cardOpen, .cardApprove, .cardBuild, .cardScreen, .cardReview, .cardSwipe, .cardLandRequest,
    .cardLanded, .stepPost, .stepStart, .stepAnswer, .stepDone, .stepCancel, .runStart, .runFinish]
  types.map (fun t => all.filter (may · t)) ==
    [[.user, .lead, .owner], [.user, .lead], [.git], [.script], [.reviewer], [.script], [.user, .lead], [.git],
     [.lead, .owner, .script], [.user], [.user], [.user, .owner, .script], [.user, .lead, .script],
     [.lead, .owner, .script], [.script]]

-- card refusals, branch by branch
#guard out opened (ev "x" 5 .lead (.cardApprove "A")) == yes
#guard out (opened ++ [ev "a2" 2 .lead (.cardApprove "A")]) (ev "x" 5 .lead (.cardApprove "A")) == no "already approved"
#guard out landedLog (ev "x" 10 .lead (.cardApprove "A")) == no "card already landed"
#guard out landedLog (ev "x" 10 .git (.cardBuild "A" "s2" "b")) == no "card already landed"
#guard out built (ev "x" 10 .git (.cardBuild "A" "s2" "b")) == yes
#guard out landedLog (ev "x" 10 .script (.cardScreen "A" "s1" true)) == no "card already landed"
#guard out built (ev "x" 10 .script (.cardScreen "A" "s0" true)) == no "stale sha: not the head commit"
#guard out built (ev "x" 10 .script (.cardScreen "A" "s1" false)) == no "failed screen does not advance the card"
#guard out built (ev "x" 10 .script (.cardScreen "A" "s1" true)) == yes
#guard out landedLog (ev "x" 10 .reviewer (.cardReview "A" "s1" "r" true)) == no "card already landed"
#guard out built (ev "x" 10 .reviewer (.cardReview "A" "s0" "r" true)) == no "stale sha: not the head commit"
#guard out built (ev "x" 10 .reviewer (.cardReview "A" "s1" "o" true)) == no "reviewer owns or built this card"
#guard out built (ev "x" 10 .reviewer (.cardReview "A" "s1" "b" true)) == no "reviewer owns or built this card"
#guard out built (ev "x" 10 .reviewer (.cardReview "A" "s1" "r" false)) == no "rejected review does not advance the card"
#guard out built (ev "x" 10 .reviewer (.cardReview "A" "s1" "r" true)) == yes
#guard out landedLog (ev "x" 10 .script (.cardSwipe "A" "s1" true)) == no "card already landed"
#guard out built (ev "x" 10 .script (.cardSwipe "A" "s0" true)) == no "stale sha: not the head commit"
#guard out built (ev "x" 10 .script (.cardSwipe "A" "s1" false)) == no "not better: device evidence not recorded"
#guard out built (ev "x" 10 .script (.cardSwipe "A" "s1" true)) == yes
#guard out landedLog (ev "x" 10 .lead (.cardLandRequest "A" "s1")) == no "card already landed"
#guard out readyLog (ev "x" 10 .lead (.cardLandRequest "A" "s0")) == no "stale sha: not the head commit"
#guard out built (ev "x" 10 .lead (.cardLandRequest "A" "s1")) == no "card is not land-ready"
#guard out readyLog (ev "x" 10 .lead (.cardLandRequest "A" "s1")) == yes
#guard out landedLog (ev "x" 10 .git (.cardLanded "A" "s1")) == no "card already landed"
#guard out built (ev "x" 10 .git (.cardLanded "A" "s9")) == yes
#guard out built (ev "x" 10 .git (.cardLanded "B" "s1")) == no "no such card"
#guard out built (ev "x" 10 .hook (.cardOpen "B" "o" false)) == no "actor hook may not cause card.open"
#guard out built (ev "x" 10 .owner (.cardOpen "A" "o" false)) == no "card exists"

-- step refusals
/-- Card `A` plus a yes/no step `S`, a choice step `C` (options a, b) and an action step `T`. -/
def steps : List Event := opened ++
  [ev "s1" 2 .script (.stepPost "S" (some "A") "q" .yes_no none),
   ev "s2" 3 .script (.stepPost "C" none "c" .choice (some ["a", "b"])),
   ev "s3" 4 .script (.stepPost "T" none "t" .action none)]
#guard out steps (ev "x" 5 .script (.stepPost "S" none "q" .text none)) == no "step exists"
#guard out steps (ev "x" 5 .script (.stepPost "N" (some "Z") "q" .text none)) == no "no such card"
#guard out steps (ev "x" 5 .script (.stepPost "N" (some "A") "q" .text none)) == yes
#guard out steps (ev "x" 5 .script (.stepPost "N" none "q" .choice (some ["a"]))) == no "choice step needs at least 2 options"
#guard out steps (ev "x" 5 .script (.stepPost "N" none "q" .choice none)) == no "choice step needs at least 2 options"
#guard out steps (ev "x" 5 .script (.stepPost "N" none "q" .choice (some ["a", "b"]))) == yes
#guard out steps (ev "x" 5 .user (.stepStart "Z")) == no "no such step"
#guard out steps (ev "x" 5 .user (.stepStart "S")) == yes
#guard out (steps ++ [ev "x" 5 .user (.stepStart "S")]) (ev "y" 6 .user (.stepStart "S")) == no "step is started, not waiting"
#guard out (steps ++ [ev "x" 5 .user (.stepAnswer "S" "no")]) (ev "y" 6 .user (.stepStart "S")) == no "step is answered, not waiting"
#guard out (steps ++ [ev "x" 5 .user (.stepCancel "S")]) (ev "y" 6 .user (.stepStart "S")) == no "step is cancelled, not waiting"
#guard out (steps ++ [ev "x" 5 .user (.stepStart "T"), ev "y" 6 .user (.stepDone "T")]) (ev "z" 7 .user (.stepStart "T"))
  == no "step is done, not waiting"
#guard out steps (ev "x" 5 .user (.stepCancel "S")) == yes
#guard out (steps ++ [ev "x" 5 .user (.stepStart "S")]) (ev "y" 6 .user (.stepCancel "S")) == yes
#guard out (steps ++ [ev "x" 5 .user (.stepAnswer "S" "yes")]) (ev "y" 6 .user (.stepCancel "S")) == no "step already answered"
#guard out steps (ev "x" 5 .user (.stepDone "T")) == no "step is waiting, only a started step can be done"
#guard out (steps ++ [ev "x" 5 .user (.stepStart "T")]) (ev "y" 6 .user (.stepDone "T")) == yes
#guard out (steps ++ [ev "x" 5 .user (.stepCancel "S")]) (ev "y" 6 .user (.stepAnswer "S" "yes")) == no "step already cancelled"
#guard out steps (ev "x" 5 .user (.stepAnswer "T" "yes")) == no "an action step is finished with step.done, not an answer"
#guard out steps (ev "x" 5 .user (.stepAnswer "S" "maybe")) == no "answer must be yes or no"
#guard out steps (ev "x" 5 .user (.stepAnswer "S" "yes")) == yes
#guard out steps (ev "x" 5 .user (.stepAnswer "S" "no")) == yes
#guard out (steps ++ [ev "x" 5 .user (.stepStart "S")]) (ev "y" 6 .user (.stepAnswer "S" "no")) == yes
#guard out steps (ev "x" 5 .user (.stepAnswer "C" "c")) == no "answer is not one of the options"
#guard out steps (ev "x" 5 .user (.stepAnswer "C" "b")) == yes

-- runs
#guard out opened (ev "x" 5 .script (.runStart "R" "Z" .gate)) == no "no such card"
#guard out (opened ++ [ev "r1" 5 .script (.runStart "R" "A" .gate)]) (ev "x" 6 .script (.runStart "R" "A" .gate)) == no "run exists"
#guard out opened (ev "x" 6 .script (.runFinish "R" true)) == no "no such run"
#guard out (opened ++ [ev "r1" 5 .script (.runStart "R" "A" .gate)]) (ev "x" 6 .script (.runFinish "R" true)) == yes
#guard out (opened ++ [ev "r1" 5 .script (.runStart "R" "A" .gate), ev "r2" 6 .script (.runFinish "R" false)])
  (ev "x" 7 .script (.runFinish "R" true)) == no "run already finished"

-- keys: seen only on acceptance; a duplicate is a no-op
#guard out opened (ev "a1" 9 .owner (.cardOpen "B" "o" false)) == .accepted true
#guard (project (opened ++ [ev "x" 2 .hook (.cardOpen "B" "o" false)])).seen == ["a1"]
#guard (project (opened ++ [ev "a1" 2 .owner (.cardOpen "B" "o" false)])).cards.length == 1

-- effects of accepted bodies
#guard (project steps).steps.map (fun s => (s.id, s.card, s.status, s.postedAt, s.lastAt))
  == [("S", some "A", .waiting, 2, 2), ("C", none, .waiting, 3, 3), ("T", none, .waiting, 4, 4)]
#guard (project (steps ++ [ev "x" 7 .user (.stepStart "S"), ev "y" 8 .user (.stepAnswer "S" "no"),
    ev "z" 9 .user (.stepCancel "C"), ev "w" 10 .user (.stepStart "T"), ev "v" 11 .user (.stepDone "T")])).steps.map
    (fun s => (s.id, s.status, s.answer, s.lastAt))
  == [("S", .answered, some "no", 8), ("C", .cancelled, none, 9), ("T", .done, none, 11)]
#guard
  let s := project (opened ++ [ev "r1" 5 .script (.runStart "R" "A" .device), ev "r2" 7 .script (.runStart "Q" "A" .gate),
    ev "r3" 8 .script (.runFinish "R" true), ev "r4" 9 .script (.runFinish "Q" false)])
  s.runs.map (fun r => (r.id, r.card, r.status, r.startedAt)) == [("R", "A", .passed, 5), ("Q", "A", .failed, 7)]
  && s.cards.map (·.lastAt) == [9]
#guard (project opened).cards == [{ id := "A", owner := "o", needsDevice := false, lastAt := 1 }]
#guard (project built).cards
  == [{ id := "A", owner := "o", needsDevice := false, approved := true, head := some "s1", builders := ["b"],
        lastAt := 3 }]
#guard (project (readyLog ++ [ev "a6" 6 .script (.cardSwipe "A" "s1" true), ev "a7" 7 .lead (.cardLandRequest "A" "s1")])).cards
  == [{ id := "A", owner := "o", needsDevice := false, approved := true, head := some "s1", builders := ["b"],
        screenAt := some "s1", reviewAt := some "s1", reviewedBy := some "r", deviceAt := some "s1",
        landReq := some "s1", lastAt := 7 }]
-- a rebuild clears the evidence and adds the builder in front
#guard (project (readyLog ++ [ev "a6" 6 .git (.cardBuild "A" "s2" "c")])).cards
  == [{ id := "A", owner := "o", needsDevice := false, approved := true, head := some "s2", builders := ["c", "b"],
        lastAt := 6 }]
#guard (project (readyLog ++ [ev "q" 6 .lead (.cardLandRequest "A" "s1"), ev "l" 7 .git (.cardLanded "A" "s1")])).cards.map
  (fun c => (c.landed, c.violation, c.lastAt)) == [(true, false, 7)]
#guard (project landedLog).cards.map (fun c => (c.landed, c.violation)) == [(true, true)]
-- ready but never requested, and requested at another sha: both still a violation
#guard (project (readyLog ++ [ev "l" 7 .git (.cardLanded "A" "s1")])).cards.map (·.violation) == [true]
#guard (project (readyLog ++ [ev "q" 6 .lead (.cardLandRequest "A" "s1"), ev "l" 7 .git (.cardLanded "A" "s0")])).cards.map
  (·.violation) == [true]
-- an event stamped earlier never moves lastAt back
#guard (project (built ++ [ev "x" 1 .script (.cardScreen "A" "s1" true)])).cards.map (·.lastAt) == [3]
#guard (project (steps ++ [ev "x" 1 .user (.stepStart "S")])).steps.map (·.lastAt) == [2, 3, 4]
-- only the named card / step changes
#guard
  let s := project (opened ++ [ev "b1" 2 .owner (.cardOpen "B" "o" true), ev "b2" 3 .lead (.cardApprove "B")])
  s.cards.map (fun c => (c.id, c.approved, c.lastAt)) == [("A", false, 1), ("B", true, 3)]

-- stage, ready, stale
/-- A card with the given evidence (owner `o`, approved, head `s1` unless overridden). -/
def card (dev : Bool := false) (head : Option String := some "s1") (sc rv dv : Option String := none) : Card :=
  { id := "A", owner := "o", needsDevice := dev, approved := true, head := head, screenAt := sc, reviewAt := rv, deviceAt := dv }
#guard stage { card with landed := true } == .land
#guard stage { card with approved := false } == .question
#guard stage (card (head := none)) == .build
#guard stage card == .screen
#guard stage (card (sc := some "s1")) == .review
#guard stage (card (sc := some "s0") (rv := some "s1")) == .screen
#guard stage (card (sc := some "s1") (rv := some "s0")) == .review
#guard stage (card (dev := true) (sc := some "s1") (rv := some "s1")) == .device
#guard stage (card (dev := true) (sc := some "s1") (rv := some "s1") (dv := some "s1")) == .land_ready
#guard stage (card (sc := some "s1") (rv := some "s1")) == .land_ready
#guard ready (card (sc := some "s1") (rv := some "s1"))
#guard !ready { card (sc := some "s1") (rv := some "s1") with approved := false }
#guard !ready (card (head := none))
#guard !ready (card (sc := some "s0") (rv := some "s1"))
#guard !ready (card (sc := some "s1") (rv := some "s0"))
#guard !ready (card (dev := true) (sc := some "s1") (rv := some "s1"))
#guard ready (card (dev := true) (sc := some "s1") (rv := some "s1") (dv := some "s1"))
#guard !ready (card (dev := true) (sc := some "s1") (rv := some "s1") (dv := some "s0"))
#guard (touch 5 { card with lastAt := 9 }).lastAt == 9 && (touch 12 { card with lastAt := 9 }).lastAt == 12
#guard stale 10 20 0 { card with lastAt := 10 } && !stale 10 19 0 { card with lastAt := 10 }
#guard !stale 10 20 1 { card with lastAt := 10 } && stale 0 5 0 { card with lastAt := 9 }

-- review.previewed: wire name, actors, device and flag refusals
#guard EvType.reviewPreviewed.name == "review.previewed"
#guard [Actor.user, .lead, .owner, .reviewer, .script, .git, .hook].filter (may · EvType.reviewPreviewed) == [.user]
#guard out opened (ev "x" 5 .user (.reviewPreviewed "nav:a" "phone")) == yes
#guard out opened (ev "x" 5 .user (.reviewPreviewed "nav:a" "desktop")) == yes
#guard out opened (ev "x" 5 .lead (.reviewPreviewed "nav:a" "phone")) != yes
#guard out opened (ev "x" 5 .user (.reviewPreviewed "nav:a" "tablet")) == no "device must be desktop or phone"
#guard out opened (ev "x" 5 .user (.reviewPreviewed "nocolon" "phone")) == no "flag must be a key part:variant"

-- review.feedback / review.feedback.reply: wire names, actors, every refusal reason, the reply closing the thread

def fbLog : List Event := opened ++ [ev "f1" 10 .user (.reviewFeedback "nav:a" "fb-1" "look at the font")]
def fbDone : List Event := fbLog ++ [ev "f2" 11 .lead (.reviewFeedbackReply "nav:a" "fb-1" "done")]
#guard EvType.reviewFeedback.name == "review.feedback"
#guard EvType.reviewFeedbackReply.name == "review.feedback.reply"
#guard [Actor.user, .lead, .owner, .reviewer, .script, .git, .hook].filter (may · EvType.reviewFeedback) == [.user]
#guard [Actor.user, .lead, .owner, .reviewer, .script, .git, .hook].filter (may · EvType.reviewFeedbackReply) == [.lead]
#guard out opened (ev "x" 5 .user (.reviewFeedback "nav:a" "fb-1" "hi")) == yes
#guard out opened (ev "x" 5 .lead (.reviewFeedback "nav:a" "fb-1" "hi")) == no "actor lead may not cause review.feedback"
#guard out fbLog (ev "x" 12 .user (.reviewFeedbackReply "nav:a" "fb-1" "done")) == no "actor user may not cause review.feedback.reply"
#guard out opened (ev "x" 5 .user (.reviewFeedback "nocolon" "fb-1" "hi")) == no "flag must be a key part:variant"
#guard out opened (ev "x" 5 .user (.reviewFeedback "nav:a" "" "hi")) == no "id is empty"
#guard out opened (ev "x" 5 .user (.reviewFeedback "nav:a" "fb-1" "  ")) == no "text is empty"
#guard out opened (ev "x" 5 .user (.reviewFeedback "nav:a" "fb-1" (String.ofList (List.replicate 2001 'a')))) == no "text is longer than 2000 characters"
#guard out opened (ev "x" 5 .user (.reviewFeedback "nav:a" "fb-1" (String.ofList (List.replicate 2000 'a')))) == yes
#guard out fbLog (ev "x" 12 .user (.reviewFeedback "nav:a" "fb-1" "again")) == no "feedback id exists"
#guard out fbLog (ev "x" 12 .lead (.reviewFeedbackReply "nav:a" "fb-1" "done")) == yes
#guard out fbLog (ev "x" 12 .lead (.reviewFeedbackReply "nav:a" "fb-9" "done")) == no "no such feedback"
#guard out fbLog (ev "x" 12 .lead (.reviewFeedbackReply "nav:b" "fb-1" "done")) == no "no such feedback"
#guard out fbDone (ev "x" 13 .lead (.reviewFeedbackReply "nav:a" "fb-1" "twice")) == no "feedback already answered"
#guard out fbLog (ev "x" 12 .lead (.reviewFeedbackReply "nav:a" "fb-1" "")) == no "text is empty"
#guard (project fbLog).fb.length == 1 && (project fbLog).fb.all (·.isOpen)
#guard (project fbDone).fb.length == 1 && (project fbDone).fb.all (!·.isOpen)

end FwTest.Mutants.Console
