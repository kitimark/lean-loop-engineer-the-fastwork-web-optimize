/-!
# Wait guard (PLAN §8.3 `PreToolUse` matcher `Bash`; mistake class `c-orphan-wait`)

Two things, both pure.

**1. Waits are bounded and owned.** A wait is an owner plus a deadline. `waitOk` admits it only with a
non-empty owner and a deadline in `1..cap`; `waitEnd` is when the wait stops whatever the condition
does. Proved: `wait_bounded` (every admitted wait stops by its deadline, which is `≤ cap`, and has an
owner). Handback: `handbackOk` allows an agent to hand back only when every background task it
started has ended; proved `handback_no_open_bg`.

**2. A foreground `Bash` call must not start a long-running process with `&`.** The command is parsed
(`parse`) into segments split at `; \n | || && &` (here-document bodies are skipped: they are data; a body opens only at
an unquoted `<<`), grouped into *units* (an and-or list or a whole `until/while/for/if/case ... done/fi/esac` compound,
the thing a trailing `&` backgrounds). A unit is *long* when it holds one of the `Shape`s: `fw watch`, an
`until`/`while` loop, a server or watcher, a `tail -f`, or a `sleep` longer than `caps.maxSleepSec`. `decide` refuses a
backgrounded long unit (`bgLong`: use the tool's `run_in_background`, which has an owner and a stop) and any
`until`/`while` loop with no bound (`unboundedLoop`: no `timeout` wrapper, no counter / clock test, and not a read loop
`while read [opts] [names]; do ... done` over a finite input: a file, a here-document or here-string, or an allowlisted
finite producer piped in or given as `< <(...)`).

The read-loop rule is a fact about this classification (`readLoop_bounded`), not about bash: that such a loop ends
rests on the premises that `read` fails at the end of a finite input and that the allowlisted producers
(`producerOut`) end; the stdin of a pipeline head is the Bash tool's stdin, `/dev/null` (MEASURED 2026-10-18: fd 0 is
the character device `/dev/null`, `timeout 5 cat` exits 0 at once).

The shapes are a small documented set, tested by goldens; the parse is approximate on purpose.
Known blind spots (shadow-logged, not claimed): code inside `$( )`, `( )`, `{ }` groups, function bodies or
`sh -c '...'` strings, aliases, variables naming a device or a FIFO (`< "$f"`), and a here-document operator glued to
a word or inside arithmetic (`cat<<EOF`, `$((1 << 2))`).
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

$$\forall w, \mathit{sat}.\ \mathrm{end}(w, \mathit{sat}) \le w.\mathit{deadline}$$
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

$$\forall E.\ \mathrm{handback}(E) \ \Rightarrow\ \forall i.\ \mathrm{start}(i) \in E \Rightarrow \mathrm{end}(i) \in E$$
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
`&&`, `&>` or a background), comment, the previous character, the current word (reversed), the length the current word
had at its first quote or backslash (`none`: no quoting yet), whether the previous word of the segment was an unquoted
here-document operator `<<` (`some false`) or `<<-` (`some true`), the current words (reversed), the finished segments
(reversed), the here-document delimiters still to read (each with its `<<-` flag: leading tabs stripped), whether the
scanner is inside a here-document body, and the body line read so far (reversed).

$$\mathrm{Acc} = \mathbb{N} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Char} \times \mathrm{Char}^{*} \times \mathrm{Option}(\mathbb{N}) \times \mathrm{Option}(\mathbb{B}) \times \mathrm{String}^{*} \times \mathrm{Seg}^{*} \times (\mathrm{Char}^{*} \times \mathbb{B})^{*} \times \mathbb{B} \times \mathrm{Char}^{*}$$
$$a = (\mathit{quote}, \mathit{esc}, \mathit{pend}, \mathit{comment}, \mathit{prev}, \mathit{word}, \mathit{qat}, \mathit{lastOp}, \mathit{words}, \mathit{segs}, \mathit{hd}, \mathit{body}, \mathit{line}), \quad \{\} = (0, \bot, \bot, \bot, \texttt{' '}, [\,], \mathrm{none}, \mathrm{none}, [\,], [\,], [\,], \bot, [\,])$$
-/
structure Acc where
  quote   : Nat := 0
  esc     : Bool := false
  pend    : Bool := false
  comment : Bool := false
  prev    : Char := ' '
  word    : List Char := []
  qat     : Option Nat := none
  lastOp  : Option Bool := none
  words   : List String := []
  segs    : List Seg := []
  hd      : List (List Char × Bool) := []
  body    : Bool := false
  line    : List Char := []

/-- The first two characters of the current word were typed unquoted (its first quote or backslash, if any, comes at
position 2 or later), so a leading `<<` in it is the here-document operator and not text.

$$\mathrm{leadOpen}(q) \iff q = \mathrm{none} \ \lor\ \exists n.\ q = \mathrm{some}(n) \land 2 \le n$$
-/
def leadOpen : Option Nat → Bool
  | none => true
  | some n => decide (2 ≤ n)

/-- The here-document delimiter a finished word `w` opens. After an unquoted `<<` (or `<<-`) operator word
($\mathit{op} = \mathrm{some}(t)$) the whole word is the delimiter; otherwise only a word whose leading `<<` is unquoted
($\mathit{opn}$) opens one: the rest of a word `<<D` or `<<-D` with `D` non-empty; a here-string `<<<` opens none. The
flag is true for `<<-` (the closing line may start with tabs). Quotes are already removed, so `<<'EOF'` is `<<EOF`.

$$\mathrm{hereDelim}(\mathit{op}, \mathit{opn}, w) = \begin{cases} \mathrm{some}(w, t) & \mathit{op} = \mathrm{some}(t) \\ \mathrm{none} & \mathit{op} = \mathrm{none},\ \lnot \mathit{opn} \\ \mathrm{none} & w = \texttt{<<<}\,r \\ \mathrm{none} & w = \texttt{<<-} \\ \mathrm{some}(D, \top) & w = \texttt{<<-}\,D,\ D \ne \varepsilon \\ \mathrm{some}(D, \bot) & w = \texttt{<<}\,D,\ D \ne \varepsilon \\ \mathrm{none} & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def hereDelim (op : Option Bool) (opn : Bool) (w : List Char) : Option (List Char × Bool) :=
  match op with
  | some t => some (w, t)
  | none =>
    if !opn then none
    else match w with
      | '<' :: '<' :: '<' :: _ => none
      | ['<', '<', '-'] => none
      | '<' :: '<' :: '-' :: d@(_ :: _) => some (d, true)
      | '<' :: '<' :: d@(_ :: _) => some (d, false)
      | _ => none

/-- The operator state after a finished word `w`: an unquoted word `<<` or `<<-` (its leading `<<` unquoted, $\mathit{opn}$)
makes the next word the delimiter.

$$\mathrm{opWord}(\mathit{opn}, w) = \begin{cases} \mathrm{some}(\bot) & \mathit{opn},\ w = \texttt{<<} \\ \mathrm{some}(\top) & \mathit{opn},\ w = \texttt{<<-} \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def opWord (opn : Bool) (w : List Char) : Option Bool :=
  if opn && w == ['<', '<'] then some false
  else if opn && w == ['<', '<', '-'] then some true
  else none

/-- Finish the current word (if any); a word that opens a here-document queues its delimiter. Here
$w = \mathrm{rev}(a.\mathit{word})$, $\mathit{opn} = \mathrm{leadOpen}(a.\mathit{qat})$, and $\mathrm{toList}(\mathrm{none}) = [\,]$,
$\mathrm{toList}(\mathrm{some}(x)) = [x]$.

