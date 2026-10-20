/-!
# Render guard: `fw land` refuses a branch whose history writes a media file outside `snapshot/`
Op `console.landRenderGuard` over the `git log -z --name-status` tokens of `main..branch`; golden `golden/land/render-guard.jsonl`.
-/
namespace Fw.Land.RenderGuard

/-- The media classes the guard refuses. -/
inductive Media | image | font | video | audio
  deriving DecidableEq, Repr

/-- The wire name of a media class. -/
def Media.name : Media → String
  | .image => "image" | .font => "font" | .video => "video" | .audio => "audio"

/-- The one extension table: lower-case file extension to media class. -/
def table : List (String × Media) :=
  (["png", "jpg", "jpeg", "jpe", "jfif", "pjpeg", "pjp", "gif", "webp", "avif", "svg", "svgz", "ico", "cur", "bmp", "tif", "tiff",
    "heic", "heif", "apng", "jxl", "jp2", "psd", "raw", "dng"].map (·, Media.image)) ++
  (["woff", "woff2", "ttf", "otf", "eot", "ttc", "pfb", "pfm"].map (·, Media.font)) ++
  (["mp4", "m4v", "webm", "mov", "mkv", "avi", "ogv", "mpg", "mpeg", "wmv", "flv", "3gp", "3g2"].map (·, Media.video)) ++
  (["mp3", "wav", "ogg", "oga", "m4a", "aac", "flac", "opus", "weba", "aif", "aiff", "mid", "midi", "wma", "amr"].map (·, Media.audio))

/-- The lower-case text after the last `.` of the last path segment, or `""` when that segment has no `.`. -/
def ext (p : String) : String :=
  let base := ((p.splitOn "/").getLast?).getD p
  match base.splitOn "." with
  | [] | [_] => ""
  | parts => (parts.getLast?.getD "").toLower

/-- The media class of a path, decided by its extension alone. -/
def mediaOf (p : String) : Option Media := table.lookup (ext p)

/-- A path under `snapshot/`, the one place Fastwork material enters git. -/
def inSnapshot (p : String) : Bool := p.startsWith "snapshot/"

/-- An allowlist entry: one exact path or every path under a directory, each with its reason. -/
inductive Allow
  | exact (path reason : String)
  | under (dir reason : String)

/-- Does the entry admit the path? -/
def Allow.covers : Allow → String → Bool
  | .exact q _, p => p == q
  | .under d _, p => p.startsWith (d ++ "/")

/-- The allowlist; empty because `git ls-files` on main (2026-10-21) lists no media file outside `snapshot/`. -/
def allowlist : List Allow := []

/-- A `git log --name-status` status letter. -/
inductive Status | added | modified | typeChanged | removed | other
  deriving DecidableEq, Repr

/-- The status of a letter; a letter the guard does not know is `other`. -/
def Status.ofLetter : String → Status
  | "A" => .added | "M" => .modified | "T" => .typeChanged | "D" => .removed | _ => .other

/-- Does the commit store a blob at the path? Every status but a removal does. -/
def Status.writes : Status → Bool
  | .removed => false
  | _ => true

/-- One path one commit touched. -/
structure Change where
  commit : String
  path : String
  status : Status

/-- A refused path: its commit, its path and its media class. -/
structure Hit where
  commit : String
  path : String
  media : Media
  deriving DecidableEq, Repr

/-- The refusal one change causes, if any. -/
def hit? (al : List Allow) (c : Change) : Option Hit :=
  if c.status.writes && !inSnapshot c.path && !al.any (·.covers c.path) then
    (mediaOf c.path).map fun m => ⟨c.commit, c.path, m⟩
  else none

/-- Every refused path of a history, in log order. -/
def hits (al : List Allow) (cs : List Change) : List Hit := cs.filterMap (hit? al)

/-- Is the land refused? -/
def refuses (al : List Allow) (cs : List Change) : Bool := !(hits al cs).isEmpty

/-- The parser state: the current commit and the status read just before a path. -/
structure PState where
  commit : String := ""
  pending : Option Status := none
  out : List Change := []

/-- Read one `-z` token of `git log -z --name-status --format='commit %H'`. -/
def step (s : PState) (t : String) : PState :=
  match s.pending with
  | some st => { s with pending := none, out := ⟨s.commit, t, st⟩ :: s.out }
  | none =>
    let u := (t.dropWhile (· == '\n')).toString
    if u.startsWith "commit " then { s with commit := (u.drop 7).toString }
    else if u.isEmpty then s
    else { s with pending := some (Status.ofLetter u) }

/-- The changes of a `-z` log split at its NUL bytes. -/
def parse (ts : List String) : List Change := (ts.foldl step {}).out.reverse

/-- The land's decision over the log tokens, with the canonical allowlist. -/
def guard (ts : List String) : List Hit := hits allowlist (parse ts)

/-! ## Theorems -/

theorem hits_append (al : List Allow) (a b : List Change) : hits al (a ++ b) = hits al a ++ hits al b := by
  simp [hits, List.filterMap_append]

