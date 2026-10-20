import Fw.Console.PreviewArm

/-!
# Login return link (task preview-login-return)

An unauthenticated HTML request to a preview origin goes to the console login with a return reference; after the login
the owner lands on the same link. `redirect` decides at the preview origin, `landing` after the login.
-/

namespace Fw.Console.Preview.Return

open Fw.Console.Preview

/-- Longest path and query taken. -/
def maxLen : Nat := 2000

/-- Milliseconds a return reference lives. -/
def ttl : Nat := 600000

/-- Return references held at once. -/
def cap : Nat := 256

/-- A path or query character: ASCII letter or digit, or one of `. : , - _ @ = & / ?`. -/
def okChar (c : Char) : Bool :=
  c.isAlphanum || c == '.' || c == ':' || c == ',' || c == '-' || c == '_' || c == '@' || c == '=' || c == '&' || c == '/' || c == '?'

/-- A path and query that start with exactly one `/`, are bounded and hold only allowed characters. -/
def pathOk (s : String) : Bool :=
  s.startsWith "/" && !s.startsWith "//" && s.length ≤ maxLen && s.all okChar

/-- A host name as read from a validated `Host` header (no port): letters, digits, `.`, `-`, `[`, `]`, `:`. -/
def hostOk (h : String) : Bool :=
  !h.isEmpty && h.length ≤ 255 &&
    h.all fun c => c.isAlphanum || c == '.' || c == '-' || c == '[' || c == ']' || c == ':'

/-- A nonce: 16 to 64 characters of the URL-safe base64 alphabet. -/
def nonceOk (n : String) : Bool :=
  16 ≤ n.length && n.length ≤ 64 && n.all fun c => c.isAlphanum || c == '-' || c == '_'

/-- The requested link, without its origin: the local port it arrived on and its path and query. -/
structure Target where
  port : Nat
  pathq : String
deriving Repr, DecidableEq

/-- The preview id of a `/preview/<id>/...` path. -/
def previewId (pq : String) : String :=
  ((pq.drop 9).takeWhile fun c => c != '/' && c != '?').toString

/-- A link that may be returned to: a path in the allowlist on a live arm port, or a path of a live preview on the preview
port. The console port is never a target. -/
def accepts (live : List Pv) (consolePort : Nat) (previewPort : Option Nat) (t : Target) : Bool :=
  pathOk t.pathq && t.port != consolePort &&
    ((ports live).contains t.port ||
      (previewPort == some t.port && t.pathq.startsWith "/preview/" && live.any fun p => p.id == previewId t.pathq))

/-- The absolute link on `host`. -/
def urlOf (host : String) (t : Target) : String := "http://" ++ host ++ ":" ++ toString t.port ++ t.pathq

/-- The console login address for `host`, with a return reference when `keep`. -/
def loginUrl (host : String) (consolePort : Nat) (nonce : String) (keep : Bool) : String :=
  "http://" ++ host ++ ":" ++ toString consolePort ++ "/owner/login" ++ (if keep then "?r=" ++ nonce else "")

/-- What the preview origin does with a request the gate refused. -/
inductive Red where
  | deny
  | login (keep : Bool)
deriving Repr, DecidableEq

/-- Redirect an HTML request to the login (keeping the link when it is accepted); anything else stays refused. -/
def redirect (html : Bool) (host : String) (nonce : String) (live : List Pv) (consolePort : Nat) (previewPort : Option Nat)
    (t : Target) : Red :=
  if !html || !hostOk host then .deny
  else .login (nonceOk nonce && accepts live consolePort previewPort t)

/-- Where the owner goes after login. -/
inductive Land where
  | target (url : String)
  | builds
  | home
deriving Repr, DecidableEq

