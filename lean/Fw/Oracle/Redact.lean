/-!
# Fw.Oracle.Redact: what may leave this machine in an oracle question

Before a state is sent to the model, every text of it goes through `redact`. One left-to-right pass (`scrub`)
replaces:
- a home path `/Users/<x>`, `/home/<x>`, `\Users\<x>` or the dash-encoded `-Users-<x>` of a project directory (the
  segment after the prefix) by `~`;
- a user name given by the caller (the client passes `git config user.name` and its words, `git config user.email`
  and the login name), compared without ASCII case and bounded by non-alphanumerics (so `-alice`, `_alice` and
  `.alice` match, `malice` does not), by `<user>`;
- a token of a known key shape (`ghp_ gho_ ghu_ ghs_ ghr_ github_pat_ sk- sk_ xoxb- xoxp- AKIA`, `Bearer `) followed
  by at least 8 token characters, by `<token>`;
- an e-mail address `name@example.com` by `<email>`; a dotted IPv4 address by `<ip>`.

`redact` then keeps the scrubbed text only if it is *clean*: a fixed point of the pass and free of home paths;
otherwise it withholds the whole text (the empty string). That check makes the two guarantees hold for every input,
not just the inputs the pass was tested on: `redact_idem` and `no_home_path`. The pass itself is best-effort for
names, tokens, e-mails and addresses (the `#guard`s below show the cases it covers).

Size caps (round-1 review): every state line is at most 500 characters (`redactLine_length`), the lines of a state
total at most 32 KiB in UTF-8 bytes (`capState_bytes`), and a stored reply at most 64 KiB (`capBytes_size`). A text
over a cap is cut and ends with the marker ` [truncated]`; a state's lines past the byte cap are dropped.
-/
namespace Fw.Oracle

/-- The home-path prefixes: macOS and Linux homes, a Windows home, and the dash-encoded form of a macOS home in a
project directory name (`-Users-<login>-...`).

$$H = [\texttt{/Users/}, \texttt{/home/}, \texttt{\textbackslash Users\textbackslash}, \texttt{-Users-}]$$ -/
def homePrefixes : List (List Char) := ["/Users/".toList, "/home/".toList, "\\Users\\".toList, "-Users-".toList]

/-- The token prefixes of known key shapes (GitHub, OpenAI-style, Slack, AWS, HTTP bearer).