$$\mathrm{flushWord}(a) = \begin{cases} a[\mathit{qat} := \mathrm{none}] & a.\mathit{word} = [\,] \\ a[\mathit{words} := \mathrm{str}(w) :: a.\mathit{words},\ \mathit{word} := [\,],\ \mathit{qat} := \mathrm{none},\ \mathit{hd} := a.\mathit{hd} \mathbin{+\!\!+} \mathrm{toList}(\mathrm{hereDelim}(a.\mathit{lastOp}, \mathit{opn}, w)),\ \mathit{lastOp} := \mathrm{opWord}(\mathit{opn}, w)] & \text{otherwise} \end{cases}$$
-/
def flushWord (a : Acc) : Acc :=
  if a.word.isEmpty then { a with qat := none }
  else
    let w := a.word.reverse
    let opn := leadOpen a.qat
    { a with words := String.ofList w :: a.words, word := [], qat := none,
             hd := a.hd ++ (hereDelim a.lastOp opn w).toList, lastOp := opWord opn w }

/-- A word whose leading `<<` was quoted or escaped (`"<<EOF"`, `'<<'`, `\<<EOF`), not after an unquoted `<<` operator,
queues no here-document and is no operator: the text after it stays code.

$$\forall a.\ a.\mathit{lastOp} = \mathrm{none} \land \lnot \mathrm{leadOpen}(a.\mathit{qat}) \ \Rightarrow\ \mathrm{flushWord}(a).\mathit{hd} = a.\mathit{hd} \land \mathrm{flushWord}(a).\mathit{lastOp} = \mathrm{none}$$
-/
theorem flushWord_quoted (a : Acc) (h1 : a.lastOp = none) (h2 : leadOpen a.qat = false) :
    (flushWord a).hd = a.hd ∧ (flushWord a).lastOp = none := by
  unfold flushWord
  split
  · simp [h1]
  · simp [h1, h2, hereDelim, opWord]

/-- Finish the current segment with a terminator. An empty segment is dropped (so `a &&⏎ b` stays one list), except a
`bg` or `fin` terminator on an empty segment is dropped too: there is nothing to background. The operator state is
reset: a delimiter word must be in the operator's segment.

$$\mathrm{endSeg}(a, t) = \begin{cases} a' & a'.\mathit{words} = [\,] \\ a'[\mathit{words} := [\,],\ \mathit{segs} := (\mathrm{rev}(a'.\mathit{words}), t) :: a'.\mathit{segs}] & \text{otherwise} \end{cases}, \quad a' = \mathrm{flushWord}(a)[\mathit{lastOp} := \mathrm{none}]$$
-/
def endSeg (a : Acc) (t : Term) : Acc :=
  let a := { flushWord a with lastOp := none }
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

/-- Record that the current word is quoted from here on: the word length at its first quote or backslash.

$$\mathrm{mark}(a) = \begin{cases} a[\mathit{qat} := \mathrm{some}(|a.\mathit{word}|)] & a.\mathit{qat} = \mathrm{none} \\ a & \text{otherwise} \end{cases}$$
-/
def mark (a : Acc) : Acc :=
  match a.qat with
  | none => { a with qat := some a.word.length }
  | some _ => a

/-- Process one character that is not a pending `&` resolver (the first matching row applies; ⏎ is newline).