/-- The destination after a login: the held link when it is still accepted, the Builds tab when its preview has stopped,
the console home otherwise. -/
def landing (live : List Pv) (consolePort : Nat) (previewPort : Option Nat) (host : String) (now : Nat)
    (held : Option (Target × Nat)) : Land :=
  match held with
  | none => .home
  | some (t, issued) =>
    if issued + ttl < now || !hostOk host then .home
    else if accepts live consolePort previewPort t then .target (urlOf host t)
    else if pathOk t.pathq then .builds
    else .home

/-- The path a landing becomes (absolute links are returned as they are). -/
def Land.next : Land → String
  | .target u => u
  | .builds => "/?tab=builds&note=stopped"
  | .home => "/"

theorem all_mem {s : String} {f : Char → Bool} (h : s.all f = true) {c : Char} (hc : c ∈ s.toList) : f c = true := by
  simp at h
  exact h c hc

theorem pathOk_slash {s : String} (h : pathOk s = true) : s.startsWith "/" = true ∧ s.startsWith "//" = false := by
  simp only [pathOk, Bool.and_eq_true, Bool.not_eq_true'] at h
  exact ⟨h.1.1.1, h.1.1.2⟩

theorem okChar_plain {c : Char} (h : okChar c = true) :
    c ≠ '\r' ∧ c ≠ '\n' ∧ c ≠ '%' ∧ c ≠ '#' ∧ c ≠ '\\' ∧ c ≠ ' ' ∧ c ≠ '"' ∧ c ≠ '<' ∧ c ≠ '\'' := by
  simp only [okChar, Bool.or_eq_true, beq_iff_eq] at h
  have hn : ¬ c.isAlphanum = true → True := fun _ => trivial
  rcases h with h | h
  · refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> rintro rfl <;> revert h <;> decide
  · refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> rintro rfl <;> revert h <;> decide

/-- **No control or delimiter character in an accepted path**: CR, LF, `%`, `#`, `\`, space, quotes and `<` are all refused. -/
theorem pathOk_plain {s : String} (h : pathOk s = true) : ∀ c ∈ s.toList, c ≠ '\r' ∧ c ≠ '\n' ∧ c ≠ '%' ∧ c ≠ '#' ∧ c ≠ '\\' ∧ c ≠ ' ' ∧ c ≠ '"' ∧ c ≠ '<' ∧ c ≠ '\'' := by
  intro c hc
  simp only [pathOk, Bool.and_eq_true] at h
  have := all_mem h.2 hc
  exact okChar_plain this

theorem hostOk_plain {h : String} (hh : hostOk h = true) : ∀ c ∈ h.toList, c ≠ '/' ∧ c ≠ '@' ∧ c ≠ '?' ∧ c ≠ '#' ∧ c ≠ '\\' ∧ c ≠ '%' := by
  intro c hc
  simp only [hostOk, Bool.and_eq_true] at hh
  have := all_mem hh.2 hc
  simp only [Bool.or_eq_true, beq_iff_eq] at this
  rcases this with ((((h | h) | h) | h) | h) <;> refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> (try rintro rfl) <;> first | exact absurd h (by decide) | (revert h; decide) | skip

theorem nonceOk_plain {n : String} (h : nonceOk n = true) : ∀ c ∈ n.toList, c ≠ '&' ∧ c ≠ '#' ∧ c ≠ '/' ∧ c ≠ '%' ∧ c ≠ '?' := by
  intro c hc
  simp only [nonceOk, Bool.and_eq_true] at h
  have := all_mem h.2 hc
  simp only [Bool.or_eq_true, beq_iff_eq] at this
  rcases this with (h | h) | h <;> refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> (try rintro rfl) <;> first | exact absurd h (by decide) | (revert h; decide) | skip

/-- **An accepted link is on a live port.** The path is in the allowlist and the port is a live arm port or the preview port. -/
theorem accepts_sound {live : List Pv} {cp : Nat} {pp : Option Nat} {t : Target} (h : accepts live cp pp t = true) :
    pathOk t.pathq = true ∧ t.port ≠ cp ∧ (t.port ∈ ports live ∨ pp = some t.port) := by
  simp only [accepts, Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.contains_iff_mem, beq_iff_eq] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨h1, h2, ?_⟩
  rcases h3 with h | h
  · exact Or.inl h
  · exact Or.inr h.1.1

/-- **A link on an arm port of a live preview is accepted** (given a good path). -/
theorem accepts_arm {live : List Pv} {cp : Nat} {pp : Option Nat} {t : Target} (hp : pathOk t.pathq = true)
    (hn : t.port ≠ cp) (hl : t.port ∈ ports live) : accepts live cp pp t = true := by
  simp [accepts, hp, hn, hl]

/-- **A link on a port no live preview owns is refused**, unless it is the preview port. -/
theorem accepts_dead {live : List Pv} {cp : Nat} {t : Target} (hl : t.port ∉ ports live) :
    accepts live cp none t = false := by
  simp [accepts, hl]

/-- **The console port is never a target.** -/
theorem accepts_console {live : List Pv} {pp : Option Nat} {t : Target} : accepts live t.port pp t = false := by
  simp [accepts]

/-- **An API request stays refused**, whatever the link. -/
theorem redirect_api (host nonce : String) (live : List Pv) (cp : Nat) (pp : Option Nat) (t : Target) :
    redirect false host nonce live cp pp t = .deny := by
  simp [redirect]

/-- **A bad host name is refused** (no login address can be built). -/
theorem redirect_bad_host (nonce : String) (live : List Pv) (cp : Nat) (pp : Option Nat) (t : Target) (host : String)
    (h : hostOk host = false) : redirect true host nonce live cp pp t = .deny := by
  simp [redirect, h]

/-- **A link is kept only if it is accepted** (and the nonce is well formed). -/
theorem redirect_keep_sound {host nonce : String} {live : List Pv} {cp : Nat} {pp : Option Nat} {t : Target}
    (h : redirect true host nonce live cp pp t = .login true) : accepts live cp pp t = true ∧ nonceOk nonce = true := by
  unfold redirect at h
  by_cases hh : (!true || !hostOk host) = true
  · have : hostOk host = false := by simpa using hh
    simp [this] at h
  · have : hostOk host = true := by simpa using hh
    simp [this] at h
    exact ⟨h.2, h.1⟩

/-- **An accepted link is kept.** -/
theorem redirect_keeps {host nonce : String} {live : List Pv} {cp : Nat} {pp : Option Nat} {t : Target}
    (hh : hostOk host = true) (hn : nonceOk nonce = true) (ha : accepts live cp pp t = true) :
    redirect true host nonce live cp pp t = .login true := by
  simp [redirect, hh, hn, ha]

/-- **A refused link goes to the login without a return.** -/
theorem redirect_plain {host nonce : String} {live : List Pv} {cp : Nat} {pp : Option Nat} {t : Target}
    (hh : hostOk host = true) (ha : accepts live cp pp t = false) :
    redirect true host nonce live cp pp t = .login false := by
  simp [redirect, hh, ha]

/-- **No held link, no destination: home.** -/
theorem landing_none (live : List Pv) (cp : Nat) (pp : Option Nat) (host : String) (now : Nat) :
    landing live cp pp host now none = .home := rfl

/-- **An expired reference goes home.** -/
theorem landing_expired {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now issued : Nat} {t : Target}
    (h : issued + ttl < now) : landing live cp pp host now (some (t, issued)) = .home := by
  simp [landing, h]

/-- **A bad host name goes home.** -/
theorem landing_bad_host {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now issued : Nat} {t : Target}
    (h : hostOk host = false) : landing live cp pp host now (some (t, issued)) = .home := by
  simp [landing, h]

/-- **A link that is still accepted is the destination.** -/
theorem landing_live {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now issued : Nat} {t : Target}
    (hf : ¬ issued + ttl < now) (hh : hostOk host = true) (ha : accepts live cp pp t = true) :
    landing live cp pp host now (some (t, issued)) = .target (urlOf host t) := by
  simp [landing, hf, hh, ha]

/-- **A stopped preview goes to the Builds tab.** -/
theorem landing_stopped {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now issued : Nat} {t : Target}
    (hf : ¬ issued + ttl < now) (hh : hostOk host = true) (ha : accepts live cp pp t = false) (hp : pathOk t.pathq = true) :
    landing live cp pp host now (some (t, issued)) = .builds := by
  simp [landing, hf, hh, ha, hp]

/-- **A link outside the allowlist goes home.** -/
theorem landing_invalid {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now issued : Nat} {t : Target}
    (hf : ¬ issued + ttl < now) (hh : hostOk host = true) (ha : accepts live cp pp t = false) (hp : pathOk t.pathq = false) :
    landing live cp pp host now (some (t, issued)) = .home := by
  simp [landing, hf, hh, ha, hp]

/-- **No open redirect.** A landing that is an absolute link is built from a held link that is accepted against the current
table, on the validated host. -/
theorem landing_sound {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now : Nat} {held : Option (Target × Nat)}
    {u : String} (h : landing live cp pp host now held = .target u) :
    ∃ t issued, held = some (t, issued) ∧ accepts live cp pp t = true ∧ hostOk host = true ∧ u = urlOf host t := by
  unfold landing at h
  cases held with
  | none => simp at h
  | some p =>
    obtain ⟨t, issued⟩ := p
    simp only at h
    by_cases h1 : (decide (issued + ttl < now) || !hostOk host) = true
    · simp [h1] at h
    · simp only [h1] at h
      have hh : hostOk host = true := by
        simp only [Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h1
        cases hc : hostOk host <;> simp_all
      by_cases h2 : accepts live cp pp t = true
      · simp only [h2, ↓reduceIte] at h
        exact ⟨t, issued, rfl, h2, hh, (Land.target.inj h).symm⟩
      · have h2' : accepts live cp pp t = false := by simpa using h2
        simp only [h2'] at h
        by_cases hp : pathOk t.pathq = true <;> simp [hp] at h

/-- **The authority of a returned link is the validated host and a live port**: the host holds no delimiter, the next
character after the port is `/`, and the path holds none of CR, LF, `%`, `#`, `\`. -/
theorem landing_url_shape {live : List Pv} {cp : Nat} {pp : Option Nat} {host : String} {now : Nat} {held : Option (Target × Nat)}
    {u : String} (h : landing live cp pp host now held = .target u) :
    ∃ t : Target, u = "http://" ++ host ++ ":" ++ toString t.port ++ t.pathq ∧ t.pathq.startsWith "/" = true ∧
      t.pathq.startsWith "//" = false ∧ (∀ c ∈ host.toList, c ≠ '/' ∧ c ≠ '@' ∧ c ≠ '?' ∧ c ≠ '#' ∧ c ≠ '\\' ∧ c ≠ '%') ∧
      (∀ c ∈ t.pathq.toList, c ≠ '\r' ∧ c ≠ '\n' ∧ c ≠ '%' ∧ c ≠ '#' ∧ c ≠ '\\') ∧ (t.port ∈ ports live ∨ pp = some t.port) := by
  obtain ⟨t, issued, _, ha, hh, rfl⟩ := landing_sound h
  obtain ⟨hp, _, hl⟩ := accepts_sound ha
  obtain ⟨s1, s2⟩ := pathOk_slash hp
  refine ⟨t, rfl, s1, s2, hostOk_plain hh, fun c hc => ?_, hl⟩
  have := pathOk_plain hp c hc
  exact ⟨this.1, this.2.1, this.2.2.1, this.2.2.2.1, this.2.2.2.2.1⟩

end Fw.Console.Preview.Return
