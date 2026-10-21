import Fw.Preset.Gen
/-!
# Frame strips of a look-change review

The strips a person looks at in the Reviews tab: per flag, engine, width and push, the artifact, the file inside it, a note
and a time difference. The rows hold no run and no expiry: those are read from `Gen.lookDecisions` material of the flag and
engine (the one canonical source), and a row whose artifact is not named by that material is missing. `stripsOf` gives each
strip a state (ready, expired, missing); `serve` is the allowlist of the files the console may send.
-/
namespace Fw.Console.ReviewStrips
open Fw.Preset

/-- Which push of the nav a strip shows. -/
inductive Push | open_ | close
deriving DecidableEq, Repr

/-- The word of a push. -/
def Push.word : Push → String
  | .open_ => "open" | .close => "close"

/-- **One strip**: the flag, the engine, the viewport width, the push, where it is (the artifact name and the path inside
it), a note and the time difference between the rows. -/
structure Row where
  flag : Flag
  engine : String
  width : Nat
  push : Push
  artifact : String
  path : String
  note : String
  diff : String
deriving DecidableEq, Repr

/-- The file name of a row: the last part of its path. This is the only name the console serves. -/
def Row.file (r : Row) : String := (r.path.splitOn "/").getLast!

private def earn : Flag := ⟨"nav", "earn-no-transition"⟩

private def chr (w : Nat) (p : Push) (note diff : String) : Row :=
  { flag := earn, engine := "chromium", width := w, push := p, artifact := "frames-chromium",
    path := s!"strips/chromium-{w}-{p.word}.png", note, diff }

private def wk (w : Nat) (p : Push) : Row :=
  { flag := earn, engine := "webkit", width := w, push := p, artifact := s!"frames-apple-{w}",
    path := s!"strips/playwright-webkit-{w}-{p.word}.png", note := "", diff := "" }

/-- **The strips** (CI run 39473950464, Chromium 156, real scroll input; run 39530106935, macOS Playwright WebKit, screenshot
strips, the ones to compare timing with; each arm is sampled at its own shot times). The notes of the WebKit strips are not written yet. The runs and
expiries are in `Gen.lookDecisions`, not here. -/
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

/-- **A resolved strip**: a row with the CI run and the expiry of its artifact, both read from the material. -/
structure Strip where
  row : Row
  run : String
  expires : String
deriving DecidableEq, Repr

/-- A strip as the op returns it: an engine, a state, the row (none when the engine has no row) and the resolved strip (none
when it is missing). -/
structure Out where
  engine : String
  state : State
  row : Option Row
  strip : Option Strip
deriving Repr

/-- Whether the artifacts of a strip are gone on `today` (both `YYYY-MM-DD`): `today >= expires`. -/
def expired (today : String) (s : Strip) : Bool := decide (¬ today < s.expires)

