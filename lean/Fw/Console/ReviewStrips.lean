import Fw.Preset.Gen
/-!
# Frame strips of a look-change review

The strips a person looks at in the Reviews tab: per flag, engine, width and push, the CI artifact and the file inside it,
a note and a time difference. The rows are the one canonical source. `stripsOf` gives each strip a state (ready, expired,
missing); `serve` is the allowlist of the files the console may send.
-/
namespace Fw.Console.ReviewStrips
open Fw.Preset

/-- Which push of the nav a strip shows. -/
inductive Push | open_ | close
deriving DecidableEq, Repr

/-- The word of a push. -/
def Push.word : Push → String
  | .open_ => "open" | .close => "close"

/-- **One strip**: the flag, the engine, the viewport width, the push, where it is (CI run, artifact, path inside the
artifact, expiry of the run's artifacts as `YYYY-MM-DD`), a note and the time difference between the rows. -/
structure Row where
  flag : Flag
  engine : String
  width : Nat
  push : Push
  run : String
  artifact : String
  path : String
  expires : String
  note : String
  diff : String
deriving DecidableEq, Repr

/-- The file name of a row: the last part of its path. This is the only name the console serves. -/
def Row.file (r : Row) : String := (r.path.splitOn "/").getLast!

private def earn : Flag := ⟨"nav", "earn-no-transition"⟩

private def chr (w : Nat) (p : Push) (note diff : String) : Row :=
  { flag := earn, engine := "chromium", width := w, push := p, run := "39473950464", artifact := "frames-chromium",
    path := s!"strips/chromium-{w}-{p.word}.png", expires := "2026-11-19", note, diff }

private def wk (w : Nat) (p : Push) : Row :=
  { flag := earn, engine := "webkit", width := w, push := p, run := "39530106935", artifact := s!"frames-apple-{w}",
    path := s!"strips/playwright-webkit-{w}-{p.word}.png", expires := "2026-11-20", note := "", diff := "" }

/-- **The strips** (CI run 39473950464, Chromium 156, real scroll input; run 39530106935, macOS Playwright WebKit, screenshot
strips, time-aligned between the two rows). The notes of the WebKit strips are not written yet. -/
def rows : List Row :=
  [ chr 390 .close "Look at the dark Join waitlist pill. With the flag it is on screen at 478 ms and solid at about 588 ms, moving together with the nav. In the original it starts fading in only at about 865 ms and is solid at about 1032 ms." "about 0.4 s earlier",
    chr 1280 .close "Same as the phone. With the flag the pill shows faintly at 538 ms and is solid by about 657 ms. In the original it starts at about 935 ms and is solid at about 1071 ms." "about 0.4 s earlier",
    chr 390 .open_ "In the original the dark pill stays full size next to EN until about 384 ms, then disappears. With the flag it shrinks and fades in the first 160 to 223 ms, together with the nav." "about 0.1 to 0.15 s earlier",
    chr 1280 .open_ "In the original the blurred pill is still visible at 249 ms. With the flag it is mostly gone by 194 ms. The nav move itself is the same." "small",
    wk 390 .close, wk 1280 .close, wk 390 .open_, wk 1280 .open_ ]

/-- The state of a strip. -/
inductive State | ready | expired | missing
deriving DecidableEq, Repr

/-- The word of a state. -/
def State.word : State → String
  | .ready => "ready" | .expired => "expired" | .missing => "missing"

/-- A strip as the op returns it: an engine, a state, and the row (none for a missing strip). -/
structure Out where
  engine : String
  state : State
  row : Option Row
deriving Repr

/-- Whether the artifacts of a row are gone on `today` (both `YYYY-MM-DD`): `today >= expires`. -/
def expired (today : String) (r : Row) : Bool := decide (¬ today < r.expires)

/-- **The dispatch that re-makes the strips of a flag**: the two lines of a ci/* head commit message. -/
def redo (f : Flag) : String := s!"[ci:trajectory-probe] [frames:{f.key}]"

/-- The engines of a material whose strips are ready, with their names. -/
def readyEngines (m : Option Gen.ReviewMaterial) : List String :=
  match m with
  | none => []
  | some m => (if m.chromium.state == .ready then ["chromium"] else []) ++ (if m.webkit.state == .ready then ["webkit"] else [])

/-- The strips of one engine of a flag: each row with its state, or one missing strip when the engine has no row. -/
def engineOuts (today : String) (f : Flag) (e : String) : List Out :=
  match rows.filter (fun r => r.flag == f && r.engine == e) with
  | [] => [⟨e, .missing, none⟩]
  | rs => rs.map fun r => ⟨e, if expired today r then .expired else .ready, some r⟩

/-- **The strips of an item**: those of every engine whose material is ready. -/
def stripsOf (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) : List Out :=
  (readyEngines m).flatMap (engineOuts today f)

/-- The files the console may send for an item: the ready strips only. -/
def servable (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) : List Row :=
  (stripsOf today f m).filterMap fun o => if o.state == .ready then o.row else none

/-- **The allowlist**: the row a request for `file` of the item may be served from. -/
def serve (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String) : Option Row :=
  (servable today f m).find? fun r => r.file == file

/-- Every row of an engine output belongs to the flag and to its engine. -/
theorem engineOuts_row (today : String) (f : Flag) (e : String) (o : Out) (h : o ∈ engineOuts today f e)
    (r : Row) (hr : o.row = some r) : r ∈ rows ∧ r.flag = f ∧ r.engine = e ∧ o.engine = e := by
  unfold engineOuts at h
  split at h
  · simp at h; subst h; simp at hr
  · rename_i rs hne
    simp only [List.mem_map] at h
    obtain ⟨r', hr', rfl⟩ := h
    have hm : r' ∈ rows.filter (fun r => r.flag == f && r.engine == e) := hr'
    simp only [List.mem_filter, Bool.and_eq_true, beq_iff_eq] at hm
    simp only [Option.some.injEq] at hr; subst hr
    exact ⟨hm.1, hm.2.1, hm.2.2, rfl⟩

/-- **Every strip the op returns belongs to the item's flag and to an engine whose material is ready.** -/
theorem strip_belongs (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out) (h : o ∈ stripsOf today f m)
    (r : Row) (hr : o.row = some r) : r ∈ rows ∧ r.flag = f ∧ r.engine ∈ readyEngines m ∧ o.engine = r.engine := by
  unfold stripsOf at h
  simp only [List.mem_flatMap] at h
  obtain ⟨e, he, ho⟩ := h
  obtain ⟨h0, h1, h2, h3⟩ := engineOuts_row today f e o ho r hr
  exact ⟨h0, h1, h2 ▸ he, h3.trans h2.symm⟩

/-- **Material that is not ready returns no strip.** -/
theorem pending_no_strips (today : String) (f : Flag) (m : Gen.ReviewMaterial) (h1 : m.chromium.state = .pending)
    (h2 : m.webkit.state = .pending) : stripsOf today f (some m) = [] := by
  simp [stripsOf, readyEngines, h1, h2]

/-- **An expired strip is never served**: every servable row is unexpired. -/
theorem expired_not_served (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (r : Row)
    (h : r ∈ servable today f m) : expired today r = false := by
  unfold servable at h
  simp only [List.mem_filterMap] at h
  obtain ⟨o, ho, h⟩ := h
  unfold stripsOf at ho
  simp only [List.mem_flatMap] at ho
  obtain ⟨e, _, ho⟩ := ho
  unfold engineOuts at ho
  split at ho
  · simp at ho; subst ho; simp at h
  · simp only [List.mem_map] at ho
    obtain ⟨r', _, rfl⟩ := ho
    by_cases hx : expired today r' = true
    · simp [hx] at h
    · simp only [hx] at h
      simp at h
      subst h
      simpa using hx

/-- A servable row is a ready strip of the item, so a row of the flag. -/
theorem servable_mem (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (r : Row)
    (h : r ∈ servable today f m) : r ∈ rows ∧ r.flag = f := by
  unfold servable at h
  simp only [List.mem_filterMap] at h
  obtain ⟨o, ho, h⟩ := h
  have hr : o.row = some r := by split at h <;> simp_all
  have := strip_belongs today f m o ho r hr
  exact ⟨this.1, this.2.1⟩

/-- **The files the console may serve are exactly row files**: a served row is a row of the flag, its file is the name asked
for, and it is not expired. -/
theorem serve_allowlist (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String) (r : Row)
    (h : serve today f m file = some r) : r ∈ rows ∧ r.flag = f ∧ r.file = file ∧ expired today r = false := by
  unfold serve at h
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  have := servable_mem today f m r hm
  exact ⟨this.1, this.2, by simpa using hp, expired_not_served today f m r hm⟩

/-- A file that is no row file is refused (nothing from the request reaches a path). -/
theorem serve_unknown (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String)
    (h : ∀ r ∈ rows, r.file ≠ file) : serve today f m file = none := by
  cases hs : serve today f m file with
  | none => rfl
  | some r => exact absurd (serve_allowlist today f m file r hs).2.2.1 (h r (serve_allowlist today f m file r hs).1)

/-- An expired row is not served. -/
theorem expired_refused (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (r : Row)
    (h : expired today r = true) : serve today f m r.file ≠ some r := by
  intro hs
  have := (serve_allowlist today f m r.file r hs).2.2.2
  simp [h] at this

/-- A missing strip is returned only for an engine whose material is ready and for which no row of the flag exists. -/
theorem missing_only_without_rows (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out)
    (h : o ∈ stripsOf today f m) (hs : o.state = .missing) :
    o.engine ∈ readyEngines m ∧ ∀ r ∈ rows, ¬ (r.flag = f ∧ r.engine = o.engine) := by
  unfold stripsOf at h
  simp only [List.mem_flatMap] at h
  obtain ⟨e, he, ho⟩ := h
  unfold engineOuts at ho
  split at ho
  · rename_i hnil
    simp only [List.mem_singleton] at ho; subst ho
    refine ⟨he, fun r hr ⟨h1, h2⟩ => ?_⟩
    have : r ∈ rows.filter (fun r => r.flag == f && r.engine == e) := by simp [hr, h1, h2]
    rw [hnil] at this; simp at this
  · simp only [List.mem_map] at ho
    obtain ⟨r, _, rfl⟩ := ho
    revert hs
    simp only
    split <;> simp


private def mat (c w : Gen.Ready) : Gen.ReviewMaterial :=
  { chromium := { state := c }, webkit := { state := w } }

-- the row files of the seed are unique (a name decides one row)
#guard (rows.map Row.file).eraseDups.length == rows.length
#guard (stripsOf "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .ready))).length == 8
#guard (stripsOf "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .pending))).length == 4
#guard (stripsOf "2026-10-21" ⟨"nav", "earn-no-transition"⟩ none).length == 0
-- an engine whose material is ready but which has no row of the flag: one missing strip
#guard (stripsOf "2026-10-21" ⟨"nav", "other"⟩ (some (mat .ready .pending))).map (·.state) == [.missing]
-- expiry day: the day before is ready, the day itself is expired
#guard (servable "2026-11-18" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .pending))).length == 4
#guard (servable "2026-11-19" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .pending))).length == 0
#guard (stripsOf "2026-11-19" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .pending))).all (·.state == .expired)
#guard (servable "2026-11-19" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .ready))).length == 4
#guard (serve "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .ready)) "chromium-390-open.png").isSome
#guard (serve "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .ready)) "playwright-webkit-1280-close.png").isSome
#guard (serve "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .pending)) "playwright-webkit-1280-close.png").isNone
#guard (serve "2026-10-21" ⟨"nav", "earn-no-transition"⟩ (some (mat .ready .ready)) "../x.png").isNone
#guard (serve "2026-10-21" ⟨"nav", "other"⟩ (some (mat .ready .ready)) "chromium-390-open.png").isNone

end Fw.Console.ReviewStrips