$$\mathrm{stepPlain}(a, c) = \begin{cases} \mathrm{newline}(a[\mathit{comment} := \bot]) & a.\mathit{comment},\ c = \text{⏎} \\ a & a.\mathit{comment},\ c \ne \text{⏎} \\ \mathrm{push}(a[\mathit{esc} := \bot], c) & a.\mathit{esc} \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 1,\ c = \texttt{'} \\ \mathrm{push}(a, c) & a.\mathit{quote} = 1 \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 2,\ c = \texttt{"} \\ a[\mathit{esc} := \top] & a.\mathit{quote} = 2,\ c = \backslash \\ \mathrm{push}(a, c) & a.\mathit{quote} = 2 \\ \mathrm{mark}(a)[\mathit{quote} := 1] & c = \texttt{'} \\ \mathrm{mark}(a)[\mathit{quote} := 2] & c = \texttt{"} \\ \mathrm{mark}(a)[\mathit{esc} := \top] & c = \backslash \\ \mathrm{flushWord}(a) & c \in \{\text{space}, \text{tab}, \text{CR}\} \\ \mathrm{newline}(a) & c = \text{⏎} \\ \mathrm{endSeg}(a, \mathrm{seq}) & c = \texttt{;} \\ \mathrm{unpipe}(a) & c = \texttt{|},\ a.\mathit{prev} = \texttt{|} \\ \mathrm{endSeg}(a, \mathrm{pipe}) & c = \texttt{|} \\ a[\mathit{comment} := \top] & c = \texttt{\#},\ a.\mathit{word} = [\,] \\ \mathrm{push}(a, c) & c = \texttt{\&},\ a.\mathit{prev} \in \{\texttt{>}, \texttt{<}\} \\ a[\mathit{pend} := \top] & c = \texttt{\&} \\ \mathrm{push}(a, c) & \text{otherwise} \end{cases}$$
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
  else if c == '\'' then { mark a with quote := 1 }
  else if c == '"' then { mark a with quote := 2 }
  else if c == '\\' then { mark a with esc := true }
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

$$\mathrm{boundWords} = [\texttt{-lt}, \texttt{-le}, \texttt{-gt}, \texttt{-ge}, \texttt{date}, \texttt{SECONDS}, \texttt{\$SECONDS}, \texttt{deadline}, \texttt{DEADLINE}]$$
-/
def boundWords : List String := ["-lt", "-le", "-gt", "-ge", "date", "SECONDS", "$SECONDS", "deadline", "DEADLINE"]

/-- Does a word bound a loop (also `$((...))` and `SECONDS=`-style words)?

$$\mathrm{isBoundWord}(w) \iff w \in \mathrm{boundWords} \lor w \text{ starts with one of } \texttt{\$((},\ \texttt{((},\ \texttt{SECONDS},\ \texttt{deadline=},\ \texttt{DEADLINE=}$$
-/
def isBoundWord (w : String) : Bool :=
  boundWords.contains w || w.startsWith "$((" || w.startsWith "((" || w.startsWith "SECONDS" || w.startsWith "deadline=" || w.startsWith "DEADLINE="

/-- `s` occurs in `w` as a substring.

$$\mathrm{has}(w, s) \iff s \text{ occurs in } w$$
-/
def has (w s : String) : Bool := (w.splitOn s).length > 1

/-- A variable assignment word (`IFS=`, `LC_ALL=C`): it holds `=`, does not start with `-`, and runs no command
substitution (no `$(` and no backquote).

$$\mathrm{isAssign}(w) \iff \mathrm{has}(w, \texttt{=}) \land w \text{ does not start with } \texttt{-} \land \lnot\mathrm{has}(w, \texttt{\$(}) \land \lnot\mathrm{has}(w, \texttt{`})$$
-/
def isAssign (w : String) : Bool := has w "=" && !w.startsWith "-" && !has w "$(" && !has w "`"

/-- A word `read` may take in a read-loop condition: non-empty, only letters, digits, `_` and `-` (an option, an option
argument or a variable name; so no redirect, no expansion, no operator), and not an option word holding `u` (`-u fd`
reads another descriptor).

$$\mathrm{isReadArg}(w) \iff w \ne \varepsilon \land w \in \{\texttt{A-Z}, \texttt{a-z}, \texttt{0-9}, \texttt{\_}, \texttt{-}\}^{*} \land \lnot(w \text{ starts with } \texttt{-} \land \texttt{u} \in w)$$
-/
def isReadArg (w : String) : Bool :=
  w != "" && w.all (fun ch => ch.isAlphanum || ch == '_' || ch == '-') && !(w.startsWith "-" && w.contains 'u')

/-- A read-loop condition: the words of the segment (from its command on) are exactly `while`, optional assignments,
`read`, then only `isReadArg` words (`while IFS= read -r line`). Nothing else may run in the condition.

$$\mathrm{isReadCond}(K) \iff K = \texttt{while} :: r \ \land\ \mathrm{dropWhile}(\mathrm{isAssign}, r) = \texttt{read} :: A \ \land\ \forall x \in A.\ \mathrm{isReadArg}(x)$$
-/
def isReadCond : List String → Bool
  | "while" :: r =>
    match r.dropWhile isAssign with
    | "read" :: args => args.all isReadArg
    | _ => false
  | _ => false

/-- A read-loop head: a segment whose words (from its command on) are a read-loop condition and that ends with `;` or a
newline (`seq`), so no `||`, `&&` or `|` extends the condition. (That the next segment starts with `do` is checked by the
grouping, `addSeg`.)

$$\mathrm{readHead}(s) \iff \mathrm{isReadCond}(\mathrm{key}(s.\mathit{words})) \land s.\mathit{term} = \mathrm{seq}$$
-/
def readHead (s : Seg) : Bool := isReadCond (key s.words) && s.term == .seq

/-- A read-loop condition starts with `while`.

$$\forall K.\ \mathrm{isReadCond}(K) \Rightarrow \mathrm{head}(K) = \texttt{while}$$
-/
theorem isReadCond_head (k : List String) (h : isReadCond k = true) : k.head? = some "while" := by
  match k, h with
  | "while" :: _, _ => rfl
  | [], h => simp [isReadCond] at h
  | x :: r, h =>
    unfold isReadCond at h
    split at h
    · simp_all
    · simp at h

/-- A word a finite producer must not hold: `-` (read stdin), a device other than `/dev/null`, a subshell or a process
or command substitution (a word starting with `(`, or holding `<(`, `$(` or a backquote), or a descriptor duplication
`<&`.

$$\mathrm{badWord}(w) \iff w = \texttt{-} \lor (w \text{ starts with } \texttt{/dev/} \land w \ne \texttt{/dev/null}) \lor w \text{ starts with } \texttt{(} \lor \mathrm{has}(w, \texttt{<(}) \lor \mathrm{has}(w, \texttt{\$(}) \lor \mathrm{has}(w, \texttt{`}) \lor \mathrm{has}(w, \texttt{<\&})$$
-/
def badWord (w : String) : Bool :=
  w == "-" || (w.startsWith "/dev/" && w != "/dev/null") || w.startsWith "(" || has w "<(" || has w "$(" ||
    has w "`" || has w "<&"

/-- The git subcommand: the first word after the global options (`-C dir`, `-c k=v` take a value; other `-...` words
none); `""` if there is none.

$$\mathrm{gitSub}([\,]) = \varepsilon, \quad \mathrm{gitSub}(\texttt{-C} :: x :: r) = \mathrm{gitSub}(\texttt{-c} :: x :: r) = \mathrm{gitSub}(r), \quad \mathrm{gitSub}(w :: r) = \begin{cases} \mathrm{gitSub}(r) & w \text{ starts with } \texttt{-} \\ w & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def gitSub : List String → String
  | "-C" :: _ :: r => gitSub r
  | "-c" :: _ :: r => gitSub r
  | w :: r => if w.startsWith "-" then gitSub r else w
  | [] => ""

/-- The git subcommands that read the repository, print and end (no watch, no pager without a tty, no command run).

$$\mathrm{gitFinite} = [\texttt{ls-files}, \texttt{ls-tree}, \texttt{diff}, \texttt{log}, \texttt{show}, \texttt{status}, \texttt{branch}, \texttt{tag}, \texttt{for-each-ref}, \texttt{rev-list}, \texttt{rev-parse}, \texttt{grep}, \texttt{shortlog}, \texttt{describe}, \texttt{cat-file}, \texttt{blame}, \texttt{merge-base}, \texttt{name-rev}]$$
-/
def gitFinite : List String :=
  ["ls-files", "ls-tree", "diff", "log", "show", "status", "branch", "tag", "for-each-ref", "rev-list", "rev-parse",
   "grep", "shortlog", "describe", "cat-file", "blame", "merge-base", "name-rev"]

/-- Substrings that may make a jq program loop or generate without end.

$$\mathrm{jqLoopWords} = [\texttt{repeat}, \texttt{recurse}, \texttt{until}, \texttt{while}, \texttt{range}, \texttt{def}, \texttt{infinite}]$$
-/
def jqLoopWords : List String := ["repeat", "recurse", "until", "while", "range", "def", "infinite"]

/-- The producer allowlist: sources (their output does not depend on stdin) and filters (they end when their stdin ends).

$$\mathrm{sourceCmds} = [\texttt{git}, \texttt{gh}, \texttt{cat}, \texttt{find}, \texttt{ls}, \texttt{printf}, \texttt{echo}, \texttt{seq}], \quad \mathrm{filterCmds} = [\texttt{grep}, \texttt{rg}, \texttt{jq}, \texttt{sort}, \texttt{head}, \texttt{wc}], \quad \mathrm{producerCmds} = \mathrm{sourceCmds} \mathbin{+\!\!+} \mathrm{filterCmds}$$
-/
def sourceCmds : List String := ["git", "gh", "cat", "find", "ls", "printf", "echo", "seq"]

/-- The filters of the producer allowlist (see `sourceCmds`).

$$\mathrm{filterCmds} = [\texttt{grep}, \texttt{rg}, \texttt{jq}, \texttt{sort}, \texttt{head}, \texttt{wc}]$$
-/
def filterCmds : List String := ["grep", "rg", "jq", "sort", "head", "wc"]

/-- Every command name a finite producer may start with.

$$\mathrm{producerCmds} = \mathrm{sourceCmds} \mathbin{+\!\!+} \mathrm{filterCmds}$$
-/
def producerCmds : List String := sourceCmds ++ filterCmds

/-- Is the output of a segment known to be finite (an allowlist)? $\mathit{inFin}$ says its stdin is finite. Here
$K = \mathrm{key}(W)$. The segment has no bad word and no long shape, and $K$ is one of: `git` with a subcommand in
`gitFinite` and no `--stdin`; `gh run list|view`; `cat` with at least one operand (a word not starting with `-`) and no
option word holding `u`; `find` with no `-exec -execdir -ok -okdir`; `seq` with no word holding `inf` or `nan` (any case);
`ls`, `printf`, `echo`; or, only when $\mathit{inFin}$, `grep`, `head`, `wc`, `jq` with no `jqLoopWords` substring,
`rg` with no `--pre...` word, `sort` with no `--compress...` word. Anything else is not finite.

$$\mathrm{producerOut}_c(\mathit{inFin}, W) \iff (\forall x \in K.\ \lnot\mathrm{badWord}(x)) \land \mathrm{shapesOf}_c(W) = [\,] \land \mathrm{allowed}(\mathit{inFin}, K)$$
$$\mathrm{allowed}(i, K) = \begin{cases} \mathrm{gitSub}(r) \in \mathrm{gitFinite} \land \texttt{-{}-stdin} \notin r & K = \texttt{git} :: r \\ v \in \{\texttt{list}, \texttt{view}\} & K = \texttt{gh} :: \texttt{run} :: v :: r \\ (\exists x \in r.\ x \text{ not starting with } \texttt{-}) \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-} \land \texttt{u} \in x & K = \texttt{cat} :: r \\ r \cap \{\texttt{-exec}, \texttt{-execdir}, \texttt{-ok}, \texttt{-okdir}\} = \emptyset & K = \texttt{find} :: r \\ \lnot\exists x \in r.\ \mathrm{has}(\mathrm{lower}(x), \texttt{inf}) \lor \mathrm{has}(\mathrm{lower}(x), \texttt{nan}) & K = \texttt{seq} :: r \\ \top & K = k :: r,\ k \in \{\texttt{ls}, \texttt{printf}, \texttt{echo}\} \\ i \land \lnot\exists x \in r, j \in \mathrm{jqLoopWords}.\ \mathrm{has}(x, j) & K = \texttt{jq} :: r \\ i \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-{}-pre} & K = \texttt{rg} :: r \\ i \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-{}-compress} & K = \texttt{sort} :: r \\ i & K = k :: r,\ k \in \{\texttt{grep}, \texttt{head}, \texttt{wc}\} \\ \bot & \text{otherwise} \end{cases}$$
-/
def producerOut (c : Caps) (inFin : Bool) (ws : List String) : Bool :=
  let ks := key ws
  !ks.any badWord && (shapesOf c ws).isEmpty &&
  match ks with
  | "git" :: r => gitFinite.contains (gitSub r) && !r.contains "--stdin"
  | "gh" :: "run" :: v :: _ => v == "list" || v == "view"
  | "cat" :: r => r.any (fun x => !x.startsWith "-") && !r.any (fun x => x.startsWith "-" && x.contains 'u')
  | "find" :: r => !r.any (fun x => x == "-exec" || x == "-execdir" || x == "-ok" || x == "-okdir")
  | "seq" :: r => !r.any (fun x => has x.toLower "inf" || has x.toLower "nan")
  | "ls" :: _ => true
  | "printf" :: _ => true
  | "echo" :: _ => true
  | "jq" :: r => inFin && !r.any (fun x => jqLoopWords.any (has x ·))
  | "rg" :: r => inFin && !r.any (·.startsWith "--pre")
  | "sort" :: r => inFin && !r.any (·.startsWith "--compress")
  | "grep" :: _ => inFin
  | "head" :: _ => inFin
  | "wc" :: _ => inFin
  | _ => false

/-- **A producer outside the allowlist is never finite**, whatever its stdin: `ping`, `tail`, `yes`, `log stream`,
`sleep`, a block word, an empty segment.

$$\forall c, i, W.\ \mathrm{head}(\mathrm{key}(W)) \notin \mathrm{producerCmds} \ \Rightarrow\ \lnot\mathrm{producerOut}_c(i, W)$$
where $\mathrm{head}$ of an empty list is the empty word $\varepsilon$ (not in the list).
-/
theorem producer_outside_list (c : Caps) (inFin : Bool) (ws : List String)
    (h : producerCmds.contains ((key ws).head?.getD "") = false) : producerOut c inFin ws = false := by
  unfold producerOut
  generalize key ws = ks at *
  dsimp only
  split <;> simp_all [producerCmds, sourceCmds, filterCmds]

/-- A filter (`grep rg jq sort head wc`) reading an input not known to be finite is not finite (`tail -f x | grep y`).

$$\forall c, W.\ \mathrm{head}(\mathrm{key}(W)) \in \mathrm{filterCmds} \ \Rightarrow\ \lnot\mathrm{producerOut}_c(\bot, W)$$
where $\mathrm{head}$ of an empty list is the empty word $\varepsilon$.
-/
theorem filter_needs_finite_input (c : Caps) (ws : List String)
    (h : filterCmds.contains ((key ws).head?.getD "") = true) : producerOut c false ws = false := by
  unfold producerOut
  generalize key ws = ks at *
  dsimp only
  split <;> simp_all [filterCmds]

/-- A redirect target that is a finite input: non-empty, not a process substitution or subshell (`(...` or `<(...`),
not a descriptor (`&3`) or a read-write `<>`, and not a device other than `/dev/null` (`/dev/zero`, `/dev/stdin` and
ttys may never end).

$$\mathrm{finiteTarget}(t) \iff t \ne \varepsilon \land t \text{ starts with none of } \texttt{(},\ \texttt{<(},\ \texttt{\&},\ \texttt{>} \land (t \text{ does not start with } \texttt{/dev/} \lor t = \texttt{/dev/null})$$
-/
def finiteTarget (t : String) : Bool :=
  t != "" && !t.startsWith "(" && !t.startsWith "<(" && !t.startsWith "&" && !t.startsWith ">" &&
    (!t.startsWith "/dev/" || t == "/dev/null")

/-- The redirect scan state: whether the last stdin redirect seen is finite (`none`: no stdin redirect yet), whether the
previous word was a bare `<` or `0<` (its target comes next), and the words of an open process substitution read so far
with a flag that it is the stdin target (`none` outside one).

$$\mathrm{RAcc} = \mathrm{Option}(\mathbb{B}) \times \mathbb{B} \times \mathrm{Option}(\mathrm{String}^{*} \times \mathbb{B}), \quad \{\} = (\mathrm{none}, \bot, \mathrm{none})$$
-/
structure RAcc where
  last : Option Bool := none
  lt   : Bool := false
  sub  : Option (List String × Bool) := none

/-- A word with its first `n` characters dropped.

$$\mathrm{dropS}(w, n) = \mathrm{str}(\mathrm{drop}(n, \mathrm{chars}(w)))$$
-/
def dropS (w : String) (n : Nat) : String := String.ofList (w.toList.drop n)

/-- The word without a closing `)`, if it ends with one.

$$\mathrm{closeParen}(w) = \begin{cases} \mathrm{some}(v) & w = v\,\texttt{)} \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def closeParen (w : String) : Option String :=
  if w.endsWith ")" then some (String.ofList w.toList.dropLast) else none

/-- The finiteness of a process substitution's command words (empty words dropped): an allowlisted producer whose
stdin is finite (the tool's stdin).

$$\mathrm{subFin}_c(W) = \mathrm{producerOut}_c(\top, [x \in W \mid x \ne \varepsilon])$$
-/
def subFin (c : Caps) (ws : List String) : Bool := producerOut c true (ws.filter (· != ""))

/-- Open a process substitution at the word rest `x` (after `<(`): closed at once if `x` ends with `)`; `st` says it is
the stdin target.

$$\mathrm{openSub}_c(r, x, \mathit{st}) = \begin{cases} r[\mathit{lt} := \bot,\ \mathit{last} := (\mathit{st}\ ?\ \mathrm{some}(\mathrm{subFin}_c([v])) : r.\mathit{last})] & \mathrm{closeParen}(x) = \mathrm{some}(v) \\ r[\mathit{lt} := \bot,\ \mathit{sub} := \mathrm{some}([x], \mathit{st})] & \text{otherwise} \end{cases}$$
-/
def openSub (c : Caps) (r : RAcc) (x : String) (st : Bool) : RAcc :=
  match closeParen x with
  | some v => { r with lt := false, last := if st then some (subFin c [v]) else r.last }
  | none => { r with lt := false, sub := some ([x], st) }

/-- One word of a redirect scan (first matching row). Inside a process substitution words are collected until one ends
with `)`. After a bare `<`/`0<` the word is the target. A word `<<...` is a here-document or here-string (finite);
`<t` or `0<t` a file redirect; a `<(` word not after `<` is an argument, skipped. Other words change nothing.

$$\mathrm{rstep}_c(r, w) = \begin{cases} r[\mathit{sub} := \mathrm{none},\ \mathit{last} := (\mathit{st}\ ?\ \mathrm{some}(\mathrm{subFin}_c(W \mathbin{+\!\!+} [v])) : r.\mathit{last})] & r.\mathit{sub} = \mathrm{some}(W, \mathit{st}),\ \mathrm{closeParen}(w) = \mathrm{some}(v) \\ r[\mathit{sub} := \mathrm{some}(W \mathbin{+\!\!+} [w], \mathit{st})] & r.\mathit{sub} = \mathrm{some}(W, \mathit{st}) \\ \mathrm{openSub}_c(r, \mathrm{dropS}(w, 2), \top) & r.\mathit{lt},\ w \text{ starts with } \texttt{<(} \\ r[\mathit{lt} := \bot,\ \mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(w))] & r.\mathit{lt} \\ r[\mathit{lt} := \top] & w \in \{\texttt{<}, \texttt{0<}\} \\ r[\mathit{last} := \mathrm{some}(\top)] & w \text{ starts with } \texttt{<<} \\ \mathrm{openSub}_c(r, \mathrm{dropS}(w, 2), \bot) & w \text{ starts with } \texttt{<(} \\ r[\mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(\mathrm{dropS}(w, 1)))] & w \text{ starts with } \texttt{<} \\ r[\mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(\mathrm{dropS}(w, 2)))] & w \text{ starts with } \texttt{0<} \\ r & \text{otherwise} \end{cases}$$
-/
def rstep (c : Caps) (r : RAcc) (w : String) : RAcc :=
  match r.sub with
  | some (ws, st) =>
    match closeParen w with
    | some v => { r with sub := none, last := if st then some (subFin c (ws ++ [v])) else r.last }
    | none => { r with sub := some (ws ++ [w], st) }
  | none =>
    if r.lt then
      if w.startsWith "<(" then openSub c r (dropS w 2) true
      else { r with lt := false, last := some (finiteTarget w) }
    else if w == "<" || w == "0<" then { r with lt := true }
    else if w.startsWith "<<" then { r with last := some true }
    else if w.startsWith "<(" then openSub c r (dropS w 2) false
    else if w.startsWith "<" then { r with last := some (finiteTarget (dropS w 1)) }
    else if w.startsWith "0<" then { r with last := some (finiteTarget (dropS w 2)) }
    else r

/-- The stdin redirect of a word list (bash applies the last one): `none` when there is none, else whether it is a finite
input. A process substitution left open makes it `some false`.

$$\mathrm{inRedir}_c(W) = \begin{cases} \mathrm{some}(\bot) & r.\mathit{sub} \ne \mathrm{none} \\ r.\mathit{last} & \text{otherwise} \end{cases}, \quad r = \mathrm{foldl}(\mathrm{rstep}_c, \{\}, W)$$
-/
def inRedir (c : Caps) (ws : List String) : Option Bool :=
  let r := ws.foldl (rstep c) {}
  if r.sub.isSome then some false else r.last

/-- Facts about one unit (the thing a trailing `&` backgrounds).

$$\mathrm{Job} = (\mathit{bg} \in \mathbb{B},\ \mathit{shapes} \in \mathrm{Shape}^{*},\ \mathit{unbounded} \in \mathbb{B})$$
-/
structure Job where
  bg        : Bool
  shapes    : List Shape
  unbounded : Bool
deriving DecidableEq, Repr

/-- The running state of the unit grouping: the open blocks (innermost first; each with two flags: it is a read loop,
and it reads a finite pipe), the shapes so far, whether a loop with no input bound was seen (`free`), a bound word, a
`timeout` wrapper, whether the unit is still empty, the previous segment, whether the previous segment was a read-loop
head (so this one must start with `do`), whether the previous segment's output is known finite, and the finished units.

$$\mathrm{UAcc} = (\mathbb{B} \times \mathbb{B})^{*} \times \mathrm{Shape}^{*} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Seg} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Job}^{*}$$
$$u = (\mathit{stack}, \mathit{shapes}, \mathit{free}, \mathit{bound}, \mathit{wrapped}, \mathit{fresh}, \mathit{last}, \mathit{cond}, \mathit{lastFin}, \mathit{units}), \quad \{\} = ([\,], [\,], \bot, \bot, \bot, \top, ([\,], \mathrm{fin}), \bot, \bot, [\,])$$
-/
structure UAcc where
  stack   : List (Bool × Bool) := []
  shapes  : List Shape := []
  free    : Bool := false
  bound   : Bool := false
  wrapped : Bool := false
  fresh   : Bool := true
  last    : Seg := ⟨[], .fin⟩
  cond    : Bool := false
  lastFin : Bool := false
  units   : List Job := []

/-- Add one segment to the grouping; close the unit when no block is open and the segment ends the list. Here
$K = \mathrm{key}(s.\mathit{words})$, $f$ its head (`""` if none), $\ell \iff f \in \{\texttt{until}, \texttt{while}\}$,
$\rho = \mathrm{readHead}(s)$, $\iota \iff u.\mathit{last}.\mathit{term} \ne \mathrm{pipe} \lor u.\mathit{lastFin}$ (this
segment's stdin is finite: a pipeline head reads the tool's stdin), $\pi \iff u.\mathit{last}.\mathit{term} = \mathrm{pipe}
\land u.\mathit{lastFin}$ (it reads a finite pipe), and $\delta \iff u.\mathit{cond} \land \mathrm{head}(s.\mathit{words})
\ne \texttt{do}$ (a read-loop head not followed by `do`: more commands in the condition).

$$\mathrm{addSeg}_c(u, s) = \begin{cases} \{\}[\mathit{units} := (s.\mathit{term} = \mathrm{bg},\ u'.\mathit{shapes},\ u'.\mathit{free} \land \lnot(u'.\mathit{bound} \lor u'.\mathit{wrapped})) :: u.\mathit{units}] & S = [\,] \land s.\mathit{term} \notin \{\mathrm{join}, \mathrm{pipe}\} \\ u' & \text{otherwise} \end{cases}$$
$$(S, \phi) = \begin{cases} ((\rho, \pi) :: u.\mathit{stack},\ \bot) & f \in \mathrm{openers} \\ (r,\ p_1 \land \lnot\, \mathrm{getD}(\mathrm{inRedir}_c(s.\mathit{words}), p_2)) & f \in \mathrm{closers},\ u.\mathit{stack} = (p_1, p_2) :: r \\ ([\,], \bot) & f \in \mathrm{closers},\ u.\mathit{stack} = [\,] \\ (u.\mathit{stack}, \bot) & \text{otherwise} \end{cases}$$
$$u' = u[\mathit{stack} := S,\ \mathit{shapes} := u.\mathit{shapes} \mathbin{+\!\!+} [\mathrm{loop} \mid \ell] \mathbin{+\!\!+} \mathrm{shapesOf}_c(s.\mathit{words}),\ \mathit{free} := u.\mathit{free} \lor (\ell \land \lnot\rho) \lor \delta \lor \phi,\ \mathit{bound} := u.\mathit{bound} \lor \exists x \in s.\mathit{words}.\ \mathrm{isBoundWord}(x),$$
$$\qquad \mathit{wrapped} := (u.\mathit{fresh}\ ?\ f \in \{\texttt{timeout}, \texttt{gtimeout}\} : u.\mathit{wrapped}),\ \mathit{fresh} := \bot,\ \mathit{last} := s,\ \mathit{cond} := \rho,\ \mathit{lastFin} := \mathrm{producerOut}_c(\iota, s.\mathit{words})]$$
where $\mathrm{getD}(\mathrm{some}(b), d) = b$ and $\mathrm{getD}(\mathrm{none}, d) = d$ (the `done` redirect overrides the pipe).
-/
def addSeg (c : Caps) (u : UAcc) (s : Seg) : UAcc :=
  let f := (key s.words).head?.getD ""
  let isLoop := f == "until" || f == "while"
  let rl := readHead s
  let inFin := u.last.term != .pipe || u.lastFin
  let piped := u.last.term == .pipe && u.lastFin
  let nodo := u.cond && s.words.head? != some "do"
  let (stack, phi) : List (Bool × Bool) × Bool :=
    if openers.contains f then ((rl, piped) :: u.stack, false)
    else if closers.contains f then
      match u.stack with
      | p :: r => (r, p.1 && !(inRedir c s.words).getD p.2)
      | [] => ([], false)
    else (u.stack, false)
  let wrapped := if u.fresh then (f == "timeout" || f == "gtimeout") else u.wrapped
  let sh := (if isLoop then [Shape.loop] else []) ++ shapesOf c s.words
  let u' := { u with stack, shapes := u.shapes ++ sh, free := u.free || (isLoop && !rl) || nodo || phi,
                     bound := u.bound || s.words.any isBoundWord, wrapped, fresh := false, last := s, cond := rl,
                     lastFin := producerOut c inFin s.words }
  if stack.isEmpty && s.term != .join && s.term != .pipe then
    { units := ⟨s.term == .bg, u'.shapes, u'.free && !(u'.bound || u'.wrapped)⟩ :: u.units }
  else u'

/-- The units of a command (a trailing open unit is closed at the end; a read loop still open there, or a read-loop head
with nothing after it, counts as free). Here $u = \mathrm{foldl}(\mathrm{addSeg}_c, \{\}, \mathrm{parse}(\mathit{cmd}))$.

$$\mathrm{units}_c(\mathit{cmd}) = \mathrm{rev}\begin{cases} u.\mathit{units} & u.\mathit{fresh} \\ (\bot,\ u.\mathit{shapes},\ (u.\mathit{free} \lor u.\mathit{cond} \lor \exists p \in u.\mathit{stack}.\ p_1) \land \lnot(u.\mathit{bound} \lor u.\mathit{wrapped})) :: u.\mathit{units} & \text{otherwise} \end{cases}$$
-/
def units (c : Caps) (cmd : String) : List Job :=
  let u := (parse cmd).foldl (addSeg c) {}
  let u := if u.fresh then u
    else { u with units := ⟨false, u.shapes, (u.free || u.cond || u.stack.any (·.1)) && !(u.bound || u.wrapped)⟩ :: u.units }
  u.units.reverse

/-- A `while`/`until` segment that is not a read-loop head (`while true`, `while read l || true`, `while read l < f`,
`until read x`) marks the loop free (unbounded unless a bound word or a `timeout` wrapper is in the unit): its own block
stays open, so the unit does not close here.

$$\forall c, u, s.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \in \{\texttt{while}, \texttt{until}\} \land \lnot \mathrm{readHead}(s) \ \Rightarrow\ \mathrm{addSeg}_c(u, s).\mathit{free}$$
-/
theorem plainLoop_free (c : Caps) (u : UAcc) (s : Seg)
    (hf : (key s.words).head? = some "while" ∨ (key s.words).head? = some "until")
    (hr : readHead s = false) : (addSeg c u s).free = true := by
  have hf' : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = true := by
    rcases hf with h | h <;> simp [h]
  have ho : openers.contains ((key s.words).head?.getD "") = true := by
    rcases hf with h | h <;> simp [h, openers]
  unfold addSeg
  simp only [hf', hr, ho, ite_true]
  simp

/-- A read-loop head followed by a segment that does not start with `do` (`while read l; [ 1 ]; do`: the condition is a
list whose last command decides) marks the loop free, while a block is open and the segment closes none.

$$\forall c, u, s.\ u.\mathit{cond} \land u.\mathit{stack} \ne [\,] \land \mathrm{head}(s.\mathit{words}) \ne \texttt{do} \land \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{closers} \ \Rightarrow\ \mathrm{addSeg}_c(u, s).\mathit{free}$$
-/
theorem cond_without_do_free (c : Caps) (u : UAcc) (s : Seg) (hc : u.cond = true) (hs : u.stack ≠ [])
    (hd : s.words.head? ≠ some "do") (hcl : closers.contains ((key s.words).head?.getD "") = false) :
    (addSeg c u s).free = true := by
  have hn : (u.cond && s.words.head? != some "do") = true := by simp [hc, hd]
  unfold addSeg
  simp only [hcl, hn, Bool.or_true, Bool.true_or]
  split
  · simp
  · obtain ⟨p, r, hpr⟩ := List.exists_cons_of_ne_nil hs
    simp [hpr]

/-- One segment inside an open block whose command is no block opener or closer, read when no read-loop head is pending
or when it starts with `do`, changes neither the open blocks, nor the free flag, nor the finished units, and leaves no
read-loop head pending.

$$\forall c, u, s.\ u.\mathit{stack} \ne [\,] \land f \notin \mathrm{openers} \cup \mathrm{closers} \land (\lnot u.\mathit{cond} \lor \mathrm{head}(s.\mathit{words}) = \texttt{do}) \ \Rightarrow\ v.\mathit{stack} = u.\mathit{stack} \land v.\mathit{free} = u.\mathit{free} \land v.\mathit{units} = u.\mathit{units} \land \lnot v.\mathit{cond}, \quad f = \mathrm{head}(\mathrm{key}(s.\mathit{words})),\ v = \mathrm{addSeg}_c(u, s)$$
-/
theorem addSeg_inner (c : Caps) (u : UAcc) (s : Seg) (hs : u.stack ≠ [])
    (ho : openers.contains ((key s.words).head?.getD "") = false)
    (hc : closers.contains ((key s.words).head?.getD "") = false)
    (hk : u.cond = false ∨ s.words.head? = some "do") :
    (addSeg c u s).stack = u.stack ∧ (addSeg c u s).free = u.free ∧ (addSeg c u s).units = u.units ∧
      (addSeg c u s).cond = false := by
  have hl : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = false := by
    cases h1 : ((key s.words).head?.getD "" == "until") <;> cases h2 : ((key s.words).head?.getD "" == "while") <;>
      simp_all [openers]
  have hr : readHead s = false := by
    cases h : readHead s
    · rfl
    · simp only [readHead, Bool.and_eq_true] at h
      have := isReadCond_head _ h.1
      simp [this, openers] at ho
  have hn : (u.cond && s.words.head? != some "do") = false := by
    rcases hk with h | h <;> simp [h]
  unfold addSeg
  simp only [ho, hc, hl, hr, hn]
  simp [hs]

/-- The body of a block (segments with no block opener or closer), read with no read-loop head pending, changes neither
the open blocks, nor the free flag, nor the finished units, and leaves no read-loop head pending.

$$\forall c, B, u.\ u.\mathit{stack} \ne [\,] \land \lnot u.\mathit{cond} \land (\forall s \in B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \ \Rightarrow\ v.\mathit{stack} = u.\mathit{stack} \land v.\mathit{free} = u.\mathit{free} \land v.\mathit{units} = u.\mathit{units} \land \lnot v.\mathit{cond}, \quad v = \mathrm{foldl}(\mathrm{addSeg}_c, u, B)$$
-/
theorem addSeg_body (c : Caps) (body : List Seg) (u : UAcc) (hs : u.stack ≠ []) (hc : u.cond = false)
    (hb : ∀ s ∈ body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false) :
    (body.foldl (addSeg c) u).stack = u.stack ∧ (body.foldl (addSeg c) u).free = u.free ∧
      (body.foldl (addSeg c) u).units = u.units ∧ (body.foldl (addSeg c) u).cond = false := by
  induction body generalizing u with
  | nil => simp [hc]
  | cons s body ih =>
    have h1 := addSeg_inner c u s hs (hb s (by simp)).1 (hb s (by simp)).2 (Or.inl hc)
    have := ih (addSeg c u s) (h1.1 ▸ hs) h1.2.2.2 (fun x hx => hb x (by simp [hx]))
    simp only [List.foldl_cons]
    exact ⟨this.1.trans h1.1, this.2.1.trans h1.2.1, this.2.2.1.trans h1.2.2.1, this.2.2.2⟩

/-- **Read loops: a fact about the classification.** Take a read-loop head $w$ (`while [assignments] read [args]` ended
by `;` or a newline), then a segment $d_0$ starting with `do`, a body $B$, with no block opener or closer in $d_0 :: B$,
and a `done` segment $d$, read with no free loop and no read-loop head pending. If the loop's stdin is classified finite
(the `done` segment's last stdin redirect is finite, or it has none and the loop reads a pipe whose producer is
classified finite), the grouping still has no free loop and the unit closed by `done` (if any) is bounded.
That such a loop ends in bash is not proved here: it rests on the premises that `read` fails at the end of a finite
input and that the allowlisted producers (`producerOut`) end.

$$\forall c, u, w, d_0, B, d.\ \lnot u.\mathit{free} \land \lnot u.\mathit{cond} \land \mathrm{readHead}(w) \land \mathrm{head}(d_0.\mathit{words}) = \texttt{do} \land (\forall s \in d_0 :: B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \land \mathrm{head}(\mathrm{key}(d.\mathit{words})) = \texttt{done}$$
$$\land\ \big(\mathrm{inRedir}_c(d.\mathit{words}) = \mathrm{some}(\top) \lor (\mathrm{inRedir}_c(d.\mathit{words}) = \mathrm{none} \land u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land u.\mathit{lastFin})\big)$$
$$\Rightarrow\ \lnot v.\mathit{free} \land (v.\mathit{units} = u.\mathit{units} \lor \exists j.\ v.\mathit{units} = j :: u.\mathit{units} \land \lnot j.\mathit{unbounded}), \quad v = \mathrm{foldl}(\mathrm{addSeg}_c, u, w :: d_0 :: B \mathbin{+\!\!+} [d])$$
-/
theorem readLoop_bounded (c : Caps) (u : UAcc) (w d0 d : Seg) (body : List Seg)
    (hu : u.free = false) (hc : u.cond = false) (hw : readHead w = true) (h0 : d0.words.head? = some "do")
    (hb : ∀ s ∈ d0 :: body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false)
    (hd : (key d.words).head? = some "done")
    (hin : inRedir c d.words = some true ∨
      (inRedir c d.words = none ∧ u.last.term = .pipe ∧ u.lastFin = true)) :
    ((w :: d0 :: body ++ [d]).foldl (addSeg c) u).free = false ∧
      (((w :: d0 :: body ++ [d]).foldl (addSeg c) u).units = u.units ∨
        ∃ j, ((w :: d0 :: body ++ [d]).foldl (addSeg c) u).units = j :: u.units ∧ j.unbounded = false) := by
  -- the `while` segment
  have hwh : (key w.words).head? = some "while" := by
    simp only [readHead, Bool.and_eq_true] at hw
    exact isReadCond_head _ hw.1
  let piped := u.last.term == .pipe && u.lastFin
  have hw1 : (addSeg c u w).stack = (true, piped) :: u.stack ∧ (addSeg c u w).free = false ∧
      (addSeg c u w).units = u.units ∧ (addSeg c u w).cond = true := by
    unfold addSeg
    simp only [hwh, hw]
    simp [hu, hc, piped, openers]
  -- the `do` segment and the body
  have hne : (addSeg c u w).stack ≠ [] := by rw [hw1.1]; simp
  have hd0 := addSeg_inner c (addSeg c u w) d0 hne (hb d0 (by simp)).1 (hb d0 (by simp)).2 (Or.inr h0)
  have hne0 : (addSeg c (addSeg c u w) d0).stack ≠ [] := by rw [hd0.1]; exact hne
  have hb1 := addSeg_body c body (addSeg c (addSeg c u w) d0) hne0 hd0.2.2.2 (fun x hx => hb x (by simp [hx]))
  -- the `done` segment
  generalize hv : body.foldl (addSeg c) (addSeg c (addSeg c u w) d0) = v at hb1
  have hvs : v.stack = (true, piped) :: u.stack := hb1.1.trans (hd0.1.trans hw1.1)
  have hvf : v.free = false := hb1.2.1.trans (hd0.2.1.trans hw1.2.1)
  have hvu : v.units = u.units := hb1.2.2.1.trans (hd0.2.2.1.trans hw1.2.2.1)
  have hvc : v.cond = false := hb1.2.2.2
  have hphi : (inRedir c d.words).getD piped = true := by
    rcases hin with h | ⟨h1, h2, h3⟩
    · simp [h]
    · simp [h1, piped, h2, h3]
  have hfold : (w :: d0 :: body ++ [d]).foldl (addSeg c) u = addSeg c v d := by
    simp [List.foldl_append, hv]
  rw [hfold]
  have hk : (key d.words).head?.getD "" = "done" := by simp [hd]
  have hdo' : openers.contains "done" = false := by decide
  have hdc' : closers.contains "done" = true := by decide
  unfold addSeg
  simp only [hk, hdo', hdc', hvs, hvf, hvu, hvc, hphi, Bool.false_eq_true, ite_false, ite_true]
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

$$\forall U, r.\ \mathrm{decide}(U) = \mathrm{deny}(r) \iff \mathrm{check}(U) = \mathrm{some}(r)$$
-/
theorem deny_iff_check (us : List Job) (r : Reason) : decide us = .deny r ↔ check us = some r := by
  unfold decide
  cases h : check us <;> simp

/-! ## Examples -/

#guard hereDelim none true "<<EOF".toList == some ("EOF".toList, false)
#guard hereDelim none true "<<-EOF".toList == some ("EOF".toList, true)
#guard hereDelim (some false) true "PY".toList == some ("PY".toList, false)
#guard hereDelim none false "<<EOF".toList == none
#guard hereDelim none true "<<<".toList == none
#guard hereDelim none true "<<-".toList == none
#guard hereDelim none true "<<".toList == none
#guard leadOpen none && leadOpen (some 2) && !leadOpen (some 0) && !leadOpen (some 1)
#guard opWord true "<<".toList == some false && opWord true "<<-".toList == some true && opWord false "<<".toList == none
#guard has "a<(b" "<(" && !has "a<b" "<(" && has "x$(y" "$("
#guard isReadArg "-r" && isReadArg "line" && isReadArg "1" && !isReadArg "-u" && !isReadArg "-ru" && !isReadArg "<f"
#guard !isReadArg "" && !isReadArg "$x"
#guard isReadCond ["while", "IFS=", "read", "-r", "line"]
#guard !isReadCond ["while", "true"] && !isReadCond ["until", "read", "x"]
#guard !isReadCond ["while", "read", "l", "<", "f"] && !isReadCond ["while", "read", "-u", "3", "l"]
#guard !isReadCond ["while", "X=$(yes)", "read", "l"]
#guard readHead ⟨["while", "read", "l"], .seq⟩ && !readHead ⟨["while", "read", "l"], .join⟩
#guard !readHead ⟨["while", "read", "l"], .pipe⟩
#guard gitSub ["-C", "x", "log"] == "log" && gitSub ["--no-pager", "diff"] == "diff" && gitSub [] == ""
#guard producerOut {} true ["git", "ls-files"] && producerOut {} true ["git", "-C", "d", "diff", "--name-only"]
#guard !producerOut {} true ["git", "bisect", "run", "x"] && !producerOut {} true ["git", "hash-object", "--stdin"]
#guard producerOut {} true ["find", ".", "-name", "*.lean"] && !producerOut {} true ["find", ".", "-exec", "tail", "-f", "{}", ";"]
#guard producerOut {} true ["ls"] && producerOut {} true ["printf", "%s\\n", "a"] && producerOut {} true ["echo", "x"]
#guard producerOut {} true ["seq", "1", "5"] && !producerOut {} true ["seq", "inf"] && !producerOut {} true ["seq", "1", "INF"]
#guard producerOut {} true ["gh", "run", "list"] && producerOut {} true ["gh", "run", "view", "1"]
#guard !producerOut {} true ["gh", "run", "watch", "1"]
#guard producerOut {} true ["cat", "f.txt"] && !producerOut {} true ["cat"] && !producerOut {} true ["cat", "-"]
#guard !producerOut {} true ["cat", "-u", "f"] && !producerOut {} true ["cat", "/dev/urandom"]
#guard producerOut {} true ["cat", "/dev/null"]
#guard producerOut {} true ["grep", "-rl", "x", "."] && !producerOut {} false ["grep", "x"]
#guard producerOut {} true ["jq", "-r", ".a[]", "f.json"] && !producerOut {} true ["jq", "-n", "repeat(1)"]
#guard !producerOut {} true ["rg", "--pre", "x", "y"] && !producerOut {} true ["sort", "--compress-program=x"]
#guard producerOut {} true ["sort", "f"] && producerOut {} true ["head", "-5", "f"] && producerOut {} true ["wc", "-l", "f"]
#guard !producerOut {} true ["ping", "x"] && !producerOut {} true ["tail", "-fn", "10", "log"]
#guard !producerOut {} true ["tail", "--follow=name", "log"] && !producerOut {} true ["tail", "-n", "5", "f"]
#guard !producerOut {} true ["log", "stream"] && !producerOut {} true ["sleep", "infinity"] && !producerOut {} true ["yes"]
#guard !producerOut {} true ["done"] && !producerOut {} true [] && !producerOut {} true ["echo", "$(yes)"]
#guard inRedir {} ["done", "<", "f.txt"] == some true && inRedir {} ["done", "<f"] == some true
#guard inRedir {} ["done", "<<<", "$x"] == some true && inRedir {} ["done", "<<EOF"] == some true
#guard inRedir {} ["done", "<", "/dev/null"] == some true && inRedir {} ["done"] == none
#guard inRedir {} ["done", "<", "<(tail", "-f", "x)"] == some false && inRedir {} ["done", "<", "/dev/zero"] == some false
#guard inRedir {} ["done", "<", "<(git", "diff", "--name-only", "main)"] == some true
#guard inRedir {} ["done", "<", "<(ls)"] == some true && inRedir {} ["done", "<", "<(ping", "x)"] == some false
#guard inRedir {} ["done", "<", "f", "<", "/dev/zero"] == some false && inRedir {} ["done", "<", "/dev/zero", "<", "f"] == some true
#guard inRedir {} ["done", "<&3"] == some false && inRedir {} ["done", "0<f"] == some true && inRedir {} ["done", "<", "<(ls"] == some false
#guard inRedir {} ["done", "<", "<(cat", "<(tail", "-f", "x))"] == some false
#guard (parse "a | b || c").map (·.term) == [.pipe, .join, .fin]
#guard parse "cat <<'EOF' > f\nwhile true; do x; done\nEOF\necho ok" == [⟨["cat", "<<EOF", ">", "f"], .seq⟩, ⟨["echo", "ok"], .fin⟩]
#guard parse "cat << 'EOF'\nwhile true\nEOF\necho ok" == [⟨["cat", "<<", "EOF"], .seq⟩, ⟨["echo", "ok"], .fin⟩]
#guard (parse "echo \"<<EOF\"\nuntil false; do sleep 5; done").length == 4
#guard (parse "echo '<<EOF'\nx").length == 2 && (parse "echo \\<<EOF\nx").length == 2 && (parse "echo \"<<\" EOF\nx").length == 2
#guard decideCmd {} "while IFS= read -r l; do echo \"$l\"; done < f.txt" == .allow
#guard decideCmd {} "while read l\ndo\n  echo $l\ndone < f.txt" == .allow
#guard decideCmd {} "git ls-files | while read -r f; do echo $f; done | sort" == .allow
#guard decideCmd {} "git ls-files | grep x | while read -r f; do echo $f; done" == .allow
#guard decideCmd {} "while read -r a; do echo $a; done <<< \"$x\"" == .allow
#guard decideCmd {} "while read -r f; do echo $f; done < <(git diff --name-only main)" == .allow
#guard decideCmd {} "cat > f.py <<'EOF'\nwhile True:\n  pass\nEOF\npython3 f.py" == .allow
#guard decideCmd {} "cat <<-EOF > x\n\twhile true; do sleep 1; done\n\tEOF\necho ok" == .allow
#guard decideCmd {} "find . -type f | while read f; do while read l; do echo $l; done < \"$f\"; done" == .allow
#guard decideCmd {} "while read l || true; do sleep 1; done < f" == .deny .unboundedLoop
#guard decideCmd {} "while read l || :; do sleep 1; done < f" == .deny .unboundedLoop
#guard decideCmd {} "while read l; [ 1 ]; do sleep 1; done < f" == .deny .unboundedLoop
#guard decideCmd {} "while read l && true; do sleep 1; done < f" == .deny .unboundedLoop
#guard decideCmd {} "while read -u 3 l; do sleep 1; done < f" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "tail -f log | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "tail -f log | grep x | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "ping x | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "tail -fn 10 log | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "tail --follow=name log | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "cat /dev/urandom | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "cat - | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "cat -u f | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "log stream | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "sleep infinity | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "yes | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "seq inf | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "ls | while read l; do echo $l; done < /dev/zero" == .deny .unboundedLoop
#guard decideCmd {} "while read l < f; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "while read l < f; do echo $l; done < g" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done < <(tail -f x)" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done < <(ping x)" == .deny .unboundedLoop
#guard decideCmd {} "echo \"<<EOF\"\nuntil false; do sleep 5; done" == .deny .unboundedLoop
#guard decideCmd {} "echo '<<EOF'\nuntil false; do sleep 5; done" == .deny .unboundedLoop
#guard decideCmd {} "for f in a b; do while true; do sleep 1; done; done" == .deny .unboundedLoop
#guard decideCmd {} "cat <<EOF > f\nx\nEOF\nwhile true; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ \"$(gh run view 1 --json status -q .status)\" = completed ]; do sleep 150; done" == .deny .unboundedLoop
#guard decideCmd {} "ls | while read f; do echo $f; done &" == .deny (.bgLong .loop)
#guard decideCmd {} "cat <<EOF > f\nhi\nEOF\npnpm fw watch &" == .deny (.bgLong .fwWatch)
#guard decideCmd {} "node server.mjs & pid=$!; sleep 1; curl -s localhost:3000; kill $pid" == .deny (.bgLong .server)
#guard decideCmd {} "a || b &" == .allow

end Fw.Ops.Wait
