/-! What may leave this machine in an oracle question: every state text goes through `redact`. -/
namespace Fw.Oracle

/-- The home-path prefixes: macOS and Linux homes. -/
def homePrefixes : List (List Char) := ["/Users/".toList, "/home/".toList, "\\Users\\".toList, "-Users-".toList]

def tokenPrefixes : List (List Char) :=
  ["ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "sk-", "sk_", "xoxb-", "xoxp-", "AKIA", "Bearer "].map
    String.toList

def segChar (c : Char) : Bool := !("/\\ \t\r\n\"'`:,;)]}<>".toList.contains c)

def wordChar (c : Char) : Bool := c.isAlphanum || "._%+-".toList.contains c

def domainChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '-'

def tokChar (c : Char) : Bool := c.isAlphanum || "_-.+/=".toList.contains c

def alnumHead : List Char → Bool
  | c :: _ => c.isAlphanum
  | [] => false

def matchHome (l : List Char) : Option (List Char × List Char) :=
  homePrefixes.findSome? fun p =>
    if p.isPrefixOf l then some (['~'], (l.drop p.length).dropWhile segChar) else none

def lowerL (l : List Char) : List Char := l.map Char.toLower

def matchName (names : List (List Char)) (a : Bool) (l : List Char) : Option (List Char × List Char) :=
  if a then none else
  names.findSome? fun n =>
    if 3 ≤ n.length && (lowerL n).isPrefixOf (lowerL (l.take n.length)) && !alnumHead (l.drop n.length) then
      some ("<user>".toList, l.drop n.length)
    else none

def matchToken (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else
  tokenPrefixes.findSome? fun p =>
    if p.isPrefixOf l then
      let r := l.drop p.length
      let b := r.takeWhile tokChar
      if 8 ≤ b.length then some ("<token>".toList, r.drop b.length) else none
    else none

def matchEmail (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else
  let u := l.takeWhile wordChar
  if u.isEmpty then none else
  match l.drop u.length with
  | '@' :: r =>
    let d := r.takeWhile domainChar
    if 3 ≤ d.length && d.contains '.' && d.head? != some '.' then some ("<email>".toList, r.drop d.length) else none
  | _ => none

/-- One to three digits at the head: the text after them. -/
def octet (l : List Char) : Option (List Char) :=
  let g := l.takeWhile Char.isDigit
  if 1 ≤ g.length && g.length ≤ 3 then some (l.drop g.length) else none

/-- A dot at the head: the text after it. -/
def dot : List Char → Option (List Char)
  | '.' :: r => some r
  | _ => none

def matchIp (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else do
  let r ← octet l
  let r ← dot r
  let r ← octet r
  let r ← dot r
  let r ← octet r
  let r ← dot r
  let r ← octet r
  match r with
  | c :: _ => if c.isDigit then none else some ("<ip>".toList, r)
  | [] => some ("<ip>".toList, r)

/-- The first rule that matches at the head. -/
def rule (names : List (List Char)) (w a : Bool) (l : List Char) : Option (List Char × List Char) :=
  matchHome l <|> matchName names a l <|> matchToken w l <|> matchEmail w l <|> matchIp w l

/-- The pass with fuel `f`: at each position the first matching rule's replacement. -/
def go (names : List (List Char)) : Nat → Bool → Bool → List Char → List Char
  | 0, _, _, l => l
  | _ + 1, _, _, [] => []
  | f + 1, w, a, c :: cs =>
    match rule names w a (c :: cs) with
    | some (o, r) => o ++ go names f false false r
    | none => c :: go names f (wordChar c) c.isAlphanum cs

/-- The scrub pass over a text, with fuel its length. -/
def scrub (names : List String) (s : String) : String :=
  String.ofList (go (names.map String.toList) s.toList.length false false s.toList)

/-- Does `p` occur in `l` as a contiguous segment? -/
def occurs (p : List Char) : List Char → Bool
  | [] => p.isPrefixOf []
  | c :: cs => p.isPrefixOf (c :: cs) || occurs p cs

theorem occurs_iff (p : List Char) : ∀ l : List Char, occurs p l = true ↔ ∃ u v, l = u ++ p ++ v
  | [] => by
    simp only [occurs, List.isPrefixOf_iff_prefix]
    constructor
    · rintro ⟨t, ht⟩; exact ⟨[], t, by simp [ht]⟩
    · rintro ⟨u, v, h⟩
      have : u = [] ∧ p = [] ∧ v = [] := by simpa [eq_comm] using h
      exact ⟨[], by simp [this.2.1]⟩
  | c :: cs => by
    simp only [occurs, Bool.or_eq_true, List.isPrefixOf_iff_prefix, occurs_iff p cs]
    constructor
    · rintro (⟨t, ht⟩ | ⟨u, v, h⟩)
      · exact ⟨[], t, by simp [ht]⟩
      · exact ⟨c :: u, v, by simp [h]⟩
    · rintro ⟨u, v, h⟩
      cases u with
      | nil => exact .inl ⟨v, by simp at h; simp [h]⟩
      | cons d u =>
        simp only [List.cons_append, List.cons.injEq] at h
        exact .inr ⟨u, v, by simp [h.2]⟩

def hasHome (s : String) : Bool := homePrefixes.any fun p => occurs p s.toList

/-- A clean text: the pass changes nothing and no home-path prefix occurs. -/
def clean (names : List String) (t : String) : Bool := scrub names t == t && !hasHome t

/-- Redaction (the `oracle.redact` op. -/
def redact (names : List String) (s : String) : String :=
  let t := scrub names s
  if clean names t then t else ""

theorem clean_empty (names : List String) : clean names "" = true := by
  simp [clean, scrub, go, hasHome, homePrefixes, occurs, String.ofList_nil]

theorem redact_idem (names : List String) (s : String) : redact names (redact names s) = redact names s := by
  unfold redact
  by_cases h : clean names (scrub names s) = true
  · simp only [h, ite_true]
    have hs : scrub names (scrub names s) = scrub names s := by
      simp only [clean, Bool.and_eq_true, beq_iff_eq] at h; exact h.1
    rw [hs]; simp [h]
  · have he : scrub names "" = "" := by
      have := clean_empty names; simp only [clean, Bool.and_eq_true, beq_iff_eq] at this; exact this.1
    simp [h, he, clean_empty]

theorem no_home_path (names : List String) (s : String) :
    ∀ p ∈ homePrefixes, ∀ u v : List Char, (redact names s).toList ≠ u ++ p ++ v := by
  have hc : clean names (redact names s) = true := by
    unfold redact
    by_cases h : clean names (scrub names s) = true
    · simp [h]
    · simp [h, clean_empty]
  simp only [clean, Bool.and_eq_true, Bool.not_eq_true', hasHome, List.any_eq_false] at hc
  intro p hp u v he
  have := (occurs_iff _ _).mpr ⟨u, v, he⟩
  exact absurd this (by simpa using hc.2 p hp)

theorem no_home_forms (names : List String) (s : String) (u v : List Char) :
    (redact names s).toList ≠ u ++ "/Users/".toList ++ v ∧ (redact names s).toList ≠ u ++ "/home/".toList ++ v ∧
      (redact names s).toList ≠ u ++ "\\Users\\".toList ++ v ∧ (redact names s).toList ≠ u ++ "-Users-".toList ++ v :=
  ⟨no_home_path names s _ (by simp [homePrefixes]) u v, no_home_path names s _ (by simp [homePrefixes]) u v,
   no_home_path names s _ (by simp [homePrefixes]) u v, no_home_path names s _ (by simp [homePrefixes]) u v⟩

#guard redact [] "/Users/example/src/x.ts:12" == "~/src/x.ts:12"
#guard redact [] "cd /home/bob && ls" == "cd ~ && ls"
#guard redact [] "mail first.b+ci@example.com now" == "mail <email> now"
#guard redact [] "token ghp_ABCDEFGH12345678 end" == "token <token> end"
#guard redact [] "Authorization: Bearer abcdefgh.ijk" == "Authorization: <token>"
#guard redact [] "sk-short" == "sk-short"
#guard redact [] "host 203.0.113.20:8080 up" == "host <ip>:8080 up"
#guard redact [] "version 1.2.3 and 2026-10-18T06:07:14.4719238Z" == "version 1.2.3 and 2026-10-18T06:07:14.4719238Z"
#guard redact ["alice"] "by alice, not malice or alicex" == "by <user>, not malice or alicex"
#guard redact ["Alice"] "by alice and ALICE and Alice." == "by <user> and <user> and <user>."
#guard redact ["al.ice@example.org"] "mail AL.ICE@EXAMPLE.ORG now" == "mail <user> now"
#guard redact ["ab"] "ab cd" == "ab cd"
#guard redact ["alice"] "/tmp/claude-501/-Users-example-source-fastwork/x" == "/tmp/claude-501/~/x"
#guard redact ["alice"] "user_alice wrote" == "user_<user> wrote"
#guard redact ["alice"] "authored-by-alice" == "authored-by-<user>"
#guard redact ["alice"] "MacBook-Pro-of-Alice.local" == "MacBook-Pro-of-<user>.local"
#guard redact ["alice"] "x.alice and 50%alice" == "x.<user> and 50%<user>"
#guard redact ["alice"] "malice alice2 alicex" == "malice alice2 alicex"
#guard redact [] "C:\\Users\\alice\\src" == "C:~\\src"
#guard redact [] "-Users-" == "~"
#guard redact [] "a/Users-b" == "a/Users-b"
#guard redact [] "" == ""
#guard redact [] "x/Users/" == "x~"
#guard redact ["user"] "user" == ""
#guard redact [] (redact [] "/Users/x/b mail a@example.org 203.0.113.1") == redact [] "/Users/x/b mail a@example.org 203.0.113.1"

/-! ## Size caps -/

/-- The most characters a state line may have. -/
def lineCap : Nat := 500

/-- The most UTF-8 bytes the lines of a state may total (32 KiB). -/
def stateCap : Nat := 32768

/-- The most UTF-8 bytes of a reply text stored in the answer log (64 KiB). -/
def replyCap : Nat := 65536

def cutMarker : String := " [truncated]"

/-- The UTF-8 size of a text: the sum of its characters' encoded sizes. -/
def bytes (s : String) : Nat := (s.toList.map Char.utf8Size).sum

def capChars (m : Nat) (s : String) : String :=
  if s.length ≤ m then s else String.ofList (s.toList.take (m - cutMarker.length)) ++ cutMarker

theorem capChars_length (m : Nat) (s : String) (h : cutMarker.length ≤ m) : (capChars m s).length ≤ m := by
  unfold capChars
  split
  · assumption
  · simp only [String.length_append, String.length_ofList, List.length_take, String.length_toList]
    omega

def takeBytes : Nat → List Char → List Char
  | _, [] => []
  | b, c :: cs => if c.utf8Size ≤ b then c :: takeBytes (b - c.utf8Size) cs else []

theorem takeBytes_size : ∀ (b : Nat) (l : List Char), ((takeBytes b l).map Char.utf8Size).sum ≤ b
  | _, [] => by simp [takeBytes]
  | b, c :: cs => by
    unfold takeBytes
    split
    · have := takeBytes_size (b - c.utf8Size) cs
      simp only [List.map_cons, List.sum_cons]; omega
    · simp

def capBytes (m : Nat) (s : String) : String :=
  if bytes s ≤ m then s else String.ofList (takeBytes (m - bytes cutMarker) s.toList) ++ cutMarker

theorem capBytes_size (m : Nat) (s : String) (h : bytes cutMarker ≤ m) : bytes (capBytes m s) ≤ m := by
  unfold capBytes
  split
  · assumption
  · have := takeBytes_size (m - bytes cutMarker) s.toList
    simp only [bytes, String.toList_append, String.toList_ofList, List.map_append, List.sum_append] at h this ⊢
    omega

/-- The stored form of a reply text (the `oracle.store` op): cut to 64 KiB. -/
def storedReply (s : String) : String := capBytes replyCap s

theorem storedReply_size (s : String) : bytes (storedReply s) ≤ replyCap :=
  capBytes_size replyCap s (by decide)

/-- One state line, redacted and capped. -/
def redactLine (names : List String) (x : String) : String :=
  let t := redact names (capChars lineCap x)
  if t.length ≤ lineCap then t else
  let u := capChars lineCap t
  if clean names u then u else ""

theorem redact_of_clean (names : List String) (u : String) (h : clean names u = true) : redact names u = u := by
  have hs : scrub names u = u := by simp only [clean, Bool.and_eq_true, beq_iff_eq] at h; exact h.1
  simp [redact, hs, h]

theorem redact_empty (names : List String) : redact names "" = "" := redact_of_clean names "" (clean_empty names)

theorem redactLine_fix (names : List String) (x : String) :
    redact names (redactLine names x) = redactLine names x := by
  unfold redactLine
  simp only
  split
  · exact redact_idem _ _
  · split
    · rename_i hc; exact redact_of_clean _ _ hc
    · exact redact_empty names

theorem redactLine_length (names : List String) (x : String) : (redactLine names x).length ≤ lineCap := by
  unfold redactLine
  simp only
  split
  · assumption
  · split
    · exact capChars_length _ _ (by decide)
    · simp [lineCap]

def linesBytes (L : List String) : Nat := (L.map bytes).sum

def keepLines : Nat → List String → List String
  | _, [] => []
  | b, x :: xs => if bytes x ≤ b then x :: keepLines (b - bytes x) xs else []

theorem keepLines_bytes : ∀ (b : Nat) (L : List String), linesBytes (keepLines b L) ≤ b
  | _, [] => by simp [keepLines, linesBytes]
  | b, x :: xs => by
    unfold keepLines
    split
    · have := keepLines_bytes (b - bytes x) xs
      simp only [linesBytes, List.map_cons, List.sum_cons] at this ⊢; omega
    · simp [linesBytes]

theorem keepLines_mem : ∀ (b : Nat) (L : List String) (x : String), x ∈ keepLines b L → x ∈ L
  | _, [], _, h => by simp [keepLines] at h
  | b, y :: ys, x, h => by
    unfold keepLines at h
    split at h
    · rcases List.mem_cons.mp h with rfl | h'
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (keepLines_mem _ ys x h')
    · simp at h

/-- Cap the lines of a state to `b` bytes in total. -/
def capState : Nat → List (String × List String) → List (String × List String)
  | _, [] => []
  | b, (k, L) :: S =>
    let L' := (keepLines b L.reverse).reverse
    (k, L') :: capState (b - linesBytes L') S

/-- The UTF-8 size of the lines of a state (field names not counted). -/
def stateBytes (S : List (String × List String)) : Nat := (S.map fun kl => linesBytes kl.2).sum

theorem capState_bytes : ∀ (b : Nat) (S : List (String × List String)), stateBytes (capState b S) ≤ b
  | _, [] => by simp [capState, stateBytes]
  | b, (k, L) :: S => by
    have h1 := keepLines_bytes b L.reverse
    have hr : linesBytes (keepLines b L.reverse).reverse = linesBytes (keepLines b L.reverse) := by
      simp [linesBytes, List.map_reverse, List.sum_reverse]
    have h2 := capState_bytes (b - linesBytes (keepLines b L.reverse).reverse) S
    simp only [capState, stateBytes, List.map_cons, List.sum_cons] at h2 ⊢
    omega

theorem capState_mem : ∀ (b : Nat) (S : List (String × List String)) (kl : String × List String) (x : String),
    kl ∈ capState b S → x ∈ kl.2 → ∃ L, (kl.1, L) ∈ S ∧ x ∈ L
  | _, [], _, _, h, _ => by simp [capState] at h
  | b, (k, L) :: S, kl, x, h, hx => by
    simp only [capState, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨L, List.mem_cons_self, by
        simpa using keepLines_mem b L.reverse x (by simpa using hx)⟩
    · obtain ⟨L', h1, h2⟩ := capState_mem _ S kl x h hx
      exact ⟨L', List.mem_cons_of_mem _ h1, h2⟩

#guard (capChars 20 "short") == "short"
#guard (capChars 20 "0123456789abcdefghijXYZ") == "01234567 [truncated]"
#guard bytes "aé😀" == 7
#guard capBytes 14 "ab😀cd" == "ab😀cd" && capBytes 14 "ab😀cdefghijklm" == "ab [truncated]"
#guard (redactLine [] (String.ofList (List.replicate 600 'a'))).length == 500
#guard redactLine [] "/Users/example/x" == "~/x"
#guard capState 10 [("a", ["12345"]), ("log", ["1", "22", "333", "4444"])] ==
  [("a", ["12345"]), ("log", ["4444"])]
#guard capState 10 [("log", ["xx", "toolongline", "yy"])] == [("log", ["yy"])]

/-- A flat question state: field name to lines of text (a one-line field is a one-element list). -/
abbrev State := List (String × List String)

/-- Redact and cap every line of every field (field names are ours and are kept), then cap the state to 32 KiB. -/
def redactState (names : List String) (st : State) : State :=
  capState stateCap (st.map fun (k, ls) => (k, ls.map (redactLine names)))

/-- A state is redacted when every line is a fixed point of `redact` and at most 500 characters. -/
def isRedacted (names : List String) (st : State) : Bool :=
  st.all (fun (_, ls) => ls.all fun x => redact names x == x && decide (x.length ≤ lineCap)) &&
    decide (stateBytes st ≤ stateCap)

theorem redactState_redacted (names : List String) (st : State) : isRedacted names (redactState names st) = true := by
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq]
  refine ⟨fun kl hkl x hx => ?_, capState_bytes _ _⟩
  obtain ⟨L, hL, hxL⟩ := capState_mem _ _ kl x hkl hx
  obtain ⟨⟨k', L0⟩, _, he⟩ := List.mem_map.mp hL
  simp only [Prod.mk.injEq] at he
  obtain ⟨_, rfl⟩ := he
  obtain ⟨y, _, rfl⟩ := List.mem_map.mp hxL
  exact ⟨redactLine_fix names y, redactLine_length names y⟩

theorem redacted_caps (names : List String) (st : State) (h : isRedacted names st = true) :
    (∀ kl ∈ st, ∀ x ∈ kl.2, x.length ≤ lineCap) ∧ stateBytes st ≤ stateCap := by
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  exact ⟨fun kl hkl x hx => (h.1 kl hkl x hx).2, h.2⟩

theorem redacted_no_home (names : List String) (st : State) (h : isRedacted names st = true) :
    ∀ kl ∈ st, ∀ x ∈ kl.2, ∀ p ∈ homePrefixes, ∀ u v : List Char, x.toList ≠ u ++ p ++ v := by
  intro kl hkl x hx p hp u v
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  have hr : redact names x = x := (h.1 kl hkl x hx).1
  rw [← hr]; exact no_home_path names x p hp u v

end Fw.Oracle