/-- **The dispatch that re-makes the strips of a flag**: one commit-message line of a ci/* head commit. -/
def redo (f : Flag) : String := s!"[ci:trajectory-probe] [frames:{f.key}]"

/-- The artifact names of a material: its artifact string split on `, `. -/
def names (a : String) : List String := a.splitOn ", "

/-- **The one place a row meets the material**: the strip of `r` with the run and expiry of `em`, when `em` names a run,
an expiry and an artifact list that contains the artifact of `r`; otherwise none. -/
def resolve (em : Gen.EngineMat) (r : Row) : Option Strip :=
  match em.run, em.artifact, em.expires with
  | some run, some a, some ex => if r.artifact ∈ names a then some ⟨r, run, ex⟩ else none
  | _, _, _ => none

/-- The material of an engine of a look change, when its strips are ready. -/
def engMat (m : Option Gen.ReviewMaterial) (e : String) : Option Gen.EngineMat :=
  match m with
  | none => none
  | some m =>
    let em : Gen.EngineMat := if e == "chromium" then m.chromium else if e == "webkit" then m.webkit else { state := .pending }
    if em.state == .ready then some em else none

/-- The output of one row: missing when the material does not resolve it, else expired or ready by the expiry of the material. -/
def mk (today : String) (e : String) (em : Gen.EngineMat) (r : Row) : Out :=
  match resolve em r with
  | none => ⟨e, .missing, some r, none⟩
  | some s => ⟨e, if expired today s then .expired else .ready, some r, some s⟩

/-- The strips of one engine of a flag: each row with its state, or one missing strip when the engine has no row. -/
def engineOuts (today : String) (f : Flag) (e : String) (em : Gen.EngineMat) : List Out :=
  match rows.filter (fun r => r.flag == f && r.engine == e) with
  | [] => [⟨e, .missing, none, none⟩]
  | rs => rs.map (mk today e em)

/-- **The strips of an item**: those of every engine whose material is ready. -/
def stripsOf (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) : List Out :=
  ["chromium", "webkit"].flatMap fun e =>
    match engMat m e with
    | none => []
    | some em => engineOuts today f e em

/-- The strips the console may send for an item: the ready ones only. -/
def servable (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) : List Strip :=
  (stripsOf today f m).filterMap fun o => if o.state == .ready then o.strip else none

/-- **The allowlist**: the strip a request for `file` of the item may be served from. -/
def serve (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String) : Option Strip :=
  (servable today f m).find? fun s => s.row.file == file

theorem resolve_sound (em : Gen.EngineMat) (r : Row) (s : Strip) (h : resolve em r = some s) :
    s.row = r ∧ em.run = some s.run ∧ em.expires = some s.expires ∧ ∃ a, em.artifact = some a ∧ s.row.artifact ∈ names a := by
  unfold resolve at h
  split at h
  · rename_i run a ex hr ha he
    split at h
    · rename_i hin
      simp only [Option.some.injEq] at h; subst h
      exact ⟨rfl, hr, he, a, ha, hin⟩
    · simp at h
  · simp at h

/-- **A row whose artifact is not named by the material is not resolved** (so it is reported missing, never served). -/
theorem resolve_unnamed (em : Gen.EngineMat) (r : Row) (a : String) (ha : em.artifact = some a)
    (h : r.artifact ∉ names a) : resolve em r = none := by
  unfold resolve
  split
  · rename_i run a' ex hr ha' he
    rw [ha] at ha'; simp only [Option.some.injEq] at ha'; subst ha'
    simp [h]
  · rfl

theorem mk_engine (today : String) (e : String) (em : Gen.EngineMat) (r : Row) : (mk today e em r).engine = e := by
  unfold mk; split <;> rfl

theorem mk_row (today : String) (e : String) (em : Gen.EngineMat) (r : Row) : (mk today e em r).row = some r := by
  unfold mk; split <;> rfl

theorem mk_strip (today : String) (e : String) (em : Gen.EngineMat) (r : Row) (s : Strip)
    (h : (mk today e em r).strip = some s) : resolve em r = some s := by
  unfold mk at h; split at h
  · simp at h
  · rename_i s' hs; simp only [Option.some.injEq] at h; subst h; exact hs

/-- A row that resolves is never reported missing; one that does not is. -/
theorem mk_missing (today : String) (e : String) (em : Gen.EngineMat) (r : Row) :
    (mk today e em r).state = .missing ↔ resolve em r = none := by
  cases hr : resolve em r with
  | none => simp [mk, hr]
  | some s' =>
    by_cases hx : expired today s' = true <;> simp [mk, hr, hx]

theorem mk_ready (today : String) (e : String) (em : Gen.EngineMat) (r : Row) (s : Strip)
    (h1 : (mk today e em r).state = .ready) (h2 : (mk today e em r).strip = some s) : expired today s = false := by
  cases hr : resolve em r with
  | none => simp [mk, hr] at h1
  | some s' =>
    simp only [mk, hr, Option.some.injEq] at h1 h2
    subst h2
    by_cases hx : expired today s' = true
    · simp [hx] at h1
    · simpa using hx

/-- Every row of an engine output belongs to the flag and to its engine. -/
theorem engineOuts_row (today : String) (f : Flag) (e : String) (em : Gen.EngineMat) (o : Out)
    (h : o ∈ engineOuts today f e em) (r : Row) (hr : o.row = some r) :
    r ∈ rows ∧ r.flag = f ∧ r.engine = e ∧ o.engine = e := by
  unfold engineOuts at h
  split at h
  · simp at h; subst h; simp at hr
  · simp only [List.mem_map] at h
    obtain ⟨r', hr', rfl⟩ := h
    have hm : r' ∈ rows.filter (fun r => r.flag == f && r.engine == e) := hr'
    simp only [List.mem_filter, Bool.and_eq_true, beq_iff_eq] at hm
    rw [mk_row] at hr; simp only [Option.some.injEq] at hr; subst hr
    exact ⟨hm.1, hm.2.1, hm.2.2, mk_engine ..⟩

/-- The structure of a strip of an item: the engine, its ready material, and the engine output it came from. -/
theorem stripsOf_mem (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out) (h : o ∈ stripsOf today f m) :
    ∃ e em, engMat m e = some em ∧ o ∈ engineOuts today f e em := by
  unfold stripsOf at h
  simp only [List.mem_flatMap] at h
  obtain ⟨e, _, ho⟩ := h
  split at ho
  · simp at ho
  · rename_i em hem; exact ⟨e, em, hem, ho⟩

/-- **Every strip the op returns belongs to the item's flag and to an engine whose material is ready.** -/
theorem strip_belongs (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out) (h : o ∈ stripsOf today f m)
    (r : Row) (hr : o.row = some r) : r ∈ rows ∧ r.flag = f ∧ (engMat m r.engine).isSome ∧ o.engine = r.engine := by
  obtain ⟨e, em, hem, ho⟩ := stripsOf_mem today f m o h
  obtain ⟨h0, h1, h2, h3⟩ := engineOuts_row today f e em o ho r hr
  subst h2
  exact ⟨h0, h1, by simp [hem], h3⟩

/-- **Material that is not ready returns no strip.** -/
theorem pending_no_strips (today : String) (f : Flag) (m : Gen.ReviewMaterial) (h1 : m.chromium.state = .pending)
    (h2 : m.webkit.state = .pending) : stripsOf today f (some m) = [] := by
  simp [stripsOf, engMat, h1, h2]

/-- **Run and expiry come from the material**: every strip of an item has the run and the expiry of the ready material of its
engine, and its artifact is one the material names. -/
theorem strip_material (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out) (h : o ∈ stripsOf today f m)
    (s : Strip) (hs : o.strip = some s) :
    ∃ em, engMat m o.engine = some em ∧ em.run = some s.run ∧ em.expires = some s.expires ∧
      ∃ a, em.artifact = some a ∧ s.row.artifact ∈ names a := by
  obtain ⟨e, em, hem, ho⟩ := stripsOf_mem today f m o h
  unfold engineOuts at ho
  split at ho
  · simp at ho; subst ho; simp at hs
  · simp only [List.mem_map] at ho
    obtain ⟨r, _, rfl⟩ := ho
    rw [mk_engine]
    exact ⟨em, hem, (resolve_sound em r s (mk_strip _ _ _ _ _ hs)).2⟩

/-- **A row whose artifact the material does not name is reported missing, never served.** -/
theorem unnamed_missing (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out) (h : o ∈ stripsOf today f m)
    (r : Row) (hr : o.row = some r) (em : Gen.EngineMat) (hem : engMat m o.engine = some em) (a : String)
    (ha : em.artifact = some a) (hn : r.artifact ∉ names a) : o.state = .missing ∧ o.strip = none := by
  obtain ⟨e, em', hem', ho⟩ := stripsOf_mem today f m o h
  unfold engineOuts at ho
  split at ho
  · simp at ho; subst ho; simp at hr
  · simp only [List.mem_map] at ho
    obtain ⟨r', _, rfl⟩ := ho
    rw [mk_row] at hr; simp only [Option.some.injEq] at hr; subst hr
    rw [mk_engine] at hem; rw [hem'] at hem; simp only [Option.some.injEq] at hem; subst hem
    have := resolve_unnamed em' r' a ha hn
    unfold mk; simp [this]

/-- A servable strip is a ready strip of the item. -/
theorem servable_mem (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (s : Strip) (h : s ∈ servable today f m) :
    ∃ o ∈ stripsOf today f m, o.state = .ready ∧ o.strip = some s ∧ o.row = some s.row := by
  unfold servable at h
  simp only [List.mem_filterMap] at h
  obtain ⟨o, ho, h⟩ := h
  by_cases hr : o.state = .ready
  · simp only [hr, beq_self_eq_true, ite_true] at h
    obtain ⟨e, em, hem, hoe⟩ := stripsOf_mem today f m o ho
    unfold engineOuts at hoe
    split at hoe
    · simp at hoe; subst hoe; simp at hr
    · simp only [List.mem_map] at hoe
      obtain ⟨r, _, rfl⟩ := hoe
      have hres := resolve_sound em r s (mk_strip _ _ _ _ _ h)
      refine ⟨_, ho, hr, h, ?_⟩
      rw [mk_row, hres.1]
  · simp [hr] at h

/-- **An expired strip is never served**: every servable strip is unexpired. -/
theorem expired_not_served (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (s : Strip)
    (h : s ∈ servable today f m) : expired today s = false := by
  obtain ⟨o, ho, hst, hs, _⟩ := servable_mem today f m s h
  obtain ⟨e, em, hem, hoe⟩ := stripsOf_mem today f m o ho
  unfold engineOuts at hoe
  split at hoe
  · simp at hoe; subst hoe; simp at hst
  · simp only [List.mem_map] at hoe
    obtain ⟨r, _, rfl⟩ := hoe
    exact mk_ready today e em r s hst hs

/-- **The files the console may serve are exactly row files**: a served strip is a row of the flag, its file is the name asked
for, it is not expired, and its run and expiry are the material's. -/
theorem serve_allowlist (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String) (s : Strip)
    (h : serve today f m file = some s) :
    s.row ∈ rows ∧ s.row.flag = f ∧ s.row.file = file ∧ expired today s = false ∧
      ∃ em, engMat m s.row.engine = some em ∧ em.run = some s.run ∧ em.expires = some s.expires ∧
        ∃ a, em.artifact = some a ∧ s.row.artifact ∈ names a := by
  unfold serve at h
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  obtain ⟨o, ho, _, hs, hr⟩ := servable_mem today f m s hm
  have hb := strip_belongs today f m o ho s.row hr
  have hmat := strip_material today f m o ho s hs
  rw [hb.2.2.2] at hmat
  exact ⟨hb.1, hb.2.1, by simpa using hp, expired_not_served today f m s hm, hmat⟩

/-- A file that is no row file is refused (nothing from the request reaches a path). -/
theorem serve_unknown (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (file : String)
    (h : ∀ r ∈ rows, r.file ≠ file) : serve today f m file = none := by
  cases hs : serve today f m file with
  | none => rfl
  | some s =>
    have := serve_allowlist today f m file s hs
    exact absurd this.2.2.1 (h s.row this.1)

/-- An expired strip is not served. -/
theorem expired_refused (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (s : Strip)
    (h : expired today s = true) : serve today f m s.row.file ≠ some s := by
  intro hs
  have := (serve_allowlist today f m s.row.file s hs).2.2.2.1
  simp [h] at this

/-- A missing strip without a row is returned only for an engine whose material is ready and for which no row of the flag exists. -/
theorem missing_only_without_rows (today : String) (f : Flag) (m : Option Gen.ReviewMaterial) (o : Out)
    (h : o ∈ stripsOf today f m) (hs : o.row = none) :
    o.state = .missing ∧ (engMat m o.engine).isSome ∧ ∀ r ∈ rows, ¬ (r.flag = f ∧ r.engine = o.engine) := by
  obtain ⟨e, em, hem, ho⟩ := stripsOf_mem today f m o h
  unfold engineOuts at ho
  split at ho
  · rename_i hnil
    simp only [List.mem_singleton] at ho; subst ho
    refine ⟨rfl, by simp [hem], fun r hr ⟨h1, h2⟩ => ?_⟩
    have : r ∈ rows.filter (fun r => r.flag == f && r.engine == e) := by simp [hr, h1, h2]
    rw [hnil] at this; simp at this
  · simp only [List.mem_map] at ho
    obtain ⟨r, _, rfl⟩ := ho
    rw [mk_row] at hs; simp at hs

-- the material of the canonical decision (what the console reads) and variants of it
private def earnF : Flag := ⟨"nav", "earn-no-transition"⟩
private def gm : Gen.ReviewMaterial := (Gen.lookDecisions.head?.bind (·.material)).getD ⟨{ state := .pending }, { state := .pending }⟩
private def mWk : Option Gen.ReviewMaterial := some { gm with chromium := { state := .pending } }
private def mCh : Option Gen.ReviewMaterial := some { gm with webkit := { state := .pending } }

-- the row files of the seed are unique (a name decides one row)
#guard (rows.map Row.file).eraseDups.length == rows.length
#guard (stripsOf "2026-10-21" earnF (some gm)).length == 8
#guard (stripsOf "2026-10-21" earnF mCh).length == 4
#guard (stripsOf "2026-10-21" earnF none).length == 0
-- run and expiry of every strip are the material's
#guard (stripsOf "2026-10-21" earnF (some gm)).all fun o => match o.row, o.strip with
  | some r, some s => s.run == (if r.engine == "chromium" then "39473950464" else "39530106935") &&
      s.expires == (if r.engine == "chromium" then "2026-11-19" else "2026-11-20")
  | _, _ => false
-- an engine whose material is ready but which has no row of the flag: one missing strip
#guard (stripsOf "2026-10-21" ⟨"nav", "other"⟩ mCh).map (·.state) == [.missing]
-- a row whose artifact the material does not name is missing and never served
#guard (stripsOf "2026-10-21" earnF (some { gm with webkit := { gm.webkit with artifact := some "frames-apple-390" } })).map (·.state)
  == [.ready, .ready, .ready, .ready, .ready, .missing, .ready, .missing]
#guard (serve "2026-10-21" earnF (some { gm with webkit := { gm.webkit with artifact := some "frames-apple-390" } })
  "playwright-webkit-1280-close.png").isNone
#guard (serve "2026-10-21" earnF (some gm) "playwright-webkit-1280-close.png").isSome
-- material ready without a run: all its rows are missing
#guard (stripsOf "2026-10-21" earnF (some { gm with webkit := { gm.webkit with run := none } })).map (·.state)
  == [.ready, .ready, .ready, .ready, .missing, .missing, .missing, .missing]
-- expiry day: the day before is ready, the day itself is expired (chromium 2026-11-19, webkit 2026-11-20)
#guard (servable "2026-11-18" earnF mCh).length == 4
#guard (servable "2026-11-19" earnF mCh).length == 0
#guard (stripsOf "2026-11-19" earnF mCh).all (·.state == .expired)
#guard (servable "2026-11-19" earnF (some gm)).length == 4
#guard (servable "2026-11-20" earnF (some gm)).length == 0
#guard (serve "2026-10-21" earnF (some gm) "chromium-390-open.png").isSome
#guard (serve "2026-10-21" earnF mCh "playwright-webkit-1280-close.png").isNone
#guard (serve "2026-10-21" earnF (some gm) "../x.png").isNone
#guard (serve "2026-10-21" ⟨"nav", "other"⟩ (some gm) "chromium-390-open.png").isNone

end Fw.Console.ReviewStrips
