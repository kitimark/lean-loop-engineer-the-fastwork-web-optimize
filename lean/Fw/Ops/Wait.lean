/-!
# Wait guard (PLAN §8.3 `PreToolUse` matcher `Bash`; mistake class `c-orphan-wait`)

Two things, both pure.

**1. Waits are bounded and owned.** A wait is an owner plus a deadline. `waitOk` admits it only with a
non-empty owner and a deadline in `1..cap`; `waitEnd` is when the wait stops whatever the condition
does. Proved: `wait_bounded` (every admitted wait stops by its deadline, which is `≤ cap`, and has an
owner). Handback: `handbackOk` allows an agent to hand back only when every background task it
started has ended; proved `handback_no_open_bg`.

**2. A foreground `Bash` call must not start a long-running process with `&`.** The command is parsed
(`parse`) into segments split at `; \n | || && &` (here-document bodies are skipped: they are data), grouped into
*units* (an and-or list or a whole `until/while/for/if/case ... done/fi/esac` compound, the thing a trailing `&`
backgrounds). A unit is *long* when it holds one of the `Shape`s: `fw watch`, an `until`/`while` loop, a server or
watcher, a `tail -f`, or a `sleep` longer than `caps.maxSleepSec`. `decide` refuses a backgrounded long unit
(`bgLong`: use the tool's `run_in_background`, which has an owner and a stop) and any `until`/`while` loop with no
bound (`unboundedLoop`: no `timeout` wrapper, no counter / clock test, and not a `while read` loop over a finite input,
proved `readLoop_bounded`).

The shapes are a small documented set, tested by goldens; the parse is approximate on purpose.
Known blind spots (shadow-logged, not claimed): code inside `$( )`, `( )` or `sh -c '...'` strings, aliases, and
a here-document delimiter glued to a redirect (`<<EOF>f`).
-/
namespace Fw.Ops.Wait

/-! ## Bounded, owned waits -/

/-- A wait: who owns it and its deadline in seconds.

$$\mathrm{Wait} = \mathrm{String} \times \mathbb{N}, \qquad w = (w.\mathit{owner},\ w.\mathit{deadline})$$
-/
structure Wait where
  owner    : String
  deadline : Nat
deriving DecidableEq, Repr

/-- A wait is admitted when it has an owner and a deadline in `1..cap`.

$$\mathrm{ok}_c(w) \iff w.\mathit{owner} \ne \texttt{""} \ \land\ 0 < w.\mathit{deadline} \ \land\ w.\mathit{deadline} \le c$$
-/
def waitOk (cap : Nat) (w : Wait) : Bool :=
  w.owner != "" && decide (0 < w.deadline) && decide (w.deadline ≤ cap)

/-- When a wait stops, given the condition `sat : ℕ → Bool` (true at second `t` when the awaited
thing has happened): the first second `t ≤ deadline` with `sat t`, else the deadline.

$$\mathrm{end}(w, \mathit{sat}) = \min\{\, t \le w.\mathit{deadline} \mid \mathit{sat}(t) \,\} \ \text{ if it exists, else } w.\mathit{deadline}$$
-/
def waitEnd (w : Wait) (sat : Nat → Bool) : Nat :=
  ((List.range (w.deadline + 1)).find? sat).getD w.deadline

/-- The stop time never passes the deadline.

$$\mathrm{end}(w, \mathit{sat}) \le w.\mathit{deadline}$$
-/
theorem waitEnd_le (w : Wait) (sat : Nat → Bool) : waitEnd w sat ≤ w.deadline := by
  unfold waitEnd
  cases h : (List.range (w.deadline + 1)).find? sat with
  | none => simp
  | some t =>
    have := List.mem_of_find?_eq_some h
    simp [List.mem_range] at this ⊢
    omega

/-- Every admitted wait has an owner and stops by its deadline, which is at most the cap, whatever the
condition does (also when it never becomes true).

$$\mathrm{ok}_c(w) \ \Rightarrow\ w.\mathit{owner} \ne \texttt{""} \ \land\ \forall\, \mathit{sat}.\ \mathrm{end}(w, \mathit{sat}) \le w.\mathit{deadline} \le c$$
-/
theorem wait_bounded (cap : Nat) (w : Wait) (h : waitOk cap w = true) :
    w.owner ≠ "" ∧ ∀ sat, waitEnd w sat ≤ w.deadline ∧ w.deadline ≤ cap := by
  unfold waitOk at h
  simp only [Bool.and_eq_true, bne_iff_ne, ne_eq, decide_eq_true_eq] at h
  exact ⟨h.1.1, fun sat => ⟨waitEnd_le w sat, h.2⟩⟩

/-- A background-task event of one agent: a task started, or ended (finished, stopped or killed).

$$\mathrm{Ev} = \mathrm{start}(id) \mid \mathrm{end}(id)$$
-/
inductive Ev where
  | start (id : String)
  | stop  (id : String)
deriving DecidableEq, Repr

/-- The ids started and not ended: the agent's open background work.

$$\mathrm{open}(E) = \{\, id \mid \mathrm{start}(id) \in E \ \land\ \mathrm{end}(id) \notin E \,\}$$
-/
def openBg (es : List Ev) : List String :=
  (es.filterMap fun | .start i => some i | .stop _ => none).filter fun i => !(es.contains (.stop i))

/-- Handback is allowed only with no open background work.

$$\mathrm{handback}(E) \iff \mathrm{open}(E) = \emptyset$$
-/
def handbackOk (es : List Ev) : Bool := (openBg es).isEmpty

/-- An agent that may hand back has no background task left open: everything it started has ended.

$$\mathrm{handback}(E) \ \Rightarrow\ \forall id.\ \mathrm{start}(id) \in E \Rightarrow \mathrm{end}(id) \in E$$
-/
theorem handback_no_open_bg (es : List Ev) (h : handbackOk es = true) :
    ∀ i, Ev.start i ∈ es → Ev.stop i ∈ es := by
  intro i hi
  unfold handbackOk openBg at h
  simp only [List.isEmpty_iff] at h
  refine Classical.byContradiction fun hn => ?_
  have : i ∈ (es.filterMap fun | .start i => some i | .stop _ => none).filter fun i => !(es.contains (.stop i)) := by
    simp only [List.mem_filter, List.mem_filterMap]
    refine ⟨⟨.start i, hi, rfl⟩, ?_⟩
    simp [hn]
  rw [h] at this
  simp at this

/-! ## Parsing a command -/

/-- How a segment ends: `;` or newline (`seq`), `&&`/`||` (`join`: the same and-or list goes on), `|` (`pipe`: the
same pipeline goes on, this segment's output is the next one's input), `&` (`bg`), or the end of the text (`fin`).

$$\mathrm{Term} = \mathrm{seq} \mid \mathrm{join} \mid \mathrm{pipe} \mid \mathrm{bg} \mid \mathrm{fin}$$
-/
inductive Term where
  | seq | join | pipe | bg | fin
deriving DecidableEq, Repr

/-- A simple command: its words (quotes removed) and how it ends.

$$\mathrm{Seg} = \mathrm{String}^{*} \times \mathrm{Term}$$
-/
structure Seg where
  words : List String
  term  : Term
deriving DecidableEq, Repr

/-- The scanner state: quote (0 none, 1 single, 2 double), pending backslash, a pending `&` (not yet known to be
`&&`, `&>` or a background), comment, the previous character, the current word (reversed), the current words
(reversed), the finished segments (reversed), the here-document delimiters still to read (each with its `<<-` flag:
leading tabs stripped), whether the scanner is inside a here-document body, and the body line read so far (reversed).

$$\mathrm{Acc} = \mathbb{N} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Char} \times \mathrm{Char}^{*} \times \mathrm{String}^{*} \times \mathrm{Seg}^{*} \times (\mathrm{Char}^{*} \times \mathbb{B})^{*} \times \mathbb{B} \times \mathrm{Char}^{*}, \quad a = (\mathit{quote}, \mathit{esc}, \mathit{pend}, \mathit{comment}, \mathit{prev}, \mathit{word}, \mathit{words}, \mathit{segs}, \mathit{hd}, \mathit{body}, \mathit{line}), \quad \{\} = (0, \bot, \bot, \bot, \texttt{' '}, [\,], [\,], [\,], [\,], \bot, [\,])$$
-/
structure Acc where
  quote   : Nat := 0
  esc     : Bool := false
  pend    : Bool := false
  comment : Bool := false
  prev    : Char := ' '
  word    : List Char := []
  words   : List String := []
  segs    : List Seg := []
  hd      : List (List Char × Bool) := []
  body    : Bool := false
  line    : List Char := []

