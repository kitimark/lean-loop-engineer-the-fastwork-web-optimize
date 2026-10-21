import Fw.Wire.ReviewFeedback
import Fw.Console
import Fw.Console.Steps
/-!
# JSON for the grouped steps (`console.stepTopics`)

| op | request | reply |
|---|---|---|
| `console.stepTopics` | `events` [{type, ...}] of the log (`step.topic` {topic, title, summary, ts}; `review.feedback` and its reply as in `console.reviewFeedback`; other types ignored), `steps` [{id, topic?, status, audience, lastAt}] of the board | `groups` [{topic (null = the rest), title, summary, updatedAt, steps [id], openQuestions, activity, thread}] in `Fw.Console.Steps.view` order, `threads` [{flag, open, comments}] of the step and topic subjects |
-/
namespace Fw.Wire.Steps
open Lean Fw.Wire.Ops Fw.Console.Steps Fw.Console.ReviewFeedback

/-- A step status word is open exactly when the reducer's `StepStatus.isOpen` says so. -/
def openWord (w : String) : Bool := w == "waiting" || w == "started"

#guard [Fw.Console.StepStatus.waiting, .started, .answered, .done, .cancelled].all fun s => openWord s.name == s.isOpen

/-- Read one `step.topic` event of the log (`none` for any other type). -/
def topicEvOf (j : Json) : Except String (Option TopicEv) := do
  match ← str j "type" with
  | "step.topic" => pure (some ⟨← str j "topic", ← str j "title", ← str j "summary", ← nat j "ts"⟩)
  | _ => pure none

/-- Read one board step as a grouping item; `none` unless it is open and for the user. -/
def itemOf (j : Json) : Except String (Option Item) := do
  let audience ← str j "audience"
  let status ← str j "status"
  if openWord status && audience == "user" then
    pure (some ⟨← str j "id", ← optS j "topic", ← natD j "lastAt" 0⟩)
  else pure none

/-- One group as JSON. -/
def groupJson (fs : List Fb) (g : Group) : Json :=
  Json.mkObj [("topic", ostr g.topic), ("title", .str g.title), ("summary", .str g.summary),
    ("updatedAt", match g.updatedAt with | some n => toJson n | none => Json.null),
    ("steps", .arr (g.items.map (fun i => Json.str i.id)).toArray), ("openQuestions", toJson g.openQuestions),
    ("activity", toJson g.activity),
    ("thread", match g.topic with
      | some t => Fw.Wire.ReviewFeedback.threadJson fs (topicSubject t)
      | none => Json.null)]

/-- `console.stepTopics` (`Fw.Console.Steps.view`). -/
def opStepTopics (req : Json) : Except String Reply := do
  let events ← arrD req "events"
  let tops := topics ((← events.mapM topicEvOf).filterMap id)
  let fs := thread ((← events.mapM Fw.Wire.ReviewFeedback.evOf).filterMap id)
  let items := (← (← arrD req "steps").mapM itemOf).filterMap id
  let subjects := (Fw.Wire.ReviewFeedback.flagsOf fs).filter isStepSubject
  pure [("groups", .arr ((view tops items fs).map (groupJson fs)).toArray),
        ("threads", .arr (subjects.map (Fw.Wire.ReviewFeedback.threadJson fs)).toArray)]

end Fw.Wire.Steps
