/-!
# Fw.Oracle.Redact: what may leave this machine in an oracle question

Before a state is sent to the model, every text of it goes through `redact`. One left-to-right pass (`scrub`)
replaces:
- a home path `/Users/<x>` or `/home/<x>` (the segment after the prefix) by `~`;
- a user name given by the caller (`git config user.name`, `user.email`, the login name), as a whole word, by
  `<user>`;
- a token of a known key shape (`ghp_ gho_ ghu_ ghs_ ghr_ github_pat_ sk- sk_ xoxb- xoxp- AKIA`, `Bearer `) followed
  by at least 8 token characters, by `<token>`;
- an e-mail address `name@example.com` by `<email>`; a dotted IPv4 address by `<ip>`.

`redact` then keeps the scrubbed text only if it is *clean*: a fixed point of the pass and free of home paths;
otherwise it withholds the whole text (the empty string). That check makes the two guarantees hold for every input,
not just the inputs the pass was tested on: `redact_idem` and `no_home_path`. The pass itself is best-effort for
names, tokens, e-mails and addresses (the `#guard`s below show the cases it covers).
-/
namespace Fw.Oracle

/-- The home-path prefixes.

$$H = [\texttt{/Users/}, \texttt{/home/}]$$ -/
def homePrefixes : List (List Char) := ["/Users/".toList, "/home/".toList]

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

/-- A user name at a word start (`w` says the previous character was a word character), not followed by a letter or
digit; names shorter than 3 characters are ignored.