/-- The here-document delimiter a finished word `w` opens, given the word `p` before it in the segment: the whole
word after a `<<` (or `<<-`) word, else the rest of a word `<<D` or `<<-D` with `D` non-empty; a here-string `<<<` opens
none. The flag is true for `<<-` (the closing line may start with tabs). Quotes are already removed, so `<<'EOF'` is
`<<EOF`.

$$\mathrm{hereDelim}(p, w) = \begin{cases} \mathrm{some}(w, \bot) & p = \texttt{<<} \\ \mathrm{some}(w, \top) & p = \texttt{<<-} \\ \mathrm{none} & w = \texttt{<<<}\,r \\ \mathrm{none} & w = \texttt{<<-} \\ \mathrm{some}(D, \top) & w = \texttt{<<-}\,D,\ D \ne \varepsilon \\ \mathrm{some}(D, \bot) & w = \texttt{<<}\,D,\ D \ne \varepsilon \\ \mathrm{none} & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def hereDelim (p : String) (w : List Char) : Option (List Char × Bool) :=
  if p == "<<" then some (w, false)
  else if p == "<<-" then some (w, true)
  else match w with
    | '<' :: '<' :: '<' :: _ => none
    | ['<', '<', '-'] => none
    | '<' :: '<' :: '-' :: d@(_ :: _) => some (d, true)
    | '<' :: '<' :: d@(_ :: _) => some (d, false)
    | _ => none

/-- Finish the current word (if any); a word that opens a here-document queues its delimiter. Here $p$ is the head of
$a.\mathit{words}$ (`""` if none), $w = \mathrm{rev}(a.\mathit{word})$, and $\mathrm{toList}(\mathrm{none}) = [\,]$,
$\mathrm{toList}(\mathrm{some}(x)) = [x]$.

$$\mathrm{flushWord}(a) = \begin{cases} a & a.\mathit{word} = [\,] \\ a[\mathit{words} := \mathrm{str}(w) :: a.\mathit{words},\ \mathit{word} := [\,],\ \mathit{hd} := a.\mathit{hd} \mathbin{+\!\!+} \mathrm{toList}(\mathrm{hereDelim}(p, w))] & \text{otherwise} \end{cases}$$
-/
def flushWord (a : Acc) : Acc :=
  if a.word.isEmpty then a
  else
    let w := a.word.reverse
    { a with words := String.ofList w :: a.words, word := [],
             hd := a.hd ++ (hereDelim (a.words.head?.getD "") w).toList }

/-- Finish the current segment with a terminator. An empty segment is dropped (so `a &&⏎ b` stays one list), except a
`bg` or `fin` terminator on an empty segment is dropped too: there is nothing to background.

$$\mathrm{endSeg}(a, t) = \begin{cases} a' & a'.\mathit{words} = [\,] \\ a'[\mathit{words} := [\,],\ \mathit{segs} := (\mathrm{rev}(a'.\mathit{words}), t) :: a'.\mathit{segs}] & \text{otherwise} \end{cases}, \quad a' = \mathrm{flushWord}(a)$$
-/
def endSeg (a : Acc) (t : Term) : Acc :=
  let a := flushWord a
  if a.words.isEmpty then a
  else { a with words := [], segs := ⟨a.words.reverse, t⟩ :: a.segs }

/-- An unquoted newline: end the segment, then enter a here-document body if a delimiter is queued.

$$\mathrm{newline}(a) = \begin{cases} b & b.\mathit{hd} = [\,] \\ b[\mathit{body} := \top] & \text{otherwise} \end{cases}, \quad b = \mathrm{endSeg}(a, \mathrm{seq})$$
-/
def newline (a : Acc) : Acc :=
  let b := endSeg a .seq
  if b.hd.isEmpty then b else { b with body := true }

/-- The second `|` of `||`: the segment the first `|` ended continues an and-or list, not a pipeline.

$$\mathrm{unpipe}(a) = \begin{cases} a[\mathit{segs} := (s.\mathit{words}, \mathrm{join}) :: r] & a.\mathit{segs} = s :: r \\ a & a.\mathit{segs} = [\,] \end{cases}$$
-/
def unpipe (a : Acc) : Acc :=
  match a.segs with
  | s :: r => { a with segs := { s with term := .join } :: r }
  | [] => a

/-- Add a character to the current word.

$$\mathrm{push}(a, c) = a[\mathit{word} := c :: a.\mathit{word}]$$
-/
def push (a : Acc) (c : Char) : Acc := { a with word := c :: a.word }

/-- Process one character that is not a pending `&` resolver (the first matching row applies; ⏎ is newline).