theorem refuses_append (al : List Allow) (a b : List Change) :
    refuses al (a ++ b) = (refuses al a || refuses al b) := by
  simp only [refuses, hits_append]; cases hits al a <;> simp

theorem refusal_survives_later (al : List Allow) (a later : List Change) (h : refuses al a = true) :
    refuses al (a ++ later) = true := by
  simp [refuses_append, h]

theorem removal_hits_none (al : List Allow) (c : Change) (h : c.status = .removed) : hit? al c = none := by
  simp [hit?, h, Status.writes]

theorem removal_keeps_refusal (al : List Allow) (a rm : List Change) (h : ∀ c ∈ rm, c.status = .removed) :
    hits al (a ++ rm) = hits al a := by
  rw [hits_append]
  have : hits al rm = [] := by
    simp only [hits, List.filterMap_eq_nil_iff]
    intro c hc; exact removal_hits_none al c (h c hc)
  simp [this]

theorem allowed_hit_none (al : List Allow) (c : Change) (h : al.any (·.covers c.path) = true) : hit? al c = none := by
  simp [hit?, h]

theorem allowed_never_refuses (al : List Allow) (cs : List Change) (h : ∀ c ∈ cs, al.any (·.covers c.path) = true) :
    refuses al cs = false := by
  have : hits al cs = [] := by
    simp only [hits, List.filterMap_eq_nil_iff]
    intro c hc; exact allowed_hit_none al c (h c hc)
  simp [refuses, this]

theorem snapshot_hit_none (al : List Allow) (c : Change) (h : inSnapshot c.path = true) : hit? al c = none := by
  simp [hit?, h]

theorem snapshot_never_refuses (al : List Allow) (cs : List Change) (h : ∀ c ∈ cs, inSnapshot c.path = true) :
    refuses al cs = false := by
  have : hits al cs = [] := by
    simp only [hits, List.filterMap_eq_nil_iff]
    intro c hc; exact snapshot_hit_none al c (h c hc)
  simp [refuses, this]

theorem nonmedia_hit_none (al : List Allow) (c : Change) (h : mediaOf c.path = none) : hit? al c = none := by
  unfold hit?; split <;> simp [h]

theorem media_hit (al : List Allow) (c : Change) (m : Media) (hw : c.status.writes = true) (hs : inSnapshot c.path = false)
    (ha : al.any (·.covers c.path) = false) (hm : mediaOf c.path = some m) : hit? al c = some ⟨c.commit, c.path, m⟩ := by
  simp [hit?, hw, hs, ha, hm]

theorem media_refuses (al : List Allow) (a b : List Change) (c : Change) (m : Media) (hw : c.status.writes = true)
    (hs : inSnapshot c.path = false) (ha : al.any (·.covers c.path) = false) (hm : mediaOf c.path = some m) :
    refuses al (a ++ c :: b) = true := by
  have h1 : refuses al [c] = true := by simp [refuses, hits, media_hit al c m hw hs ha hm]
  have : a ++ c :: b = a ++ [c] ++ b := by simp
  rw [this, refuses_append, refuses_append, h1]; simp

theorem exact_covers (q r : String) : (Allow.exact q r).covers q = true := by simp [Allow.covers]

theorem under_covers (d r p : String) (h : p.startsWith (d ++ "/") = true) : (Allow.under d r).covers p = true := by
  simp [Allow.covers, h]

#guard ext "results/a.PNG" == "png"
#guard ext "a.b/Makefile" == ""
#guard ext "x.png.gz" == "gz"
#guard mediaOf "apps/site/public/f.woff2" == some .font
#guard mediaOf "docs/a.md" == none
#guard mediaOf "apps/x.ts" == none
#guard mediaOf "clip.webm" == some .video
#guard mediaOf "a.mp3" == some .audio
#guard inSnapshot "snapshot/fastwork.co/a.png" && !inSnapshot "snapshots/a.png" && !inSnapshot "x/snapshot/a.png"
#guard (Allow.under "results/ok" "r").covers "results/ok/a.png" && !(Allow.under "results/ok" "r").covers "results/okx/a.png"
#guard (parse ["commit c1", "\nA", "results/a b.png", "M", "src/x.ts", "commit c2", "commit c3", "\nD", "results/a b.png", ""]).map (·.path)
  == ["results/a b.png", "src/x.ts", "results/a b.png"]
#guard guard ["commit c1", "\nA", "results/hero.png", "commit c2", "\nD", "results/hero.png", ""]
  == [⟨"c1", "results/hero.png", .image⟩]
#guard guard ["commit c1", "\nA", "snapshot/a.png", "A", "src/a.ts", ""] == []
#guard guard ["commit c1", "\nA", "commit x.png", ""] == [⟨"c1", "commit x.png", .image⟩]
#guard guard ["commit c1", "\nX", "a.ttf", ""] == [⟨"c1", "a.ttf", .font⟩]

end Fw.Land.RenderGuard