$$\mathrm{mName}(N, w, l) = (\texttt{<user>}, \mathrm{drop}(|n|, l)) \text{ for the first } n \in N \text{ with } \lnot w,\ |n| \ge 3,\ n \sqsubseteq l,\ \lnot\mathrm{alnumHead}(\mathrm{drop}(|n|, l)), \text{ else } \bot$$ -/
def matchName (names : List (List Char)) (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  if w then none else
  names.findSome? fun n =>
    if 3 ≤ n.length && n.isPrefixOf l && !alnumHead (l.drop n.length) then some ("<user>".toList, l.drop n.length)
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

/-- The first rule that matches at the head, in the order home path, user name, token, e-mail, address.

$$\mathrm{rule}(N, w, l) = \mathrm{mHome}(l) \mathbin{\|} \mathrm{mName}(N, w, l) \mathbin{\|} \mathrm{mTok}(w, l) \mathbin{\|} \mathrm{mMail}(w, l) \mathbin{\|} \mathrm{mIp}(w, l)$$ -/
def rule (names : List (List Char)) (w : Bool) (l : List Char) : Option (List Char × List Char) :=
  matchHome l <|> matchName names w l <|> matchToken w l <|> matchEmail w l <|> matchIp w l

/-- The pass with fuel `f`: at each position the first matching rule's replacement, else the character itself;
`w` tracks whether the previous emitted character was a word character (out of fuel: the rest unchanged).

$$\mathrm{go}(N, 0, w, l) = l, \quad \mathrm{go}(N, f{+}1, w, [\,]) = [\,], \quad \mathrm{go}(N, f{+}1, w, c :: l) = \begin{cases} o \mathbin{+\!\!+} \mathrm{go}(N, f, \bot, r) & \mathrm{rule}(N, w, c :: l) = (o, r) \\ c :: \mathrm{go}(N, f, \mathrm{word}(c), l) & \text{otherwise} \end{cases}$$ -/
def go (names : List (List Char)) : Nat → Bool → List Char → List Char
  | 0, _, l => l
  | _ + 1, _, [] => []
  | f + 1, w, c :: cs =>
    match rule names w (c :: cs) with
    | some (o, r) => o ++ go names f false r
    | none => c :: go names f (wordChar c) cs

/-- The scrub pass over a text, with fuel its length.

$$\mathrm{scrub}(N, s) = \mathrm{go}(N, |s|, \bot, s)$$ -/
def scrub (names : List String) (s : String) : String :=
  String.ofList (go (names.map String.toList) s.toList.length false s.toList)

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

/-- **No home path survives redaction**: the output never contains `/Users/` (nor `/home/`).

$$\forall N, s, u, v:\ \mathrm{redact}(N, s) \ne u \mathbin{+\!\!+} \texttt{/Users/} \mathbin{+\!\!+} v \ \land\ \mathrm{redact}(N, s) \ne u \mathbin{+\!\!+} \texttt{/home/} \mathbin{+\!\!+} v$$ -/
theorem no_home_path (names : List String) (s : String) (u v : List Char) :
    (redact names s).toList ≠ u ++ "/Users/".toList ++ v ∧ (redact names s).toList ≠ u ++ "/home/".toList ++ v := by
  have hc : clean names (redact names s) = true := by
    unfold redact
    by_cases h : clean names (scrub names s) = true
    · simp [h]
    · simp [h, clean_empty]
  simp only [clean, Bool.and_eq_true, Bool.not_eq_true', hasHome, homePrefixes, List.any_cons, List.any_nil,
    Bool.or_false, Bool.or_eq_false_iff] at hc
  obtain ⟨_, h1, h2⟩ := hc
  constructor
  · intro he; have := (occurs_iff _ _).mpr ⟨u, v, he⟩; rw [h1] at this; exact Bool.noConfusion this
  · intro he; have := (occurs_iff _ _).mpr ⟨u, v, he⟩; rw [h2] at this; exact Bool.noConfusion this

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
#guard redact ["ab"] "ab cd" == "ab cd"
#guard redact [] "" == ""
#guard redact [] "x/Users/" == "x~"
#guard redact ["user"] "user" == ""
#guard redact [] (redact [] "/Users/x/b mail a@example.org 203.0.113.1") == redact [] "/Users/x/b mail a@example.org 203.0.113.1"

/-- A flat question state: field name to lines of text (a one-line field is a one-element list).

$$\mathrm{State} = (\mathrm{String} \times \mathrm{String}^{*})^{*}$$ -/
abbrev State := List (String × List String)

/-- Redact every line of every field (field names are ours and are kept).

$$\mathrm{redactState}(N, S) = [\, (k, [\, \mathrm{redact}(N, x) : x \in L \,]) : (k, L) \in S \,]$$ -/
def redactState (names : List String) (st : State) : State :=
  st.map fun (k, ls) => (k, ls.map (redact names))

/-- A state is redacted when every line is a fixed point of `redact`.

$$\mathrm{isRedacted}(N, S) \iff \forall (k, L) \in S:\ \forall x \in L:\ \mathrm{redact}(N, x) = x$$ -/
def isRedacted (names : List String) (st : State) : Bool :=
  st.all fun (_, ls) => ls.all fun x => redact names x == x

/-- A redacted state passes the check.

$$\forall N, S:\ \mathrm{isRedacted}(N, \mathrm{redactState}(N, S))$$ -/
theorem redactState_redacted (names : List String) (st : State) : isRedacted names (redactState names st) = true := by
  simp [isRedacted, redactState, redact_idem]

/-- A state that passes the check holds no home path in any line.

$$\forall N, S:\ \mathrm{isRedacted}(N, S) \Rightarrow \forall (k, L) \in S:\ \forall x \in L:\ \forall u, v:\ x \ne u \mathbin{+\!\!+} \texttt{/Users/} \mathbin{+\!\!+} v \land x \ne u \mathbin{+\!\!+} \texttt{/home/} \mathbin{+\!\!+} v$$ -/
theorem redacted_no_home (names : List String) (st : State) (h : isRedacted names st = true) :
    ∀ kl ∈ st, ∀ x ∈ kl.2, ∀ u v : List Char,
      x.toList ≠ u ++ "/Users/".toList ++ v ∧ x.toList ≠ u ++ "/home/".toList ++ v := by
  intro kl hkl x hx u v
  simp only [isRedacted, List.all_eq_true, beq_iff_eq] at h
  have hr : redact names x = x := h kl hkl x hx
  rw [← hr]; exact no_home_path names x u v

end Fw.Oracle