$$T = [\texttt{ghp\_}, \texttt{gho\_}, \texttt{ghu\_}, \texttt{ghs\_}, \texttt{ghr\_}, \texttt{github\_pat\_}, \texttt{sk-}, \texttt{sk\_}, \texttt{xoxb-}, \texttt{xoxp-}, \texttt{AKIA}, \texttt{Bearer }]$$ -/
def tokenPrefixes : List (List Char) :=
  ["ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "sk-", "sk_", "xoxb-", "xoxp-", "AKIA", "Bearer "].map
    String.toList

/-- A character that can belong to the user segment of a home path (anything but a separator or quote).

$$\mathrm{seg}(c) \iff c \notin \{\texttt{/}, \texttt{\textbackslash}, \text{space}, \text{tab}, \text{CR}, \text{LF}, \texttt{"}, \texttt{'}, \texttt{`}, \texttt{:}, \texttt{,}, \texttt{;}, \texttt{)}, \texttt{]}, \texttt{\}}, \texttt{<}, \texttt{>}\}$$ -/
def segChar (c : Char) : Bool := !("/\\ \t\r\n\"'`:,;)]}<>".toList.contains c)

/-- A word character: a letter, a digit or one of `. _ % + -` (also the characters of an e-mail's local part).

$$\mathrm{word}(c) \iff \mathrm{alnum}(c) \lor c \in \{\texttt{.}, \texttt{\_}, \texttt{\%}, \texttt{+}, \texttt{-}\}$$ -/
def wordChar (c : Char) : Bool := c.isAlphanum || "._%+-".toList.contains c

/-- A character of an e-mail domain: a letter, a digit, `.` or `-`.

$$\mathrm{dom}(c) \iff \mathrm{alnum}(c) \lor c \in \{\texttt{.}, \texttt{-}\}$$ -/
def domainChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '-'

/-- A character of a token body: a letter, a digit or one of `_ - . + / =`.

$$\mathrm{tok}(c) \iff \mathrm{alnum}(c) \lor c \in \{\texttt{\_}, \texttt{-}, \texttt{.}, \texttt{+}, \texttt{/}, \texttt{=}\}$$ -/
def tokChar (c : Char) : Bool := c.isAlphanum || "_-.+/=".toList.contains c

/-- Does the text start with a letter or digit?

$$\mathrm{alnumHead}(c :: l) \iff \mathrm{alnum}(c), \quad \lnot\mathrm{alnumHead}([\,])$$ -/
def alnumHead : List Char → Bool
  | c :: _ => c.isAlphanum
  | [] => false

/-- A home path at the head: `~` and the text after the user segment.

$$\mathrm{mHome}(l) = (\texttt{\textasciitilde}, \mathrm{dropWhile}(\mathrm{seg}, \mathrm{drop}(|p|, l))) \text{ for the first } p \in H \text{ with } p \sqsubseteq l, \text{ else } \bot$$ -/
def matchHome (l : List Char) : Option (List Char × List Char) :=
  homePrefixes.findSome? fun p =>
    if p.isPrefixOf l then some (['~'], (l.drop p.length).dropWhile segChar) else none

/-- ASCII case folding of a character list (`Char.toLower` maps `A`–`Z` to `a`–`z` and keeps every other character).

$$\mathrm{low}(l) = [\, \mathrm{toLower}(c) : c \in l \,]$$ -/
def lowerL (l : List Char) : List Char := l.map Char.toLower

/-- A user name not preceded by a letter or digit (`a` says the previous character was one), compared without ASCII
case, not followed by a letter or digit; names shorter than 3 characters are ignored.

$$\mathrm{mName}(N, a, l) = (\texttt{<user>}, \mathrm{drop}(|n|, l)) \text{ for the first } n \in N \text{ with } \lnot a,\ |n| \ge 3,\ \mathrm{low}(n) \sqsubseteq \mathrm{low}(\mathrm{take}(|n|, l)),\ \lnot\mathrm{alnumHead}(\mathrm{drop}(|n|, l)), \text{ else } \bot$$ -/
def matchName (names : List (List Char)) (a : Bool) (l : List Char) : Option (List Char × List Char) :=
  if a then none else
  names.findSome? fun n =>
    if 3 ≤ n.length && (lowerL n).isPrefixOf (lowerL (l.take n.length)) && !alnumHead (l.drop n.length) then
      some ("<user>".toList, l.drop n.length)
    else none

/-- A token at a word start: a known prefix followed by at least 8 token characters.

$$\mathrm{mTok}(w, l) = (\texttt{<token>}, \mathrm{drop}(|b|, r)) \text{ for the first } p \in T \text{ with } \lnot w,\ p \sqsubseteq l,\ r = \mathrm{drop}(|p|, l),\ b = \mathrm{takeWhile}(\mathrm{tok}, r),\ |b| \ge 8, \text{ else } \bot$$ -/
def matchToken (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else
  tokenPrefixes.findSome? fun p =>
    if p.isPrefixOf l then
      let r := l.drop p.length
      let b := r.takeWhile tokChar
      if 8 ≤ b.length then some ("<token>".toList, r.drop b.length) else none
    else none

/-- An e-mail address at a word start: a nonempty run of word characters, `@`, then a domain run of at least 3
characters that contains a dot and does not start with one.

$$\mathrm{mMail}(w, l) = (\texttt{<email>}, \mathrm{drop}(|d|, r)) \iff \lnot w,\ l = u \mathbin{+\!\!+} \texttt{@} :: r,\ u = \mathrm{takeWhile}(\mathrm{word}, l) \ne [\,],\ d = \mathrm{takeWhile}(\mathrm{dom}, r),\ |d| \ge 3,\ \texttt{.} \in d,\ d_0 \ne \texttt{.}$$ -/
def matchEmail (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else
  let u := l.takeWhile wordChar
  if u.isEmpty then none else
  match l.drop u.length with
  | '@' :: r =>
    let d := r.takeWhile domainChar
    if 3 ≤ d.length && d.contains '.' && d.head? != some '.' then some ("<email>".toList, r.drop d.length) else none
  | _ => none

/-- One to three digits at the head: the text after them.

$$\mathrm{octet}(l) = \mathrm{drop}(|g|, l) \text{ if } g = \mathrm{takeWhile}(\mathrm{digit}, l),\ 1 \le |g| \le 3, \text{ else } \bot$$ -/
def octet (l : List Char) : Option (List Char) :=
  let g := l.takeWhile Char.isDigit
  if 1 ≤ g.length && g.length ≤ 3 then some (l.drop g.length) else none

/-- A dot at the head: the text after it.

$$\mathrm{dot}(\texttt{.} :: r) = r, \quad \mathrm{dot}(l) = \bot \text{ otherwise}$$ -/
def dot : List Char → Option (List Char)
  | '.' :: r => some r
  | _ => none

/-- A dotted IPv4 address at a word start, not followed by a digit.

$$\mathrm{mIp}(w, l) = (\texttt{<ip>}, r) \iff \lnot w,\ r = (\mathrm{octet} \circ \mathrm{dot})^{3}(\mathrm{octet}(l)),\ \lnot\mathrm{digitHead}(r)$$ -/
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

/-- The first rule that matches at the head, in the order home path, user name, token, e-mail, address (`w`: the
previous character was a word character; `a`: it was a letter or digit).

$$\mathrm{rule}(N, w, a, l) = \mathrm{mHome}(l) \mathbin{\|} \mathrm{mName}(N, a, l) \mathbin{\|} \mathrm{mTok}(w, l) \mathbin{\|} \mathrm{mMail}(w, l) \mathbin{\|} \mathrm{mIp}(w, l)$$ -/
def rule (names : List (List Char)) (w a : Bool) (l : List Char) : Option (List Char × List Char) :=
  matchHome l <|> matchName names a l <|> matchToken w l <|> matchEmail w l <|> matchIp w l

/-- The pass with fuel `f`: at each position the first matching rule's replacement, else the character itself;
`w` and `a` track whether the previous kept character was a word character and a letter or digit (both false at
the start and after a replacement; out of fuel: the rest unchanged).

$$\mathrm{go}(N, 0, w, a, l) = l, \quad \mathrm{go}(N, f{+}1, w, a, [\,]) = [\,], \quad \mathrm{go}(N, f{+}1, w, a, c :: l) = \begin{cases} o \mathbin{+\!\!+} \mathrm{go}(N, f, \bot, \bot, r) & \mathrm{rule}(N, w, a, c :: l) = (o, r) \\ c :: \mathrm{go}(N, f, \mathrm{word}(c), \mathrm{alnum}(c), l) & \text{otherwise} \end{cases}$$ -/
def go (names : List (List Char)) : Nat → Bool → Bool → List Char → List Char
  | 0, _, _, l => l
  | _ + 1, _, _, [] => []
  | f + 1, w, a, c :: cs =>
    match rule names w a (c :: cs) with
    | some (o, r) => o ++ go names f false false r
    | none => c :: go names f (wordChar c) c.isAlphanum cs

/-- The scrub pass over a text, with fuel its length.

$$\mathrm{scrub}(N, s) = \mathrm{go}(N, |s|, \bot, \bot, s)$$ -/
def scrub (names : List String) (s : String) : String :=
  String.ofList (go (names.map String.toList) s.toList.length false false s.toList)

/-- Does `p` occur in `l` as a contiguous segment?

$$\mathrm{occ}(p, l) \iff \exists u, v:\ l = u \mathbin{+\!\!+} p \mathbin{+\!\!+} v$$ -/
def occurs (p : List Char) : List Char → Bool
  | [] => p.isPrefixOf []
  | c :: cs => p.isPrefixOf (c :: cs) || occurs p cs

/-- `occurs` means a segment.

$$\forall p, l:\ \mathrm{occ}(p, l) \iff \exists u, v:\ l = u \mathbin{+\!\!+} p \mathbin{+\!\!+} v$$ -/
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

/-- Does the text contain a home-path prefix?

$$\mathrm{hasHome}(s) \iff \exists p \in H:\ \mathrm{occ}(p, s)$$ -/
def hasHome (s : String) : Bool := homePrefixes.any fun p => occurs p s.toList

/-- A clean text: the pass changes nothing and no home-path prefix occurs.

$$\mathrm{clean}(N, t) \iff \mathrm{scrub}(N, t) = t \land \lnot\mathrm{hasHome}(t)$$ -/
def clean (names : List String) (t : String) : Bool := scrub names t == t && !hasHome t

/-- **Redaction** (the `oracle.redact` op, per text): the scrubbed text if it is clean, else the empty string (the
text is withheld).

$$\mathrm{redact}(N, s) = \begin{cases} \mathrm{scrub}(N, s) & \mathrm{clean}(N, \mathrm{scrub}(N, s)) \\ \texttt{""} & \text{otherwise} \end{cases}$$ -/
def redact (names : List String) (s : String) : String :=
  let t := scrub names s
  if clean names t then t else ""

/-- The empty text is clean.

$$\forall N:\ \mathrm{clean}(N, \texttt{""})$$ -/
theorem clean_empty (names : List String) : clean names "" = true := by
  simp [clean, scrub, go, hasHome, homePrefixes, occurs, String.ofList_nil]

/-- **Redaction is idempotent.**

$$\forall N, s:\ \mathrm{redact}(N, \mathrm{redact}(N, s)) = \mathrm{redact}(N, s)$$ -/
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

/-- **No home path survives redaction**: the output contains none of `/Users/`, `/home/`, `\Users\`, `-Users-`.

$$\forall N, s:\ \forall p \in H:\ \forall u, v:\ \mathrm{redact}(N, s) \ne u \mathbin{+\!\!+} p \mathbin{+\!\!+} v, \quad H = [\texttt{/Users/}, \texttt{/home/}, \texttt{\textbackslash Users\textbackslash}, \texttt{-Users-}]$$ -/
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

/-- **The four home forms, spelled out**: a redacted text contains no `/Users/`, `/home/`, `\Users\` or `-Users-`.

$$\forall N, s, u, v:\ \mathrm{redact}(N, s) \notin \{u \mathbin{+\!\!+} \texttt{/Users/} \mathbin{+\!\!+} v,\ u \mathbin{+\!\!+} \texttt{/home/} \mathbin{+\!\!+} v,\ u \mathbin{+\!\!+} \texttt{\textbackslash Users\textbackslash} \mathbin{+\!\!+} v,\ u \mathbin{+\!\!+} \texttt{-Users-} \mathbin{+\!\!+} v\}$$ -/
theorem no_home_forms (names : List String) (s : String) (u v : List Char) :
    (redact names s).toList ≠ u ++ "/Users/".toList ++ v ∧ (redact names s).toList ≠ u ++ "/home/".toList ++ v ∧
      (redact names s).toList ≠ u ++ "\\Users\\".toList ++ v ∧ (redact names s).toList ≠ u ++ "-Users-".toList ++ v :=
  ⟨no_home_path names s _ (by simp [homePrefixes]) u v, no_home_path names s _ (by simp [homePrefixes]) u v,
   no_home_path names s _ (by simp [homePrefixes]) u v, no_home_path names s _ (by simp [homePrefixes]) u v⟩

-- what the pass covers (best-effort rules; the guarantees above do not depend on them)
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
-- round-2 review strings: a name after `-`, `_`, `.` or `%`, and the dash-encoded and Windows home forms
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

/-- The most characters a state line may have.

$$\mathrm{lineCap} = 500$$ -/
def lineCap : Nat := 500

/-- The most UTF-8 bytes the lines of a state may total (32 KiB).

$$\mathrm{stateCap} = 32768$$ -/
def stateCap : Nat := 32768

/-- The most UTF-8 bytes of a reply text stored in the answer log (64 KiB).

$$\mathrm{replyCap} = 65536$$ -/
def replyCap : Nat := 65536

/-- The marker that ends a cut text.

$$\mathrm{mark} = \texttt{" [truncated]"}\ (12 \text{ ASCII characters})$$ -/
def cutMarker : String := " [truncated]"

/-- The UTF-8 size of a text: the sum of its characters' encoded sizes.

$$\mathrm{bytes}(s) = \textstyle\sum_{c \in s} \mathrm{utf8Size}(c)$$ -/
def bytes (s : String) : Nat := (s.toList.map Char.utf8Size).sum

/-- Cut a text to at most `m` characters: unchanged when it fits, else its first `m ∸ 12` characters and the marker.

$$\mathrm{capC}(m, s) = \begin{cases} s & |s| \le m \\ \mathrm{take}(m \mathbin{\dot-} |\mathrm{mark}|, s) \mathbin{+\!\!+} \mathrm{mark} & \text{otherwise} \end{cases}$$ -/
def capChars (m : Nat) (s : String) : String :=
  if s.length ≤ m then s else String.ofList (s.toList.take (m - cutMarker.length)) ++ cutMarker

/-- **A cut text fits** when the cap leaves room for the marker.

$$\forall m, s:\ |\mathrm{mark}| \le m \Rightarrow |\mathrm{capC}(m, s)| \le m$$ -/
theorem capChars_length (m : Nat) (s : String) (h : cutMarker.length ≤ m) : (capChars m s).length ≤ m := by
  unfold capChars
  split
  · assumption
  · simp only [String.length_append, String.length_ofList, List.length_take, String.length_toList]
    omega

/-- The longest prefix whose characters fit in `b` bytes, stopping at the first character that does not fit.

$$\mathrm{takeB}(b, [\,]) = [\,], \quad \mathrm{takeB}(b, c :: l) = \begin{cases} c :: \mathrm{takeB}(b - \mathrm{utf8Size}(c), l) & \mathrm{utf8Size}(c) \le b \\ [\,] & \text{otherwise} \end{cases}$$ -/
def takeBytes : Nat → List Char → List Char
  | _, [] => []
  | b, c :: cs => if c.utf8Size ≤ b then c :: takeBytes (b - c.utf8Size) cs else []

/-- The kept prefix fits in `b` bytes.

$$\forall b, l:\ \textstyle\sum_{c \in \mathrm{takeB}(b, l)} \mathrm{utf8Size}(c) \le b$$ -/
theorem takeBytes_size : ∀ (b : Nat) (l : List Char), ((takeBytes b l).map Char.utf8Size).sum ≤ b
  | _, [] => by simp [takeBytes]
  | b, c :: cs => by
    unfold takeBytes
    split
    · have := takeBytes_size (b - c.utf8Size) cs
      simp only [List.map_cons, List.sum_cons]; omega
    · simp

/-- Cut a text to at most `m` UTF-8 bytes: unchanged when it fits, else the longest prefix that fits in
`m ∸ 12` bytes and the marker.

$$\mathrm{capB}(m, s) = \begin{cases} s & \mathrm{bytes}(s) \le m \\ \mathrm{takeB}(m \mathbin{\dot-} \mathrm{bytes}(\mathrm{mark}), s) \mathbin{+\!\!+} \mathrm{mark} & \text{otherwise} \end{cases}$$ -/
def capBytes (m : Nat) (s : String) : String :=
  if bytes s ≤ m then s else String.ofList (takeBytes (m - bytes cutMarker) s.toList) ++ cutMarker

/-- **A byte-cut text fits** when the cap leaves room for the marker.

$$\forall m, s:\ \mathrm{bytes}(\mathrm{mark}) \le m \Rightarrow \mathrm{bytes}(\mathrm{capB}(m, s)) \le m$$ -/
theorem capBytes_size (m : Nat) (s : String) (h : bytes cutMarker ≤ m) : bytes (capBytes m s) ≤ m := by
  unfold capBytes
  split
  · assumption
  · have := takeBytes_size (m - bytes cutMarker) s.toList
    simp only [bytes, String.toList_append, String.toList_ofList, List.map_append, List.sum_append] at h this ⊢
    omega

/-- The stored form of a reply text (the `oracle.store` op): cut to 64 KiB.

$$\mathrm{stored}(s) = \mathrm{capB}(\mathrm{replyCap}, s)$$ -/
def storedReply (s : String) : String := capBytes replyCap s

/-- **A stored reply is at most 64 KiB.**

$$\forall s:\ \mathrm{bytes}(\mathrm{stored}(s)) \le 65536$$ -/
theorem storedReply_size (s : String) : bytes (storedReply s) ≤ replyCap :=
  capBytes_size replyCap s (by decide)

/-- One state line, redacted and capped: cut to 500 characters, then redacted; if redaction made it longer than 500
characters, cut again and keep that only if it is clean, else withhold the line.

$$\mathrm{redLine}(N, x) = \begin{cases} t & |t| \le 500 \\ u & |t| > 500,\ \mathrm{clean}(N, u) \\ \texttt{""} & \text{otherwise} \end{cases}, \quad t = \mathrm{redact}(N, \mathrm{capC}(500, x)),\ u = \mathrm{capC}(500, t)$$ -/
def redactLine (names : List String) (x : String) : String :=
  let t := redact names (capChars lineCap x)
  if t.length ≤ lineCap then t else
  let u := capChars lineCap t
  if clean names u then u else ""

/-- A clean text is a fixed point of `redact`.

$$\forall N, u:\ \mathrm{clean}(N, u) \Rightarrow \mathrm{redact}(N, u) = u$$ -/
theorem redact_of_clean (names : List String) (u : String) (h : clean names u = true) : redact names u = u := by
  have hs : scrub names u = u := by simp only [clean, Bool.and_eq_true, beq_iff_eq] at h; exact h.1
  simp [redact, hs, h]

/-- The empty text is a fixed point of `redact`.

$$\forall N:\ \mathrm{redact}(N, \texttt{""}) = \texttt{""}$$ -/
theorem redact_empty (names : List String) : redact names "" = "" := redact_of_clean names "" (clean_empty names)

/-- **A redacted line is a fixed point of `redact`.**

$$\forall N, x:\ \mathrm{redact}(N, \mathrm{redLine}(N, x)) = \mathrm{redLine}(N, x)$$ -/
theorem redactLine_fix (names : List String) (x : String) :
    redact names (redactLine names x) = redactLine names x := by
  unfold redactLine
  simp only
  split
  · exact redact_idem _ _
  · split
    · rename_i hc; exact redact_of_clean _ _ hc
    · exact redact_empty names

/-- **A redacted line has at most 500 characters.**

$$\forall N, x:\ |\mathrm{redLine}(N, x)| \le 500$$ -/
theorem redactLine_length (names : List String) (x : String) : (redactLine names x).length ≤ lineCap := by
  unfold redactLine
  simp only
  split
  · assumption
  · split
    · exact capChars_length _ _ (by decide)
    · simp [lineCap]

/-- The UTF-8 size of a list of lines.

$$\mathrm{bytes}(L) = \textstyle\sum_{x \in L} \mathrm{bytes}(x)$$ -/
def linesBytes (L : List String) : Nat := (L.map bytes).sum

/-- The longest prefix of lines that fits in `b` bytes, stopping at the first line that does not fit.

$$\mathrm{keep}(b, [\,]) = [\,], \quad \mathrm{keep}(b, x :: L) = \begin{cases} x :: \mathrm{keep}(b - \mathrm{bytes}(x), L) & \mathrm{bytes}(x) \le b \\ [\,] & \text{otherwise} \end{cases}$$ -/
def keepLines : Nat → List String → List String
  | _, [] => []
  | b, x :: xs => if bytes x ≤ b then x :: keepLines (b - bytes x) xs else []

/-- The kept lines fit in `b` bytes.

$$\forall b, L:\ \mathrm{bytes}(\mathrm{keep}(b, L)) \le b$$ -/
theorem keepLines_bytes : ∀ (b : Nat) (L : List String), linesBytes (keepLines b L) ≤ b
  | _, [] => by simp [keepLines, linesBytes]
  | b, x :: xs => by
    unfold keepLines
    split
    · have := keepLines_bytes (b - bytes x) xs
      simp only [linesBytes, List.map_cons, List.sum_cons] at this ⊢; omega
    · simp [linesBytes]

/-- The kept lines are lines of the input.

$$\forall b, L, x:\ x \in \mathrm{keep}(b, L) \Rightarrow x \in L$$ -/
theorem keepLines_mem : ∀ (b : Nat) (L : List String) (x : String), x ∈ keepLines b L → x ∈ L
  | _, [], _, h => by simp [keepLines] at h
  | b, y :: ys, x, h => by
    unfold keepLines at h
    split at h
    · rcases List.mem_cons.mp h with rfl | h'
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (keepLines_mem _ ys x h')
    · simp at h

/-- Cap the lines of a state to `b` bytes in total: fields in order, each keeps its *last* lines that fit in what the
earlier fields left (for a log, the lines nearest the failure).

$$\mathrm{capS}(b, [\,]) = [\,], \quad \mathrm{capS}(b, (k, L) :: S) = (k, L') :: \mathrm{capS}(b - \mathrm{bytes}(L'), S),\ L' = \mathrm{rev}(\mathrm{keep}(b, \mathrm{rev}(L)))$$ -/
def capState : Nat → List (String × List String) → List (String × List String)
  | _, [] => []
  | b, (k, L) :: S =>
    let L' := (keepLines b L.reverse).reverse
    (k, L') :: capState (b - linesBytes L') S

/-- The UTF-8 size of the lines of a state (field names not counted).

$$\mathrm{bytes}(S) = \textstyle\sum_{(k, L) \in S} \mathrm{bytes}(L)$$ -/
def stateBytes (S : List (String × List String)) : Nat := (S.map fun kl => linesBytes kl.2).sum

/-- **A capped state fits in `b` bytes.**

$$\forall b, S:\ \mathrm{bytes}(\mathrm{capS}(b, S)) \le b$$ -/
theorem capState_bytes : ∀ (b : Nat) (S : List (String × List String)), stateBytes (capState b S) ≤ b
  | _, [] => by simp [capState, stateBytes]
  | b, (k, L) :: S => by
    have h1 := keepLines_bytes b L.reverse
    have hr : linesBytes (keepLines b L.reverse).reverse = linesBytes (keepLines b L.reverse) := by
      simp [linesBytes, List.map_reverse, List.sum_reverse]
    have h2 := capState_bytes (b - linesBytes (keepLines b L.reverse).reverse) S
    simp only [capState, stateBytes, List.map_cons, List.sum_cons] at h2 ⊢
    omega

/-- Every line of a capped state is a line of the same field of the input.

$$\forall b, S, k, L', x:\ (k, L') \in \mathrm{capS}(b, S) \land x \in L' \Rightarrow \exists L:\ (k, L) \in S \land x \in L$$ -/
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

/-- A flat question state: field name to lines of text (a one-line field is a one-element list).

$$\mathrm{State} = (\mathrm{String} \times \mathrm{String}^{*})^{*}$$ -/
abbrev State := List (String × List String)

/-- Redact and cap every line of every field (field names are ours and are kept), then cap the state to 32 KiB.

$$\mathrm{redactState}(N, S) = \mathrm{capS}(\mathrm{stateCap}, [\, (k, [\, \mathrm{redLine}(N, x) : x \in L \,]) : (k, L) \in S \,])$$ -/
def redactState (names : List String) (st : State) : State :=
  capState stateCap (st.map fun (k, ls) => (k, ls.map (redactLine names)))

/-- A state is redacted when every line is a fixed point of `redact` and at most 500 characters, and its lines total
at most 32 KiB.

$$\mathrm{isRedacted}(N, S) \iff (\forall (k, L) \in S:\ \forall x \in L:\ \mathrm{redact}(N, x) = x \land |x| \le 500) \land \mathrm{bytes}(S) \le 32768$$ -/
def isRedacted (names : List String) (st : State) : Bool :=
  st.all (fun (_, ls) => ls.all fun x => redact names x == x && decide (x.length ≤ lineCap)) &&
    decide (stateBytes st ≤ stateCap)

/-- A redacted state passes the check.

$$\forall N, S:\ \mathrm{isRedacted}(N, \mathrm{redactState}(N, S))$$ -/
theorem redactState_redacted (names : List String) (st : State) : isRedacted names (redactState names st) = true := by
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq]
  refine ⟨fun kl hkl x hx => ?_, capState_bytes _ _⟩
  obtain ⟨L, hL, hxL⟩ := capState_mem _ _ kl x hkl hx
  obtain ⟨⟨k', L0⟩, _, he⟩ := List.mem_map.mp hL
  simp only [Prod.mk.injEq] at he
  obtain ⟨_, rfl⟩ := he
  obtain ⟨y, _, rfl⟩ := List.mem_map.mp hxL
  exact ⟨redactLine_fix names y, redactLine_length names y⟩

/-- **The caps of a sent state**: in a redacted state every line has at most 500 characters and the lines total at
most 32 KiB.

$$\forall N, S:\ \mathrm{isRedacted}(N, S) \Rightarrow (\forall (k, L) \in S:\ \forall x \in L:\ |x| \le 500) \land \mathrm{bytes}(S) \le 32768$$ -/
theorem redacted_caps (names : List String) (st : State) (h : isRedacted names st = true) :
    (∀ kl ∈ st, ∀ x ∈ kl.2, x.length ≤ lineCap) ∧ stateBytes st ≤ stateCap := by
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  exact ⟨fun kl hkl x hx => (h.1 kl hkl x hx).2, h.2⟩

/-- A state that passes the check holds no home path (`/Users/`, `/home/`, `\Users\`, `-Users-`) in any line.

$$\forall N, S:\ \mathrm{isRedacted}(N, S) \Rightarrow \forall (k, L) \in S:\ \forall x \in L:\ \forall p \in H:\ \forall u, v:\ x \ne u \mathbin{+\!\!+} p \mathbin{+\!\!+} v, \quad H = [\texttt{/Users/}, \texttt{/home/}, \texttt{\textbackslash Users\textbackslash}, \texttt{-Users-}]$$ -/
theorem redacted_no_home (names : List String) (st : State) (h : isRedacted names st = true) :
    ∀ kl ∈ st, ∀ x ∈ kl.2, ∀ p ∈ homePrefixes, ∀ u v : List Char, x.toList ≠ u ++ p ++ v := by
  intro kl hkl x hx p hp u v
  simp only [isRedacted, Bool.and_eq_true, List.all_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  have hr : redact names x = x := (h.1 kl hkl x hx).1
  rw [← hr]; exact no_home_path names x p hp u v

end Fw.Oracle