$$\mathrm{stepPlain}(a, c) = \begin{cases} \mathrm{newline}(a[\mathit{comment} := \bot]) & a.\mathit{comment},\ c = \text{⏎} \\ a & a.\mathit{comment},\ c \ne \text{⏎} \\ \mathrm{push}(a[\mathit{esc} := \bot], c) & a.\mathit{esc} \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 1,\ c = \texttt{'} \\ \mathrm{push}(a, c) & a.\mathit{quote} = 1 \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 2,\ c = \texttt{"} \\ a[\mathit{esc} := \top] & a.\mathit{quote} = 2,\ c = \backslash \\ \mathrm{push}(a, c) & a.\mathit{quote} = 2 \\ a[\mathit{quote} := 1] & c = \texttt{'} \\ a[\mathit{quote} := 2] & c = \texttt{"} \\ a[\mathit{esc} := \top] & c = \backslash \\ \mathrm{flushWord}(a) & c \in \{\text{space}, \text{tab}, \text{CR}\} \\ \mathrm{newline}(a) & c = \text{⏎} \\ \mathrm{endSeg}(a, \mathrm{seq}) & c = \texttt{;} \\ \mathrm{unpipe}(a) & c = \texttt{|},\ a.\mathit{prev} = \texttt{|} \\ \mathrm{endSeg}(a, \mathrm{pipe}) & c = \texttt{|} \\ a[\mathit{comment} := \top] & c = \texttt{\#},\ a.\mathit{word} = [\,] \\ \mathrm{push}(a, c) & c = \texttt{\&},\ a.\mathit{prev} \in \{\texttt{>}, \texttt{<}\} \\ a[\mathit{pend} := \top] & c = \texttt{\&} \\ \mathrm{push}(a, c) & \text{otherwise} \end{cases}$$
-/
def stepPlain (a : Acc) (c : Char) : Acc :=
  if a.comment then
    if c == '\n' then newline { a with comment := false } else a
  else if a.esc then push { a with esc := false } c
  else if a.quote == 1 then
    if c == '\'' then { a with quote := 0 } else push a c
  else if a.quote == 2 then
    if c == '"' then { a with quote := 0 }
    else if c == '\\' then { a with esc := true }
    else push a c
  else if c == '\'' then { a with quote := 1 }
  else if c == '"' then { a with quote := 2 }
  else if c == '\\' then { a with esc := true }
  else if c == ' ' || c == '\t' || c == '\r' then flushWord a
  else if c == '\n' then newline a
  else if c == ';' then endSeg a .seq
  else if c == '|' then
    if a.prev == '|' then unpipe a else endSeg a .pipe
  else if c == '#' && a.word.isEmpty then { a with comment := true }
  else if c == '&' then
    if a.prev == '>' || a.prev == '<' then push a c else { a with pend := true }
  else push a c

/-- One character of a here-document body: the text is skipped; at a newline the line just read is compared with the
first queued delimiter (after removing leading tabs for `<<-`), and a match ends that document (the body ends when no
delimiter is left). Here $(d, t)$ is the head of $a.\mathit{hd}$, $r$ its tail, and
$\ell = \mathrm{rev}(a.\mathit{line})$ with leading tabs removed when $t$.

$$\mathrm{bodyStep}(a, c) = \begin{cases} a[\mathit{line} := c :: a.\mathit{line}] & c \ne \text{⏎} \\ a[\mathit{body} := \bot,\ \mathit{line} := [\,]] & c = \text{⏎},\ a.\mathit{hd} = [\,] \\ a[\mathit{hd} := r,\ \mathit{body} := (r \ne [\,]),\ \mathit{line} := [\,]] & c = \text{⏎},\ a.\mathit{hd} = (d, t) :: r,\ \ell = d \\ a[\mathit{line} := [\,]] & c = \text{⏎},\ a.\mathit{hd} = (d, t) :: r,\ \ell \ne d \end{cases}$$
-/
def bodyStep (a : Acc) (c : Char) : Acc :=
  if c == '\n' then
    match a.hd with
    | [] => { a with body := false, line := [] }
    | (d, dash) :: rest =>
      let l := a.line.reverse
      let l := if dash then l.dropWhile (· == '\t') else l
      if l == d then { a with hd := rest, body := !rest.isEmpty, line := [] }
      else { a with line := [] }
  else { a with line := c :: a.line }

/-- One scanner step: inside a here-document body the character goes to `bodyStep`; otherwise a pending `&` is
resolved by the next character (`&&` is a join, `&>` stays in the word, anything else makes the `&` a background
operator), then the character is processed.

$$\mathrm{step}(a, c) = b[\mathit{prev} := c], \quad b = \begin{cases} \mathrm{bodyStep}(a, c) & a.\mathit{body} \\ \mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{join}) & a.\mathit{pend},\ c = \texttt{\&} \\ \mathrm{stepPlain}(\mathrm{push}(a[\mathit{pend} := \bot], \texttt{\&}), c) & a.\mathit{pend},\ c = \texttt{>} \\ \mathrm{stepPlain}(\mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{bg}), c) & a.\mathit{pend},\ c \notin \{\texttt{\&}, \texttt{>}\} \\ \mathrm{stepPlain}(a, c) & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def step (a : Acc) (c : Char) : Acc :=
  if a.body then { bodyStep a c with prev := c }
  else
  let a' :=
    if a.pend then
      if c == '&' then (endSeg { a with pend := false } .join, true)
      else if c == '>' then (push { a with pend := false } '&', false)
      else (endSeg { a with pend := false } .bg, false)
    else (a, false)
  if a'.2 then { a'.1 with prev := c }
  else { stepPlain a'.1 c with prev := c }

/-- Inside a here-document body a step never changes the parsed words, segments, quote state or pending `&`: the body
is data, not commands.

$$\forall a, c.\ a.\mathit{body} \ \Rightarrow\ \mathrm{step}(a, c).\mathit{segs} = a.\mathit{segs} \land \mathrm{step}(a, c).\mathit{words} = a.\mathit{words} \land \mathrm{step}(a, c).\mathit{word} = a.\mathit{word} \land \mathrm{step}(a, c).\mathit{quote} = a.\mathit{quote} \land \mathrm{step}(a, c).\mathit{pend} = a.\mathit{pend}$$
-/
theorem heredoc_body_inert (a : Acc) (c : Char) (h : a.body = true) :
    (step a c).segs = a.segs ∧ (step a c).words = a.words ∧ (step a c).word = a.word ∧
      (step a c).quote = a.quote ∧ (step a c).pend = a.pend := by
  unfold step bodyStep
  simp only [h, ite_true]
  repeat' split
  all_goals simp

/-- A here-document body line (no newline in it) leaves the parsed segments as they were, whatever it holds
(`while true`, `&`, quotes): the scanner stays in the body.

$$\forall \mathit{cs}, a.\ a.\mathit{body} \land \text{⏎} \notin \mathit{cs} \ \Rightarrow\ (\mathrm{foldl}\ \mathrm{step}\ a\ \mathit{cs}).\mathit{segs} = a.\mathit{segs} \land (\mathrm{foldl}\ \mathrm{step}\ a\ \mathit{cs}).\mathit{body}$$
-/
theorem heredoc_line_inert (cs : List Char) (a : Acc) (h : a.body = true) (hn : '\n' ∉ cs) :
    (cs.foldl step a).segs = a.segs ∧ (cs.foldl step a).body = true := by
  induction cs generalizing a with
  | nil => simp [h]
  | cons c cs ih =>
    simp only [List.mem_cons, not_or] at hn
    have hc : (c == '\n') = false := by simpa using Ne.symm hn.1
    have hb : (step a c).body = true := by
      unfold step bodyStep; simp [h, hc]
    have := ih (step a c) hb hn.2
    simp only [List.foldl_cons]
    exact ⟨this.1.trans (heredoc_body_inert a c h).1, this.2⟩

/-- Split a command into segments.

$$\mathrm{parse}: \mathrm{String} \to \mathrm{Seg}^{*}$$
-/
def parse (s : String) : List Seg :=
  let a := s.toList.foldl step {}
  let a := if a.pend then endSeg { a with pend := false } .bg else a
  (endSeg a .fin).segs.reverse

/-! ## Shapes and units -/

/-- What makes a unit long-running.

$$\mathrm{Shape} = \mathrm{fwWatch} \mid \mathrm{loop} \mid \mathrm{server} \mid \mathrm{tail} \mid \mathrm{longSleep}$$
-/
inductive Shape where
  | fwWatch | loop | server | tail | longSleep
deriving DecidableEq, Repr

/-- The caps: the longest `sleep` a backgrounded unit may hold, in seconds (default 30).

$$\mathrm{Caps} = (\mathit{maxSleepSec}), \qquad \mathit{maxSleepSec} = 30$$
-/
structure Caps where
  maxSleepSec : Nat := 30
deriving Repr

/-- A sleep argument in seconds: digits with an optional `s`/`m`/`h`/`d` suffix; anything else (`0.5`, `$n`) is `none`.

$$\mathrm{secs?}(w) = \begin{cases} \mathrm{some}(n \cdot m(c)) & w = r\,c \text{ (} c \text{ the last character of } w),\ m(c) \text{ defined},\ d \ne \varepsilon,\ \mathrm{toNat?}(d) = \mathrm{some}(n) \\ \mathrm{none} & \text{otherwise (also } w = \varepsilon) \end{cases}, \quad d = \begin{cases} w & c \in \texttt{0..9} \\ r & \text{else} \end{cases}, \quad m(c) = \begin{cases} 1 & c \in \texttt{0..9} \cup \{\texttt{s}\} \\ 60 & c = \texttt{m} \\ 3600 & c = \texttt{h} \\ 86400 & c = \texttt{d} \end{cases}$$
-/
def secs? (w : String) : Option Nat :=
  match w.toList.reverse with
  | [] => none
  | c :: rest =>
    let mul : Option Nat :=
      if c.isDigit then some 1 else if c == 's' then some 1 else if c == 'm' then some 60
      else if c == 'h' then some 3600 else if c == 'd' then some 86400 else none
    let digits := if c.isDigit then c :: rest else rest
    match mul, String.ofList digits.reverse |>.toNat? with
    | some m, some n => if digits.isEmpty then none else some (n * m)
    | _, _ => none

/-- Words that, with a following word, name a dev server or watcher.

$$\mathrm{pkgRunners} = [\texttt{pnpm}, \texttt{npm}, \texttt{yarn}, \texttt{bun}, \texttt{npx}, \texttt{run}]$$
-/
def pkgRunners : List String := ["pnpm", "npm", "yarn", "bun", "npx", "run"]

/-- The second words of a package-manager server command.

$$\mathrm{serverVerbs} = [\texttt{dev}, \texttt{serve}, \texttt{start}, \texttt{preview}]$$
-/
def serverVerbs : List String := ["dev", "serve", "start", "preview"]

/-- Words that are a server or watcher by themselves.

$$\mathrm{serverWords} = [\texttt{vite}, \texttt{http-server}, \texttt{nodemon}, \texttt{live-server}, \texttt{browser-sync}, \texttt{http.server}, \texttt{fswatch}, \texttt{-{}-watch}]$$
-/
def serverWords : List String := ["vite", "http-server", "nodemon", "live-server", "browser-sync", "http.server", "fswatch", "--watch"]

/-- The `fw` launcher: `fw`, `.../fw`, `fw.mjs`, `.../fw.mjs`.

$$\mathrm{isFw}(w) \iff w = \texttt{fw} \lor w \text{ ends with } \texttt{/fw} \lor w = \texttt{fw.mjs} \lor w \text{ ends with } \texttt{/fw.mjs}$$
-/
def isFw (w : String) : Bool := w == "fw" || w.endsWith "/fw" || w == "fw.mjs" || w.endsWith "/fw.mjs"

/-- The shapes found at each position of a word list (adjacent pairs matter). Here $n$ is the head of $r$ (`""` if
$r = [\,]$) and $[x \mid P]$ is $[x]$ when $P$ holds, else $[\,]$.

$$\mathrm{shapesOf}_c([\,]) = [\,], \qquad \mathrm{shapesOf}_c(w :: r) = [\mathrm{fwWatch} \mid \mathrm{isFw}(w) \land n = \texttt{watch}] \mathbin{+\!\!+} [\mathrm{server} \mid w \in \mathrm{serverWords} \lor (w \in \mathrm{pkgRunners} \land n \in \mathrm{serverVerbs})] \mathbin{+\!\!+} [\mathrm{server} \mid w \in \{\texttt{node}, \texttt{tsx}, \texttt{bun}, \texttt{python}, \texttt{python3}\} \land \texttt{server} \text{ occurs in } n] \mathbin{+\!\!+} [\mathrm{tail} \mid w = \texttt{tail} \land \exists x \in r.\ x \in \{\texttt{-f}, \texttt{-F}, \texttt{-{}-follow}\}] \mathbin{+\!\!+} [\mathrm{longSleep} \mid w = \texttt{sleep} \land \exists k.\ \mathrm{secs?}(n) = \mathrm{some}(k) \land c.\mathit{maxSleepSec} < k] \mathbin{+\!\!+} \mathrm{shapesOf}_c(r)$$
-/
def shapesOf (c : Caps) : List String → List Shape
  | [] => []
  | w :: rest =>
    let nxt := rest.head?.getD ""
    (if isFw w && nxt == "watch" then [Shape.fwWatch] else []) ++
    (if serverWords.contains w || (pkgRunners.contains w && serverVerbs.contains nxt) then [Shape.server] else []) ++
    (if (w == "node" || w == "tsx" || w == "bun" || w == "python" || w == "python3") && (nxt.splitOn "server").length > 1 then [Shape.server] else []) ++
    (if w == "tail" && rest.any (fun x => x == "-f" || x == "-F" || x == "--follow") then [Shape.tail] else []) ++
    (if w == "sleep" && (match secs? nxt with | some n => decide (c.maxSleepSec < n) | none => false) then [Shape.longSleep] else []) ++
    shapesOf c rest

/-- Block openers and closers, by first word.

$$\mathrm{openers} = [\texttt{until}, \texttt{while}, \texttt{for}, \texttt{if}, \texttt{case}, \texttt{select}]$$
-/
def openers : List String := ["until", "while", "for", "if", "case", "select"]

/-- Block closers.

$$\mathrm{closers} = [\texttt{done}, \texttt{fi}, \texttt{esac}]$$
-/
def closers : List String := ["done", "fi", "esac"]

/-- Reserved words that may come before the command of a segment (`do while ...`, `then until ...`, `! grep ...`).

$$\mathrm{prefixWords} = [\texttt{do}, \texttt{then}, \texttt{else}, \texttt{elif}, \texttt{\{}, \texttt{!}, \texttt{time}]$$
-/
def prefixWords : List String := ["do", "then", "else", "elif", "{", "!", "time"]

/-- The words of a segment from its command on: leading reserved prefix words dropped.

$$\mathrm{key}(W) = \mathrm{dropWhile}(\cdot \in \mathrm{prefixWords}, W)$$
-/
def key (ws : List String) : List String := ws.dropWhile (prefixWords.contains ·)

/-- The words that bound a loop on their own: a clock, a counter or an arithmetic test.

$$\mathrm{boundWords} = [\texttt{-lt}, \texttt{-le}, \texttt{-gt}, \texttt{-ge}, \texttt{date}, \texttt{SECONDS}, \texttt{\$SECONDS}, \texttt{deadline}, \texttt{DEADLINE}, \texttt{seq}]$$
-/
def boundWords : List String := ["-lt", "-le", "-gt", "-ge", "date", "SECONDS", "$SECONDS", "deadline", "DEADLINE", "seq"]

/-- Does a word bound a loop (also `$((...))` and `SECONDS=`-style words)?

$$\mathrm{isBoundWord}(w) \iff w \in \mathrm{boundWords} \lor w \text{ starts with one of } \texttt{\$((},\ \texttt{((},\ \texttt{SECONDS},\ \texttt{deadline=},\ \texttt{DEADLINE=}$$
-/
def isBoundWord (w : String) : Bool :=
  boundWords.contains w || w.startsWith "$((" || w.startsWith "((" || w.startsWith "SECONDS" || w.startsWith "deadline=" || w.startsWith "DEADLINE="

/-- A variable assignment word (`IFS=`, `LC_ALL=C`): it holds `=` and does not start with `-`.

$$\mathrm{isAssign}(w) \iff \texttt{=} \text{ occurs in } w \land w \text{ does not start with } \texttt{-}$$
-/
def isAssign (w : String) : Bool := (w.splitOn "=").length > 1 && !w.startsWith "-"

/-- A read loop: `while`, then optional assignments, then `read` (`while IFS= read -r line`). It ends when its input
does: `read` fails at end of input.

$$\mathrm{isReadLoop}(K) \iff K = \texttt{while} :: r \ \land\ \mathrm{head}(\mathrm{dropWhile}(\mathrm{isAssign}, r)) = \texttt{read}$$
-/
def isReadLoop : List String → Bool
  | "while" :: r => (r.dropWhile isAssign).head? == some "read"
  | _ => false

/-- A redirect target that is a finite input: non-empty, not a process substitution (`(...` or `<(...`), and not a
device other than `/dev/null` (`/dev/zero`, `/dev/stdin` and ttys may never end).

$$\mathrm{finiteTarget}(t) \iff t \ne \varepsilon \land t \text{ starts with neither } \texttt{(} \text{ nor } \texttt{<(} \land (t \text{ does not start with } \texttt{/dev/} \lor t = \texttt{/dev/null})$$
-/
def finiteTarget (t : String) : Bool :=
  t != "" && !t.startsWith "(" && !t.startsWith "<(" && (!t.startsWith "/dev/" || t == "/dev/null")

/-- Does a word list hold a finite input redirect: `<` or `0<` followed by a finite target, a word `<t` with a finite
target `t`, or a here-document / here-string word (starting with `<<`)? Here $n$ is the head of $r$ (`""` if none).

$$\mathrm{finiteRedir}([\,]) = \bot, \qquad \mathrm{finiteRedir}(w :: r) = \begin{cases} \mathrm{finiteTarget}(n) & w \in \{\texttt{<}, \texttt{0<}\} \\ \top & w = \texttt{<<}\,x \\ \mathrm{finiteTarget}(t) & w = \texttt{<}\,t,\ t \ne \varepsilon \\ \bot & \text{otherwise} \end{cases} \ \lor\ \mathrm{finiteRedir}(r) \quad \text{(first matching row)}$$
-/
def finiteRedir : List String → Bool
  | [] => false
  | w :: rest =>
    (if w == "<" || w == "0<" then finiteTarget (rest.head?.getD "")
     else match w.toList with
       | '<' :: '<' :: _ => true
       | '<' :: t@(_ :: _) => finiteTarget (String.ofList t)
       | _ => false) || finiteRedir rest

/-- A pipeline producer that ends by itself: a plain command (its first command word $k$ is not empty, not a block
opener or closer, not `yes`; the segment is not a bare `cat`, which reads the tool's stdin), with no long shape and no
follow word (`-f`, `-F`, `--follow`, `watch`). Here $K = \mathrm{key}(W)$ and $k$ the head of $K$ (`""` if none).

$$\mathrm{finiteProducer}_c(W) \iff k \ne \varepsilon \land k \notin \mathrm{openers} \cup \mathrm{closers} \cup \{\texttt{yes}\} \land K \ne [\texttt{cat}] \land \mathrm{shapesOf}_c(W) = [\,] \land \forall x \in W.\ x \notin \{\texttt{-f}, \texttt{-F}, \texttt{-{}-follow}, \texttt{watch}\}$$
-/
def finiteProducer (c : Caps) (ws : List String) : Bool :=
  let ks := key ws
  let k := ks.head?.getD ""
  k != "" && !openers.contains k && !closers.contains k && k != "yes" && ks != ["cat"] &&
    (shapesOf c ws).isEmpty && !ws.any (fun x => x == "-f" || x == "-F" || x == "--follow" || x == "watch")

/-- Facts about one unit (the thing a trailing `&` backgrounds).

$$\mathrm{Job} = (\mathit{bg} \in \mathbb{B},\ \mathit{shapes} \in \mathrm{Shape}^{*},\ \mathit{unbounded} \in \mathbb{B})$$
-/
structure Job where
  bg        : Bool
  shapes    : List Shape
  unbounded : Bool
deriving DecidableEq, Repr

/-- The running state of the unit grouping: the open blocks (innermost first; `true` marks a read loop whose input is
not yet known to be finite, decided at its `done`), the shapes so far, whether a loop with no input bound was seen
(`free`), a bound word, a `timeout` wrapper, whether the unit is still empty, the previous segment and the finished
units.

$$\mathrm{UAcc} = \mathbb{B}^{*} \times \mathrm{Shape}^{*} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Seg} \times \mathrm{Job}^{*}, \quad u = (\mathit{stack}, \mathit{shapes}, \mathit{free}, \mathit{bound}, \mathit{wrapped}, \mathit{fresh}, \mathit{last}, \mathit{units}), \quad \{\} = ([\,], [\,], \bot, \bot, \bot, \top, ([\,], \mathrm{fin}), [\,])$$
-/
structure UAcc where
  stack   : List Bool := []
  shapes  : List Shape := []
  free    : Bool := false
  bound   : Bool := false
  wrapped : Bool := false
  fresh   : Bool := true
  last    : Seg := ⟨[], .fin⟩
  units   : List Job := []

/-- Add one segment to the grouping; close the unit when no block is open and the segment ends the list. Here
$K = \mathrm{key}(s.\mathit{words})$, $f$ its head (`""` if none), $\ell \iff f \in \{\texttt{until}, \texttt{while}\}$,
$\rho = \mathrm{isReadLoop}(K)$, and $\pi \iff u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land
\mathrm{finiteProducer}_c(u.\mathit{last}.\mathit{words})$ (the loop reads a finite pipe).

$$\mathrm{addSeg}_c(u, s) = \begin{cases} \{\}[\mathit{units} := (s.\mathit{term} = \mathrm{bg},\ u'.\mathit{shapes},\ u'.\mathit{free} \land \lnot(u'.\mathit{bound} \lor u'.\mathit{wrapped})) :: u.\mathit{units}] & S = [\,] \land s.\mathit{term} \notin \{\mathrm{join}, \mathrm{pipe}\} \\ u' & \text{otherwise} \end{cases}$$
$$(S, \phi) = \begin{cases} ((\rho \land \lnot\pi) :: u.\mathit{stack},\ \bot) & f \in \mathrm{openers} \\ (r,\ p \land \lnot \mathrm{finiteRedir}(s.\mathit{words})) & f \in \mathrm{closers},\ u.\mathit{stack} = p :: r \\ ([\,], \bot) & f \in \mathrm{closers},\ u.\mathit{stack} = [\,] \\ (u.\mathit{stack}, \bot) & \text{otherwise} \end{cases}$$
$$u' = u[\mathit{stack} := S,\ \mathit{shapes} := u.\mathit{shapes} \mathbin{+\!\!+} [\mathrm{loop} \mid \ell] \mathbin{+\!\!+} \mathrm{shapesOf}_c(s.\mathit{words}),\ \mathit{free} := u.\mathit{free} \lor (\ell \land \lnot\rho) \lor \phi,\ \mathit{bound} := u.\mathit{bound} \lor \exists x \in s.\mathit{words}.\ \mathrm{isBoundWord}(x),\ \mathit{wrapped} := (u.\mathit{fresh}\ ?\ f \in \{\texttt{timeout}, \texttt{gtimeout}\} : u.\mathit{wrapped}),\ \mathit{fresh} := \bot,\ \mathit{last} := s]$$
-/
def addSeg (c : Caps) (u : UAcc) (s : Seg) : UAcc :=
  let f := (key s.words).head?.getD ""
  let isLoop := f == "until" || f == "while"
  let rl := isReadLoop (key s.words)
  let piped := u.last.term == .pipe && finiteProducer c u.last.words
  let (stack, phi) : List Bool × Bool :=
    if openers.contains f then ((rl && !piped) :: u.stack, false)
    else if closers.contains f then
      match u.stack with
      | p :: r => (r, p && !finiteRedir s.words)
      | [] => ([], false)
    else (u.stack, false)
  let wrapped := if u.fresh then (f == "timeout" || f == "gtimeout") else u.wrapped
  let sh := (if isLoop then [Shape.loop] else []) ++ shapesOf c s.words
  let u' := { u with stack, shapes := u.shapes ++ sh, free := u.free || (isLoop && !rl) || phi,
                     bound := u.bound || s.words.any isBoundWord, wrapped, fresh := false, last := s }
  if stack.isEmpty && s.term != .join && s.term != .pipe then
    { units := ⟨s.term == .bg, u'.shapes, u'.free && !(u'.bound || u'.wrapped)⟩ :: u.units }
  else u'

/-- The units of a command (a trailing open unit is closed at the end; a read loop still open there counts as free).
Here $u = \mathrm{foldl}(\mathrm{addSeg}_c, \{\}, \mathrm{parse}(\mathit{cmd}))$.

$$\mathrm{units}_c(\mathit{cmd}) = \mathrm{rev}\begin{cases} u.\mathit{units} & u.\mathit{fresh} \\ (\bot,\ u.\mathit{shapes},\ (u.\mathit{free} \lor \top \in u.\mathit{stack}) \land \lnot(u.\mathit{bound} \lor u.\mathit{wrapped})) :: u.\mathit{units} & \text{otherwise} \end{cases}$$
-/
def units (c : Caps) (cmd : String) : List Job :=
  let u := (parse cmd).foldl (addSeg c) {}
  let u := if u.fresh then u
    else { u with units := ⟨false, u.shapes, (u.free || u.stack.any id) && !(u.bound || u.wrapped)⟩ :: u.units }
  u.units.reverse

/-- A `while`/`until` segment that is not a read loop marks the loop free (unbounded unless a bound word or a `timeout`
wrapper is in the unit): its own block stays open, so the unit does not close here.

$$\forall c, u, s.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \in \{\texttt{while}, \texttt{until}\} \land \lnot \mathrm{isReadLoop}(\mathrm{key}(s.\mathit{words})) \ \Rightarrow\ \mathrm{addSeg}_c(u, s).\mathit{free}$$
-/
theorem plainLoop_free (c : Caps) (u : UAcc) (s : Seg)
    (hf : (key s.words).head? = some "while" ∨ (key s.words).head? = some "until")
    (hr : isReadLoop (key s.words) = false) : (addSeg c u s).free = true := by
  have hf' : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = true := by
    rcases hf with h | h <;> simp [h]
  have ho : openers.contains ((key s.words).head?.getD "") = true := by
    rcases hf with h | h <;> simp [h, openers]
  unfold addSeg
  simp only [hf', hr, ho, ite_true]
  simp

/-- One segment inside an open block whose command is no block opener or closer changes neither the open blocks, nor
the free flag, nor the finished units.

$$\forall c, u, s.\ u.\mathit{stack} \ne [\,] \land f \notin \mathrm{openers} \cup \mathrm{closers} \ \Rightarrow\ \mathrm{addSeg}_c(u, s).\mathit{stack} = u.\mathit{stack} \land \mathrm{addSeg}_c(u, s).\mathit{free} = u.\mathit{free} \land \mathrm{addSeg}_c(u, s).\mathit{units} = u.\mathit{units}, \quad f = \mathrm{head}(\mathrm{key}(s.\mathit{words}))$$
-/
theorem addSeg_inner (c : Caps) (u : UAcc) (s : Seg) (hs : u.stack ≠ [])
    (ho : openers.contains ((key s.words).head?.getD "") = false)
    (hc : closers.contains ((key s.words).head?.getD "") = false) :
    (addSeg c u s).stack = u.stack ∧ (addSeg c u s).free = u.free ∧ (addSeg c u s).units = u.units := by
  have hl : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = false := by
    cases h1 : ((key s.words).head?.getD "" == "until") <;> cases h2 : ((key s.words).head?.getD "" == "while") <;>
      simp_all [openers]
  unfold addSeg
  simp only [ho, hc, hl]
  simp [hs]

/-- The body of a block (segments with no block opener or closer) changes neither the open blocks, nor the free flag,
nor the finished units, while a block is open.

$$\forall c, B, u.\ u.\mathit{stack} \ne [\,] \land (\forall s \in B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \ \Rightarrow\ v.\mathit{stack} = u.\mathit{stack} \land v.\mathit{free} = u.\mathit{free} \land v.\mathit{units} = u.\mathit{units}, \quad v = \mathrm{foldl}(\mathrm{addSeg}_c, u, B)$$
-/
theorem addSeg_body (c : Caps) (body : List Seg) (u : UAcc) (hs : u.stack ≠ [])
    (hb : ∀ s ∈ body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false) :
    (body.foldl (addSeg c) u).stack = u.stack ∧ (body.foldl (addSeg c) u).free = u.free ∧
      (body.foldl (addSeg c) u).units = u.units := by
  induction body generalizing u with
  | nil => simp
  | cons s body ih =>
    have h1 := addSeg_inner c u s hs (hb s (by simp)).1 (hb s (by simp)).2
    have := ih (addSeg c u s) (h1.1 ▸ hs) (fun x hx => hb x (by simp [hx]))
    simp only [List.foldl_cons]
    exact ⟨this.1.trans h1.1, this.2.1.trans h1.2.1, this.2.2.trans h1.2.2⟩

/-- **Read loops are bounded by their input.** A block `while [assignments] read ...; B; done` whose body $B$ opens and
closes no block adds no free (unbounded) loop when its input is finite: either the segment before it is a finite
producer piped into it (`git ls-files | while read f; ...`), or its `done` segment holds a finite input redirect
(`done < file`, `done <<EOF`, `done <<< "$x"`). Starting from a state with no free loop, the grouping still has no free
loop, and the unit closed by `done` (if any) is bounded.

$$\forall c, u, w, d, B.\ \neg u.\mathit{free} \land \mathrm{isReadLoop}(\mathrm{key}(w.\mathit{words})) \land (\forall s \in B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \land \mathrm{head}(\mathrm{key}(d.\mathit{words})) = \texttt{done} \land \big((u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land \mathrm{finiteProducer}_c(u.\mathit{last}.\mathit{words})) \lor \mathrm{finiteRedir}(d.\mathit{words})\big)$$
$$\Rightarrow\ \neg v.\mathit{free} \land (v.\mathit{units} = u.\mathit{units} \lor \exists j.\ v.\mathit{units} = j :: u.\mathit{units} \land \neg j.\mathit{unbounded}), \quad v = \mathrm{foldl}(\mathrm{addSeg}_c, u, w :: B \mathbin{+\!\!+} [d])$$
-/
theorem readLoop_bounded (c : Caps) (u : UAcc) (w d : Seg) (body : List Seg)
    (hu : u.free = false) (hw : isReadLoop (key w.words) = true)
    (hb : ∀ s ∈ body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false)
    (hd : (key d.words).head? = some "done")
    (hin : (u.last.term = .pipe ∧ finiteProducer c u.last.words = true) ∨ finiteRedir d.words = true) :
    ((w :: body ++ [d]).foldl (addSeg c) u).free = false ∧
      (((w :: body ++ [d]).foldl (addSeg c) u).units = u.units ∨
        ∃ j, ((w :: body ++ [d]).foldl (addSeg c) u).units = j :: u.units ∧ j.unbounded = false) := by
  -- the `while` segment
  have hwh : (key w.words).head? = some "while" := by
    match h : key w.words with
    | "while" :: _ => simp
    | [] => simp [h, isReadLoop] at hw
    | x :: r =>
      have : x = "while" := by
        rw [h] at hw
        unfold isReadLoop at hw
        split at hw
        · simp_all
        · simp at hw
      simp [this]
  let pushed := isReadLoop (key w.words) && !(u.last.term == .pipe && finiteProducer c u.last.words)
  have hpush : pushed = true → finiteRedir d.words = true := by
    intro hp
    rcases hin with ⟨h1, h2⟩ | h
    · simp [pushed, h1, h2] at hp
    · exact h
  have hw1 : (addSeg c u w).stack = pushed :: u.stack ∧ (addSeg c u w).free = false ∧
      (addSeg c u w).units = u.units := by
    unfold addSeg
    simp only [hwh, hw]
    simp [hu, pushed, hw, openers]
  -- the body
  have hne : (addSeg c u w).stack ≠ [] := by rw [hw1.1]; simp
  have hb1 := addSeg_body c body (addSeg c u w) hne hb
  -- the `done` segment
  generalize hv : body.foldl (addSeg c) (addSeg c u w) = v at hb1
  have hvs : v.stack = pushed :: u.stack := hb1.1.trans hw1.1
  have hvf : v.free = false := hb1.2.1.trans hw1.2.1
  have hvu : v.units = u.units := hb1.2.2.trans hw1.2.2
  have hphi : (pushed && !finiteRedir d.words) = false := by
    cases hp : pushed
    · simp
    · simp [hpush hp]
  have hfold : (w :: body ++ [d]).foldl (addSeg c) u = addSeg c v d := by
    simp [List.foldl_append, hv]
  rw [hfold]
  have hk : (key d.words).head?.getD "" = "done" := by simp [hd]
  have hdo' : openers.contains "done" = false := by decide
  have hdc' : closers.contains "done" = true := by decide
  unfold addSeg
  simp only [hk, hdo', hdc', hvs, hvf, hvu, hphi, Bool.false_eq_true, ite_false, ite_true]
  split
  · exact ⟨by simp, Or.inr ⟨_, rfl, by simp⟩⟩
  · exact ⟨by simp, Or.inl rfl⟩

/-! ## The decision -/

/-- Why a command is refused.

$$\mathrm{Reason} = \mathrm{bgLong}(s) \mid \mathrm{unboundedLoop}, \quad s \in \mathrm{Shape}$$
-/
inductive Reason where
  | bgLong (s : Shape)
  | unboundedLoop
deriving DecidableEq, Repr

/-- The guard's answer.

$$\mathrm{Decision} = \mathrm{allow} \mid \mathrm{deny}(r),\ r \in \mathrm{Reason}$$
-/
inductive Decision where
  | allow
  | deny (r : Reason)
deriving DecidableEq, Repr

/-- The first reason a unit list is refused: a backgrounded long unit first, else an unbounded loop.

$$\mathrm{check}(U) = \begin{cases} \mathrm{some}(\mathrm{bgLong}(\mathrm{head}(u.\mathit{shapes}))) & u \text{ is the first } u \in U \text{ with } u.\mathit{bg} \land u.\mathit{shapes} \ne [\,] \\ \mathrm{some}(\mathrm{unboundedLoop}) & \text{no such } u,\ \exists u \in U.\ u.\mathit{unbounded} \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def check (us : List Job) : Option Reason :=
  match us.find? (fun u => u.bg && !u.shapes.isEmpty) with
  | some u => (u.shapes.head?).map Reason.bgLong
  | none => if us.any (·.unbounded) then some .unboundedLoop else none

/-- The decision for a list of units.

$$\mathrm{decide}(U) = \mathrm{deny}(r) \text{ if } \mathrm{check}(U) = r, \text{ else allow}$$
-/
def decide (us : List Job) : Decision :=
  match check us with
  | some r => .deny r
  | none => .allow

/-- The decision for a command text.

$$\mathrm{decideCmd}(\mathit{caps}, \mathit{cmd}) = \mathrm{decide}(\mathrm{units}(\mathit{cmd}))$$
-/
def decideCmd (c : Caps) (cmd : String) : Decision := decide (units c cmd)

/-- A backgrounded unit that holds a long shape is refused (`bgLong`).

$$u \in U,\ u.\mathit{bg},\ u.\mathit{shapes} \ne [] \ \Rightarrow\ \exists s.\ \mathrm{decide}(U) = \mathrm{deny}(\mathrm{bgLong}(s))$$
-/
theorem bg_long_denied (us : List Job) (u : Job) (hu : u ∈ us) (hb : u.bg = true) (hs : u.shapes ≠ []) :
    ∃ s, decide us = .deny (.bgLong s) := by
  have hex : (us.find? (fun u => u.bg && !u.shapes.isEmpty)).isSome = true := by
    rw [List.find?_isSome]
    exact ⟨u, hu, by simp [hb, hs]⟩
  obtain ⟨v, hv⟩ := Option.isSome_iff_exists.mp hex
  have hvp := List.find?_some hv
  simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at hvp
  obtain ⟨s, t, hst⟩ := List.exists_cons_of_ne_nil hvp.2
  refine ⟨s, ?_⟩
  simp [decide, check, hv, hst]

/-- A command with no backgrounded long unit and no unbounded loop is allowed.

$$(\forall u \in U.\ \lnot(u.\mathit{bg} \land u.\mathit{shapes} \ne []) \land \lnot u.\mathit{unbounded}) \ \Rightarrow\ \mathrm{decide}(U) = \mathrm{allow}$$
-/
theorem clean_allowed (us : List Job)
    (h : ∀ u ∈ us, ¬ (u.bg = true ∧ u.shapes ≠ []) ∧ u.unbounded = false) : decide us = .allow := by
  have h1 : us.find? (fun u => u.bg && !u.shapes.isEmpty) = none := by
    rw [List.find?_eq_none]
    intro u hu
    have := (h u hu).1
    simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff]
    intro hb
    exact this ⟨by simpa using hb.1, hb.2⟩
  have h2 : us.any (·.unbounded) = false := by
    simp only [List.any_eq_false]
    intro u hu
    simp [(h u hu).2]
  simp [decide, check, h1, h2]

/-- A foreground command (no unit backgrounded) is refused only for an unbounded loop.

$$(\forall u \in U.\ \lnot u.\mathit{bg}) \ \Rightarrow\ \mathrm{decide}(U) \ne \mathrm{deny}(\mathrm{bgLong}(s))$$
-/
theorem foreground_never_bgLong (us : List Job) (h : ∀ u ∈ us, u.bg = false) (s : Shape) :
    decide us ≠ .deny (.bgLong s) := by
  have h1 : us.find? (fun u => u.bg && !u.shapes.isEmpty) = none := by
    rw [List.find?_eq_none]
    intro u hu
    simp [h u hu]
  by_cases h2 : us.any (·.unbounded) = true
  · simp [decide, check, h1, h2]
  · simp [decide, check, h1, h2]

/-- A refused command names its reason (every `deny` carries one; `allow` carries none).

$$\mathrm{decide}(U) = \mathrm{deny}(r) \iff \mathrm{check}(U) = \mathrm{some}(r)$$
-/
theorem deny_iff_check (us : List Job) (r : Reason) : decide us = .deny r ↔ check us = some r := by
  unfold decide
  cases h : check us <;> simp

/-! ## Examples -/

#guard hereDelim "" "<<EOF".toList == some ("EOF".toList, false)
#guard hereDelim "" "<<-EOF".toList == some ("EOF".toList, true)
#guard hereDelim "<<" "PY".toList == some ("PY".toList, false)
#guard hereDelim "" "<<<".toList == none
#guard hereDelim "" "<<-".toList == none
#guard hereDelim "" "<<".toList == none
#guard isReadLoop ["while", "IFS=", "read", "-r", "line"]
#guard !isReadLoop ["while", "true"]
#guard !isReadLoop ["until", "read", "x"]
#guard finiteRedir ["done", "<", "f.txt"] && finiteRedir ["done", "<f"] && finiteRedir ["done", "<<<", "$x"]
#guard finiteRedir ["done", "<<EOF"] && finiteRedir ["done", "<", "/dev/null"]
#guard !finiteRedir ["done", "<", "<(tail", "-f", "x)"] && !finiteRedir ["done", "<", "/dev/zero"] && !finiteRedir ["done"]
#guard finiteProducer {} ["git", "ls-files"] && finiteProducer {} ["find", "."]
#guard !finiteProducer {} ["yes"] && !finiteProducer {} ["cat"] && !finiteProducer {} ["tail", "-f", "x"]
#guard !finiteProducer {} ["done"] && !finiteProducer {} ["gh", "run", "watch", "1"]
#guard (parse "a | b || c").map (·.term) == [.pipe, .join, .fin]
#guard parse "cat <<'EOF' > f\nwhile true; do x; done\nEOF\necho ok" == [⟨["cat", "<<EOF", ">", "f"], .seq⟩, ⟨["echo", "ok"], .fin⟩]
#guard decideCmd {} "while IFS= read -r l; do echo \"$l\"; done < f.txt" == .allow
#guard decideCmd {} "git ls-files | while read -r f; do echo $f; done | sort" == .allow
#guard decideCmd {} "while read -r a; do echo $a; done <<< \"$x\"" == .allow
#guard decideCmd {} "cat > f.py <<'EOF'\nwhile True:\n  pass\nEOF\npython3 f.py" == .allow
#guard decideCmd {} "cat <<-EOF > x\n\twhile true; do sleep 1; done\n\tEOF\necho ok" == .allow
#guard decideCmd {} "find . -type f | while read f; do while read l; do echo $l; done < \"$f\"; done" == .allow
#guard decideCmd {} "while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "tail -f log | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "yes | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "while read l < f; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done < <(tail -f x)" == .deny .unboundedLoop
#guard decideCmd {} "for f in a b; do while true; do sleep 1; done; done" == .deny .unboundedLoop
#guard decideCmd {} "cat <<EOF > f\nx\nEOF\nwhile true; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ \"$(gh run view 1 --json status -q .status)\" = completed ]; do sleep 150; done" == .deny .unboundedLoop
#guard decideCmd {} "ls | while read f; do echo $f; done &" == .deny (.bgLong .loop)
#guard decideCmd {} "cat <<EOF > f\nhi\nEOF\npnpm fw watch &" == .deny (.bgLong .fwWatch)
#guard decideCmd {} "a || b &" == .allow

end Fw.Ops.Wait
