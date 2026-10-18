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
`until`/`while` loop with no bound (`unboundedLoop`). The bound is read from the loop **condition only** (the words from
`while`/`until` up to `do`; the body cannot bound or unbound a loop, `body_irrelevant`): an and-or list combined by
bash's exit rule (`comb`) in which a test of the allowlist grammar B (`atomParse`, `relOk`) decides the exit: a plain
variable (`$v`, `${v}`, `"$v"`, or a bare name in `(( ))`) ordered against a decimal literal (`[ $i -lt 10 ]`,
`[[ $SECONDS -ge 600 ]]`, `(( i < 10 ))`), never a special variable, and a clock only in the exit direction
(`grammar_only`, `subst_never_bound`, `seconds_direction`). Everything else (command substitution, `$((..))`,
`${v:-..}`, a limit held in a variable, string tests, `!`, polls) is unbounded. Or a read loop `while read [opts] [names]; do ... done` over a finite input: a file, a here-document,
a here-string with no command substitution or a finite one, or an allowlisted finite producer piped in or given as
`< <(...)`. A condition that runs `read` on an input not known finite is unbounded whatever else it tests
(`readLoop_input_free`). `timeout N` bounds what it wraps (`timeout 600 bash -c '...'`, a producer `timeout 60 tail -f`).

The read-loop rule is a fact about this classification (`readLoop_bounded`), not about bash: that such a loop ends
rests on the premises that `read` fails at the end of a finite input and that the allowlisted producers
(`producerOut`) end; the stdin of a pipeline head is the Bash tool's stdin, `/dev/null` (MEASURED 2026-10-18: fd 0 is
the character device `/dev/null`, `timeout 5 cat` exits 0 at once). The guard targets agent mistakes, not an adversary,
and fails closed outside B. The counter rule assumes the counter moves towards its limit (`while [ $i -lt 5 ]` with no
increment is allowed); a `break` in the body is not a bound.

The shapes are a small documented set, tested by goldens; the parse is approximate on purpose.
Known blind spots (shadow-logged, not claimed): code inside `$( )`, `( )`, `{ }` groups, function bodies or
`sh -c '...'` strings, aliases, `for ((;;))`, variables naming a device or a FIFO (`< "$f"`), a FIFO or `/proc` file
named by a plain path (`cat fifo`, `cat /proc/kmsg`), a command substitution in
an unquoted here-document body, and a here-document operator glued to a word or inside arithmetic (`cat<<EOF`,
`$((1 << 2))`), a single-quoted `'$i'` read as a variable, an unset or non-numeric counter, `eval` strings.
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

/-- How a segment ends: `;` or newline (`seq`), `&&` (`andIf`) or `||` (`orElse`) (the same and-or list goes on), `|` (`pipe`: the
same pipeline goes on, this segment's output is the next one's input), `&` (`bg`), or the end of the text (`fin`).

$$\mathrm{Term} = \mathrm{seq} \mid \mathrm{andIf} \mid \mathrm{orElse} \mid \mathrm{pipe} \mid \mathrm{bg} \mid \mathrm{fin}$$
-/
inductive Term where
  | seq | andIf | orElse | pipe | bg | fin
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

$$\mathrm{unpipe}(a) = \begin{cases} a[\mathit{segs} := (s.\mathit{words}, \mathrm{orElse}) :: r] & a.\mathit{segs} = s :: r \\ a & a.\mathit{segs} = [\,] \end{cases}$$
-/
def unpipe (a : Acc) : Acc :=
  match a.segs with
  | s :: r => { a with segs := { s with term := .orElse } :: r }
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

/-- Process one character that is not a pending `&` resolver (the first matching row applies; ⏎ is newline). A
backslash-newline outside single quotes is removed, as in bash (`whi\⏎le` is `while`).

$$\mathrm{stepPlain}(a, c) = \begin{cases} \mathrm{newline}(a[\mathit{comment} := \bot]) & a.\mathit{comment},\ c = \text{⏎} \\ a & a.\mathit{comment},\ c \ne \text{⏎} \\ a[\mathit{esc} := \bot] & a.\mathit{esc},\ c = \text{⏎} \\ \mathrm{push}(a[\mathit{esc} := \bot], c) & a.\mathit{esc} \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 1,\ c = \texttt{'} \\ \mathrm{push}(a, c) & a.\mathit{quote} = 1 \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 2,\ c = \texttt{"} \\ a[\mathit{esc} := \top] & a.\mathit{quote} = 2,\ c = \backslash \\ \mathrm{push}(a, c) & a.\mathit{quote} = 2 \\ \mathrm{mark}(a)[\mathit{quote} := 1] & c = \texttt{'} \\ \mathrm{mark}(a)[\mathit{quote} := 2] & c = \texttt{"} \\ \mathrm{mark}(a)[\mathit{esc} := \top] & c = \backslash \\ \mathrm{flushWord}(a) & c \in \{\text{space}, \text{tab}, \text{CR}\} \\ \mathrm{newline}(a) & c = \text{⏎} \\ \mathrm{endSeg}(a, \mathrm{seq}) & c = \texttt{;} \\ \mathrm{unpipe}(a) & c = \texttt{|},\ a.\mathit{prev} = \texttt{|} \\ \mathrm{endSeg}(a, \mathrm{pipe}) & c = \texttt{|} \\ a[\mathit{comment} := \top] & c = \texttt{\#},\ a.\mathit{word} = [\,] \\ \mathrm{push}(a, c) & c = \texttt{\&},\ a.\mathit{prev} \in \{\texttt{>}, \texttt{<}\} \\ a[\mathit{pend} := \top] & c = \texttt{\&} \\ \mathrm{push}(a, c) & \text{otherwise} \end{cases}$$
-/
def stepPlain (a : Acc) (c : Char) : Acc :=
  if a.comment then
    if c == '\n' then newline { a with comment := false } else a
  else if a.esc then
    if c == '\n' then { a with esc := false } else push { a with esc := false } c
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
resolved by the next character (`&&` is an `andIf`, `&>` stays in the word, anything else makes the `&` a background
operator), then the character is processed.

$$\mathrm{step}(a, c) = b[\mathit{prev} := c], \quad b = \begin{cases} \mathrm{bodyStep}(a, c) & a.\mathit{body} \\ \mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{andIf}) & a.\mathit{pend},\ c = \texttt{\&} \\ \mathrm{stepPlain}(\mathrm{push}(a[\mathit{pend} := \bot], \texttt{\&}), c) & a.\mathit{pend},\ c = \texttt{>} \\ \mathrm{stepPlain}(\mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{bg}), c) & a.\mathit{pend},\ c \notin \{\texttt{\&}, \texttt{>}\} \\ \mathrm{stepPlain}(a, c) & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def step (a : Acc) (c : Char) : Acc :=
  if a.body then { bodyStep a c with prev := c }
  else
  let a' :=
    if a.pend then
      if c == '&' then (endSeg { a with pend := false } .andIf, true)
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

/-- `s` occurs in `w` as a substring.

$$\mathrm{has}(w, s) \iff s \text{ occurs in } w$$
-/
def has (w s : String) : Bool := (w.splitOn s).length > 1

/-- A character of a variable name: an ASCII letter, a digit or `_`.

$$\mathrm{nameChar}(c) \iff c \in \{\texttt{A-Z}, \texttt{a-z}, \texttt{0-9}, \texttt{\_}\}$$
-/
def nameChar (c : Char) : Bool := c.isAlphanum || c == '_'

/-- A variable name: non-empty, a letter or `_` first, then only `nameChar`s. So no special or positional parameter
(`$`, `#`, `?`, `!`, `@`, `*`, `-`, a digit).

$$\mathrm{isName}([\,]) = \bot, \qquad \mathrm{isName}(c :: r) \iff c \in \{\texttt{A-Z}, \texttt{a-z}, \texttt{\_}\} \land \forall x \in r.\ \mathrm{nameChar}(x)$$
-/
def isName : List Char → Bool
  | c :: r => (c.isAlpha || c == '_') && r.all nameChar
  | [] => false

/-- A decimal literal: one or more digits, with no leading `0` unless it is exactly `0` (so no octal `010`, no hex
`0x1`, no sign).

$$\mathrm{isDec}(l) \iff l \ne [\,] \land (\forall x \in l.\ x \in \texttt{0-9}) \land (\mathrm{head}(l) = \texttt{0} \Rightarrow l = [\texttt{0}])$$
-/
def isDec (l : List Char) : Bool :=
  !l.isEmpty && l.all Char.isDigit && (l.head? != some '0' || l == ['0'])

/-- An operand of a bound test: a variable (by name) or a decimal number.

$$\mathrm{Opd} = \mathrm{var}(n) \mid \mathrm{num}(k), \qquad n \in \mathrm{String},\ k \in \mathbb{N}$$
-/
inductive Opd where
  | var (n : String)
  | num (k : Nat)
deriving DecidableEq, Repr

/-- A character an operand word may hold: a `nameChar`, `$`, `{` or `}`.

$$\mathrm{opdChar}(c) \iff \mathrm{nameChar}(c) \lor c \in \{\texttt{\$}, \texttt{\{}, \texttt{\}}\}$$
-/
def opdChar (c : Char) : Bool := nameChar c || c == '$' || c == '{' || c == '}'

/-- Read an operand word (quotes already removed, so `"$i"` is `$i`). $b$: the word is inside `(( ))`, where a bare name
is a variable. Every character must be an `opdChar`; then `${n}` or `$n` with `isName(n)` is the variable $n$, a decimal
literal is a number, and when $b$ a name alone is a variable. Anything else is not an operand: `$$`, `$#`, `$?`, `$1`,
`$(..)`, `$((..))`, `${x:-0}`, a backquote, `0x1`, `010`, `-1`.

$$\mathrm{opd}_b(w) = \begin{cases} \mathrm{none} & \exists x \in w.\ \lnot\mathrm{opdChar}(x) \\ \mathrm{some}(\mathrm{var}(n)) & w = \texttt{\$\{}\,n\,\texttt{\}} \land \mathrm{isName}(n) \\ \mathrm{some}(\mathrm{var}(n)) & w = \texttt{\$}\,n \land \mathrm{isName}(n) \\ \mathrm{some}(\mathrm{num}(k)) & w \text{ does not start with } \texttt{\$} \land \mathrm{isDec}(w),\ k \text{ the decimal value of } w \\ \mathrm{some}(\mathrm{var}(w)) & w \text{ does not start with } \texttt{\$} \land b \land \mathrm{isName}(w) \\ \mathrm{none} & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def opd (bare : Bool) (w : String) : Option Opd :=
  if w.toList.all opdChar then
    match w.toList with
    | '$' :: '{' :: r =>
      if r.getLast? == some '}' && isName r.dropLast then some (.var (String.ofList r.dropLast)) else none
    | '$' :: r => if isName r then some (.var (String.ofList r)) else none
    | l =>
      if isDec l then some (.num (w.toNat?.getD 0))
      else if bare && isName l then some (.var w) else none
  else none

/-- An ordering relation of a bound test (`<`, `≤`, `>`, `≥`).

$$\mathrm{Rel} = \mathrm{lt} \mid \mathrm{le} \mid \mathrm{gt} \mid \mathrm{ge}$$
-/
inductive Rel where
  | lt | le | gt | ge
deriving DecidableEq, Repr

/-- The relation word: inside `(( ))` ($a$) one of `<`, `<=`, `>`, `>=`; in `[ ]` and `[[ ]]` one of `-lt`, `-le`,
`-gt`, `-ge` (there `<` is a redirect in `[` and a string order in `[[`, and `-eq`/`-ne` can be jumped over).

$$\mathrm{relOf}_a(w) = \begin{cases} \mathrm{some}(\mathrm{lt}) & (a \land w = \texttt{<}) \lor (\lnot a \land w = \texttt{-lt}) \\ \mathrm{some}(\mathrm{le}) & (a \land w = \texttt{<=}) \lor (\lnot a \land w = \texttt{-le}) \\ \mathrm{some}(\mathrm{gt}) & (a \land w = \texttt{>}) \lor (\lnot a \land w = \texttt{-gt}) \\ \mathrm{some}(\mathrm{ge}) & (a \land w = \texttt{>=}) \lor (\lnot a \land w = \texttt{-ge}) \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def relOf (arith : Bool) (w : String) : Option Rel :=
  if arith then
    if w == "<" then some .lt else if w == "<=" then some .le
    else if w == ">" then some .gt else if w == ">=" then some .ge else none
  else
    if w == "-lt" then some .lt else if w == "-le" then some .le
    else if w == "-gt" then some .gt else if w == "-ge" then some .ge else none

/-- The relation seen from the other side: $a\ r\ b \iff b\ \mathrm{flip}(r)\ a$.

$$\mathrm{flip}(\mathrm{lt}) = \mathrm{gt}, \quad \mathrm{flip}(\mathrm{le}) = \mathrm{ge}, \quad \mathrm{flip}(\mathrm{gt}) = \mathrm{lt}, \quad \mathrm{flip}(\mathrm{ge}) = \mathrm{le}$$
-/
def Rel.flip : Rel → Rel
  | .lt => .gt | .le => .ge | .gt => .lt | .ge => .le

/-- A test $v\ r\ N$ that a growing $v$ eventually makes false (and keeps false): $r$ is `<` or `≤`.

$$\mathrm{down}(r) \iff r \in \{\mathrm{lt}, \mathrm{le}\}$$
-/
def Rel.down : Rel → Bool
  | .lt => true | .le => true | _ => false

/-- Variables that are never a bound: bash sets them itself and they do not move towards a limit (random, or fixed
for the loop).

$$\mathrm{noBoundVars} = [\texttt{RANDOM}, \texttt{SRANDOM}, \texttt{LINENO}, \texttt{BASHPID}, \texttt{PPID}, \texttt{UID}, \texttt{EUID}, \texttt{HISTCMD}, \texttt{EPOCHREALTIME}, \texttt{BASH\_SUBSHELL}, \texttt{SHLVL}]$$
-/
def noBoundVars : List String :=
  ["RANDOM", "SRANDOM", "LINENO", "BASHPID", "PPID", "UID", "EUID", "HISTCMD", "EPOCHREALTIME", "BASH_SUBSHELL", "SHLVL"]

/-- The clocks: variables bash moves up by itself, so their direction is known.

$$\mathrm{clocks} = [\texttt{SECONDS}, \texttt{EPOCHSECONDS}]$$
-/
def clocks : List String := ["SECONDS", "EPOCHSECONDS"]

/-- The variable side of a bound test $n\ r\ N$ in a loop ($u$: an `until` loop): $n$ is not in `noBoundVars`, and a
clock must move towards the exit: a `while` loop exits when the test fails, so it needs `<`/`≤`; an `until` loop exits
when it holds, so it needs `>`/`≥`. Any other variable is a counter assumed to move towards its limit (a heuristic).

$$\mathrm{varOk}(u, n, r) \iff n \notin \mathrm{noBoundVars} \land (n \in \mathrm{clocks} \Rightarrow (\mathrm{down}(r) \iff \lnot u))$$
-/
def varOk (untl : Bool) (n : String) (r : Rel) : Bool :=
  !noBoundVars.contains n && (!clocks.contains n || (if untl then !r.down else r.down))

/-- A parsed test $x\ r\ y$ is a bound: one side a variable that passes `varOk`, the other a number (two numbers or two
variables are not).

$$\mathrm{relOk}(u, x, r, y) = \begin{cases} \mathrm{varOk}(u, n, r) & x = \mathrm{var}(n),\ y = \mathrm{num}(k) \\ \mathrm{varOk}(u, n, \mathrm{flip}(r)) & x = \mathrm{num}(k),\ y = \mathrm{var}(n) \\ \bot & \text{otherwise} \end{cases}$$
-/
def relOk (untl : Bool) : Opd → Rel → Opd → Bool
  | .var n, r, .num _ => varOk untl n r
  | .num _, r, .var n => varOk untl n r.flip
  | _, _, _ => false

/-- Parse three words as operand, relation, operand ($a$: inside `(( ))`).

$$\mathrm{tri}_a(x, o, y) = \begin{cases} \mathrm{some}(p, r, q) & \mathrm{opd}_a(x) = \mathrm{some}(p) \land \mathrm{relOf}_a(o) = \mathrm{some}(r) \land \mathrm{opd}_a(y) = \mathrm{some}(q) \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def tri (arith : Bool) (x o y : String) : Option (Opd × Rel × Opd) :=
  match opd arith x, relOf arith o, opd arith y with
  | some p, some r, some q => some (p, r, q)
  | _, _, _ => none

/-- A character an arithmetic bound test may hold: a `nameChar`, `<`, `>`, `=`, a space, `(` or `)`. No `$`, backquote,
comma, `?`, `:`, `|`, `&`, `+`, `-`, `!` or tab.

$$\mathrm{arithChar}(c) \iff \mathrm{nameChar}(c) \lor c \in \{\texttt{<}, \texttt{>}, \texttt{=}, \text{space}, \texttt{(}, \texttt{)}\}$$
-/
def arithChar (c : Char) : Bool := nameChar c || c == '<' || c == '>' || c == '=' || c == ' ' || c == '(' || c == ')'

/-- The token class of a character inside `(( ))`: 1 a `nameChar`, 2 one of `<>=`, 0 a space, 3 anything else.

$$\mathrm{cls}(c) = \begin{cases} 1 & \mathrm{nameChar}(c) \\ 2 & c \in \{\texttt{<}, \texttt{>}, \texttt{=}\} \\ 0 & c = \text{space} \\ 3 & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def cls (c : Char) : Nat :=
  if nameChar c then 1 else if c == '<' || c == '>' || c == '=' then 2 else if c == ' ' then 0 else 3

/-- One character of the arithmetic tokenizer. The state is the finished tokens (reversed), the current token
(reversed) and its class; a class-3 character fails, a space ends the current token, a character of the current class
extends it, any other starts a new token.

$$\mathrm{tokStep}(\mathrm{none}, c) = \mathrm{none}, \qquad \mathrm{tokStep}(\mathrm{some}(T, w, k), c) = \begin{cases} \mathrm{none} & \mathrm{cls}(c) = 3 \\ \mathrm{some}(T', [\,], 0) & \mathrm{cls}(c) = 0 \\ \mathrm{some}(T, c :: w, k) & \mathrm{cls}(c) = k \\ \mathrm{some}(T', [c], \mathrm{cls}(c)) & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
where $T' = T$ if $w = [\,]$, else $\mathrm{rev}(w) :: T$.
-/
def tokStep : Option (List String × List Char × Nat) → Char → Option (List String × List Char × Nat)
  | none, _ => none
  | some (ts, cur, k), c =>
    let k' := cls c
    let ts' := if cur.isEmpty then ts else String.ofList cur.reverse :: ts
    if k' == 3 then none
    else if k' == 0 then some (ts', [], 0)
    else if k' == k then some (ts, c :: cur, k)
    else some (ts', [c], k')

/-- Split the text inside `(( ))` into tokens: maximal runs of name characters and of `<>=`, split at spaces; none if
any other character occurs (`i<10` gives `i`, `<`, `10`; `i < 1 0` gives four tokens).

$$\mathrm{arithToks}(l) = \begin{cases} \mathrm{some}(\mathrm{rev}(T')) & \mathrm{foldl}(\mathrm{tokStep}, \mathrm{some}([\,], [\,], 0), l) = \mathrm{some}(T, w, k) \\ \mathrm{none} & \text{otherwise} \end{cases}$$
where $T' = T$ if $w = [\,]$, else $\mathrm{rev}(w) :: T$.
-/
def arithToks (l : List Char) : Option (List String) :=
  match l.foldl tokStep (some ([], [], 0)) with
  | some (ts, cur, _) => some (if cur.isEmpty then ts else String.ofList cur.reverse :: ts).reverse
  | none => none

/-- An arithmetic test `(( x OP y ))` (glued or spaced): every character of every word is an `arithChar`, the words
joined by single spaces are `((` + $m$ + `))`, and $m$ is exactly three tokens $x, o, y$ that `tri` reads (bare names
allowed).

$$\mathrm{arithParse}(W) = \begin{cases} \mathrm{tri}_\top(x, o, y) & (\forall w \in W.\ \forall c \in w.\ \mathrm{arithChar}(c)) \land \mathrm{join}_{\texttt{" "}}(W) = \texttt{((}\,m\,\texttt{))} \land \mathrm{arithToks}(m) = \mathrm{some}([x, o, y]) \\ \mathrm{none} & \text{otherwise} \end{cases}$$
-/
def arithParse (ws : List String) : Option (Opd × Rel × Opd) :=
  if ws.all (·.toList.all arithChar) then
    match (String.intercalate " " ws).toList with
    | '(' :: '(' :: r =>
      if r.reverse.take 2 == [')', ')'] then
        match arithToks r.dropLast.dropLast with
        | some [x, o, y] => tri true x o y
        | _ => none
      else none
    | _ => none
  else none

/-- **The bound grammar B.** A condition element (its words, quotes removed) parses as a bound test: exactly
`[ x OP y ]` or `[[ x OP y ]]` (five words, `-lt -le -gt -ge`, operands `$v`, `${v}` or a decimal), else an arithmetic
`(( x OP y ))` (`arithParse`). A leading `!`, `test`, `-o`/`-a`, extra words or a redirect all fall outside.

$$\mathrm{atomParse}(W) = \begin{cases} \mathrm{tri}_\bot(x, o, y) & W = [l, x, o, y, r] \land ((l, r) = (\texttt{[}, \texttt{]}) \lor (l, r) = (\texttt{[[}, \texttt{]]})) \\ \mathrm{arithParse}(W) & \text{otherwise} \end{cases}$$
-/
def atomParse (ws : List String) : Option (Opd × Rel × Opd) :=
  match ws with
  | [l, x, o, y, r] =>
    if (l == "[" && r == "]") || (l == "[[" && r == "]]") then tri false x o y else arithParse ws
  | _ => arithParse ws

/-- One element of a loop condition is a **bound test** in a `while` ($u = \bot$) or `until` ($u = \top$) loop: it
parses in the grammar (`atomParse`) and the parsed test passes `relOk`. Anything else (`true`, `date`, `[ 1 -lt 2 ]`,
`[ "$(ls | wc -l)" -gt 0 ]`, `[ $i -lt $n ]`) is not.

$$\mathrm{boundAtom}(u, W) = \begin{cases} \mathrm{relOk}(u, x, r, y) & \mathrm{atomParse}(W) = \mathrm{some}(x, r, y) \\ \bot & \mathrm{atomParse}(W) = \mathrm{none} \end{cases}$$
-/
def boundAtom (untl : Bool) (ws : List String) : Bool :=
  match atomParse ws with
  | some (x, r, y) => relOk untl x r y
  | none => false

/-- **boundAtom is membership in B.** An element is a bound test exactly when it parses in the grammar and the parsed
test passes `relOk`.

$$\forall u, W.\ \mathrm{boundAtom}(u, W) \iff \exists x, r, y.\ \mathrm{atomParse}(W) = \mathrm{some}(x, r, y) \land \mathrm{relOk}(u, x, r, y)$$
-/
theorem boundAtom_iff (u : Bool) (ws : List String) :
    boundAtom u ws = true ↔ ∃ x r y, atomParse ws = some (x, r, y) ∧ relOk u x r y = true := by
  unfold boundAtom
  split
  · rename_i x r y h
    constructor
    · intro hr; exact ⟨x, r, y, h, hr⟩
    · rintro ⟨x', r', y', h', hr'⟩
      rw [h] at h'
      cases h'
      exact hr'
  · rename_i h
    simp [h]

/-- The variable of a passing `varOk` is not in `noBoundVars`.

$$\forall u, n, r.\ \mathrm{varOk}(u, n, r) \Rightarrow n \notin \mathrm{noBoundVars}$$
-/
theorem varOk_noBound (u : Bool) (n : String) (r : Rel) (h : varOk u n r = true) :
    noBoundVars.contains n = false := by
  unfold varOk at h
  revert h
  cases noBoundVars.contains n <;> simp

/-- A clock passes `varOk` only in the exit direction: `<`/`≤` for `while`, `>`/`≥` for `until`.

$$\forall u, n, r.\ n \in \mathrm{clocks} \land \mathrm{varOk}(u, n, r) \Rightarrow (\mathrm{down}(r) \iff \lnot u)$$
-/
theorem varOk_clock (u : Bool) (n : String) (r : Rel) (hc : clocks.contains n = true) (h : varOk u n r = true) :
    r.down = !u := by
  unfold varOk at h
  rw [hc] at h
  revert h
  cases noBoundVars.contains n <;> cases u <;> cases r <;> simp [Rel.down]

/-- A bound test has one variable side and one number side, and its variable is not in `noBoundVars`.

$$\forall u, x, r, y.\ \mathrm{relOk}(u, x, r, y) \Rightarrow \exists n, k.\ n \notin \mathrm{noBoundVars} \land ((x = \mathrm{var}(n) \land y = \mathrm{num}(k)) \lor (x = \mathrm{num}(k) \land y = \mathrm{var}(n)))$$
-/
theorem relOk_shape (u : Bool) (x : Opd) (r : Rel) (y : Opd) (h : relOk u x r y = true) :
    ∃ n k, noBoundVars.contains n = false ∧ ((x = .var n ∧ y = .num k) ∨ (x = .num k ∧ y = .var n)) := by
  match x, y, h with
  | .var n, .num k, h => exact ⟨n, k, varOk_noBound u n r h, Or.inl ⟨rfl, rfl⟩⟩
  | .num k, .var n, h => exact ⟨n, k, varOk_noBound u n r.flip h, Or.inr ⟨rfl, rfl⟩⟩
  | .var _, .var _, h => simp [relOk] at h
  | .num _, .num _, h => simp [relOk] at h

/-- **Clock direction.** If a bound test of a `while` ($u = \bot$) or `until` ($u = \top$) loop compares a clock $n$
(`SECONDS`, `EPOCHSECONDS`), the relation as seen from the clock is `<`/`≤` exactly for `while`: the test then reaches
the loop's exit value as the clock grows.

$$\forall u, W, x, r, y, n.\ n \in \mathrm{clocks} \land \mathrm{atomParse}(W) = \mathrm{some}(x, r, y) \land \mathrm{boundAtom}(u, W) \Rightarrow (x = \mathrm{var}(n) \Rightarrow (\mathrm{down}(r) \iff \lnot u)) \land (y = \mathrm{var}(n) \Rightarrow (\mathrm{down}(\mathrm{flip}(r)) \iff \lnot u))$$
-/
theorem seconds_direction (u : Bool) (ws : List String) (x : Opd) (r : Rel) (y : Opd) (n : String)
    (hc : clocks.contains n = true) (hp : atomParse ws = some (x, r, y)) (hb : boundAtom u ws = true) :
    (x = .var n → r.down = !u) ∧ (y = .var n → r.flip.down = !u) := by
  unfold boundAtom at hb
  rw [hp] at hb
  constructor
  · rintro rfl
    match y, hb with
    | .num _, hb => exact varOk_clock u n r hc hb
    | .var _, hb => simp [relOk] at hb
  · rintro rfl
    match x, hb with
    | .num _, hb => exact varOk_clock u n r.flip hc hb
    | .var _, hb => simp [relOk] at hb


/-- A word holds `$(` (a command substitution, also `$((`): some `$` is directly followed by `(`.

$$\mathrm{dollarParen}([\,]) = \bot, \qquad \mathrm{dollarParen}(a :: r) \iff (a = \texttt{\$} \land \mathrm{head}(r) = \texttt{(}) \lor \mathrm{dollarParen}(r)$$
-/
def dollarParen : List Char → Bool
  | a :: r => (a == '$' && r.head? == some '(') || dollarParen r
  | [] => false

/-- A word holding `$(` holds both `$` and `(`.

$$\forall l.\ \mathrm{dollarParen}(l) \Rightarrow \texttt{\$} \in l \land \texttt{(} \in l$$
-/
theorem dollarParen_mem (l : List Char) (h : dollarParen l = true) : '$' ∈ l ∧ '(' ∈ l := by
  induction l with
  | nil => simp [dollarParen] at h
  | cons a r ih =>
    simp only [dollarParen, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at h
    rcases h with ⟨rfl, hr⟩ | h
    · cases r with
      | nil => simp at hr
      | cons b r' => simp at hr; subst hr; simp
    · have := ih h; exact ⟨List.mem_cons_of_mem _ this.1, List.mem_cons_of_mem _ this.2⟩

/-- A character that fails $p$ is not in a list whose every element passes $p$.

$$\forall p, l, c.\ (\forall a \in l.\ p(a)) \land \lnot p(c) \Rightarrow c \notin l$$
-/
theorem all_not_mem {p : Char → Bool} {l : List Char} {c : Char} (h : l.all p = true) (hc : p c = false) : c ∉ l := by
  intro hm
  have := (List.all_eq_true.mp h) c hm
  simp [hc] at this

/-- A word that parses as an operand is made of operand characters only.

$$\forall b, w, o.\ \mathrm{opd}(b, w) = \mathrm{some}(o) \Rightarrow \forall c \in w.\ \mathrm{opdChar}(c)$$
-/
theorem opd_chars (b : Bool) (w : String) (o : Opd) (h : opd b w = some o) : w.toList.all opdChar = true := by
  unfold opd at h
  split at h
  · assumption
  · simp at h

/-- A word that parses as a relation is one of the eight order operators.

$$\forall a, w, r.\ \mathrm{relOf}(a, w) = \mathrm{some}(r) \Rightarrow w \in \{\texttt{<}, \texttt{<=}, \texttt{>}, \texttt{>=}, \texttt{-lt}, \texttt{-le}, \texttt{-gt}, \texttt{-ge}\}$$
-/
theorem relOf_mem (a : Bool) (w : String) (r : Rel) (h : relOf a w = some r) :
    w ∈ ["<", "<=", ">", ">=", "-lt", "-le", "-gt", "-ge"] := by
  unfold relOf at h
  repeat' split at h
  all_goals simp_all

/-- A parsed three-word test has sides made of operand characters and an order operator in the middle.

$$\forall a, x, o, y, p.\ \mathrm{tri}(a, x, o, y) = \mathrm{some}(p) \Rightarrow (\forall c \in x.\ \mathrm{opdChar}(c)) \land o \in \{\texttt{<}, \texttt{<=}, \texttt{>}, \texttt{>=}, \texttt{-lt}, \texttt{-le}, \texttt{-gt}, \texttt{-ge}\} \land (\forall c \in y.\ \mathrm{opdChar}(c))$$
-/
theorem tri_chars (a : Bool) (x o y : String) (p : Opd × Rel × Opd) (h : tri a x o y = some p) :
    x.toList.all opdChar = true ∧ o ∈ ["<", "<=", ">", ">=", "-lt", "-le", "-gt", "-ge"] ∧
      y.toList.all opdChar = true := by
  unfold tri at h
  split at h
  · rename_i p' r q hx ho hy
    exact ⟨opd_chars _ _ _ hx, relOf_mem _ _ _ ho, opd_chars _ _ _ hy⟩
  · simp at h

/-- Every word of a parsed `(( ))` test is made of arithmetic characters only.

$$\forall W, p.\ \mathrm{arithParse}(W) = \mathrm{some}(p) \Rightarrow \forall w \in W.\ \forall c \in w.\ \mathrm{arithChar}(c)$$
-/
theorem arithParse_chars (ws : List String) (p : Opd × Rel × Opd) (h : arithParse ws = some p) :
    ∀ w ∈ ws, w.toList.all arithChar = true := by
  unfold arithParse at h
  split at h
  · rename_i hw
    exact List.all_eq_true.mp hw
  · simp at h

/-- Every word of a parsed bound test is free of backquotes, and has no `$` (arithmetic form) or no `(` (bracket form).

$$\forall W, p.\ \mathrm{atomParse}(W) = \mathrm{some}(p) \Rightarrow \forall w \in W.\ \texttt{`} \notin w \land (\texttt{\$} \notin w \lor \texttt{(} \notin w)$$
-/
theorem atomParse_chars (ws : List String) (p : Opd × Rel × Opd) (h : atomParse ws = some p) :
    ∀ w ∈ ws, '`' ∉ w.toList ∧ ('$' ∉ w.toList ∨ '(' ∉ w.toList) := by
  have ar : arithParse ws = some p → ∀ w ∈ ws, '`' ∉ w.toList ∧ ('$' ∉ w.toList ∨ '(' ∉ w.toList) := by
    intro ha w hw
    have := arithParse_chars ws p ha w hw
    exact ⟨all_not_mem this (by decide), Or.inl (all_not_mem this (by decide))⟩
  unfold atomParse at h
  split at h
  · rename_i l x o y r
    split at h
    · rename_i hlr
      obtain ⟨hx, ho, hy⟩ := tri_chars _ _ _ _ _ h
      have hl : l = "[" ∨ l = "[[" := by
        simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at hlr
        rcases hlr with ⟨h1, _⟩ | ⟨h1, _⟩ <;> simp [h1]
      have hr : r = "]" ∨ r = "]]" := by
        simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at hlr
        rcases hlr with ⟨_, h1⟩ | ⟨_, h1⟩ <;> simp [h1]
      intro w hw
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hw
      rcases hw with rfl | rfl | rfl | rfl | rfl
      · rcases hl with rfl | rfl <;> decide
      · exact ⟨all_not_mem hx (by decide), Or.inr (all_not_mem hx (by decide))⟩
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at ho
        rcases ho with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
      · exact ⟨all_not_mem hy (by decide), Or.inr (all_not_mem hy (by decide))⟩
      · rcases hr with rfl | rfl <;> decide
    · exact ar h
  · exact ar h

/-- **A substitution is never a bound.** If some word of a condition element holds `$(` (a command substitution or
`$((`) or a backquote, the element is not a bound test, in either loop kind: `[ "$(ls | wc -l)" -gt 0 ]`,
`[ $(gh run list ...) -ge 1 ]`, `[ $((0)) -lt 1 ]`, `` [ `date +%s` -lt 9 ] `` are all unbounded.

$$\forall u, W, w.\ w \in W \land (\mathrm{dollarParen}(w) \lor \texttt{`} \in w) \Rightarrow \lnot\mathrm{boundAtom}(u, W)$$
-/
theorem subst_never_bound (u : Bool) (ws : List String) (w : String) (hw : w ∈ ws)
    (hs : dollarParen w.toList = true ∨ '`' ∈ w.toList) : boundAtom u ws = false := by
  cases hb : boundAtom u ws with
  | false => rfl
  | true =>
    obtain ⟨x, r, y, hp, _⟩ := (boundAtom_iff u ws).mp hb
    have hc := atomParse_chars ws _ hp w hw
    rcases hs with hd | hq
    · have := dollarParen_mem _ hd
      rcases hc.2 with h1 | h1
      · exact absurd this.1 h1
      · exact absurd this.2 h1
    · exact absurd hq hc.1

/-- How the bound of an and-or condition grows by one element. A `while` loop ends when its condition fails, an `until`
loop when it succeeds; a bound test is assumed to reach that exit value and stay there. So for `while`, `a && b` is
bounded when either side is and `a || b` only when both are; for `until` the other way round. After `;`, a newline or
any other terminator the last element alone decides.

$$\mathrm{comb}(\mathit{until}, \mathit{op}, x, a) = \begin{cases} x \land a & \mathit{op} = \mathrm{andIf},\ \mathit{until} \\ x \lor a & \mathit{op} = \mathrm{andIf},\ \lnot\mathit{until} \\ x \lor a & \mathit{op} = \mathrm{orElse},\ \mathit{until} \\ x \land a & \mathit{op} = \mathrm{orElse},\ \lnot\mathit{until} \\ a & \text{otherwise} \end{cases}$$
-/
def comb (untl : Bool) (op : Term) (acc a : Bool) : Bool :=
  match op with
  | .andIf => if untl then acc && a else acc || a
  | .orElse => if untl then acc || a else acc && a
  | _ => a

/-- A variable assignment word (`IFS=`, `LC_ALL=C`): it holds `=`, does not start with `-`, and runs no command
substitution (no `$(` and no backquote).

$$\mathrm{isAssign}(w) \iff \mathrm{has}(w, \texttt{=}) \land w \text{ does not start with } \texttt{-} \land \lnot\mathrm{has}(w, \texttt{\$(}) \land \lnot\mathrm{has}(w, \texttt{`})$$
-/
def isAssign (w : String) : Bool := has w "=" && !w.startsWith "-" && !has w "$(" && !has w "`"

/-- An ANSI-C quoted word `$'\c...'` after quote removal: `$`, a backslash, then at least one letter or digit only
(`$'\0'`, `$'\n'`). It is a literal, never an expansion.

$$\mathrm{ansiArg}(w) \iff w = \texttt{\$}\backslash v \land v \ne \varepsilon \land v \in \{\texttt{A-Z}, \texttt{a-z}, \texttt{0-9}\}^{*}$$
-/
def ansiArg (w : String) : Bool :=
  match w.toList with
  | '$' :: '\\' :: v => !v.isEmpty && v.all Char.isAlphanum
  | _ => false

/-- A zero count or timeout for `read`: a word that is all digits or starts with `-`, whose trailing run of digits is
non-empty and only `0`s (`0`, `00`, `-n0`, `-t0`). `read -n 0`, `-N 0` and `-t 0` consume nothing, so they never reach
the end of the input.

$$\mathrm{zeroArg}(w) \iff d \ne [\,] \land (\forall x \in d.\ x = \texttt{0}) \land (w \text{ starts with } \texttt{-} \lor \forall x \in w.\ x \in \texttt{0-9}),\quad d = \text{the longest suffix of } w \text{ of digits}$$
-/
def zeroArg (w : String) : Bool :=
  let d := w.toList.reverse.takeWhile Char.isDigit
  !d.isEmpty && d.all (· == '0') && (w.startsWith "-" || w.toList.all Char.isDigit)

/-- A word `read` may take in a read-loop condition: a non-empty word of only letters, digits, `_` and `-` (an option,
an option argument or a variable name; so no redirect, no expansion, no operator) that is not an option word holding `u`
(`-u fd` reads another descriptor) and not a zero count or timeout (`zeroArg`), or an ANSI-C literal (`-d $'\0'`).

$$\mathrm{isReadArg}(w) \iff (w \ne \varepsilon \land w \in \{\texttt{A-Z}, \texttt{a-z}, \texttt{0-9}, \texttt{\_}, \texttt{-}\}^{*} \land \lnot(w \text{ starts with } \texttt{-} \land \texttt{u} \in w) \land \lnot\mathrm{zeroArg}(w)) \lor \mathrm{ansiArg}(w)$$
-/
def isReadArg (w : String) : Bool :=
  (w != "" && w.all (fun ch => ch.isAlphanum || ch == '_' || ch == '-') && !(w.startsWith "-" && w.contains 'u') &&
    !zeroArg w) || ansiArg w

/-- A plain `read`: optional assignments, `read`, then only `isReadArg` words.

$$\mathrm{plainRead}(W) \iff \mathrm{dropWhile}(\mathrm{isAssign}, W) = \texttt{read} :: A \ \land\ \forall x \in A.\ \mathrm{isReadArg}(x)$$
-/
def plainRead (ws : List String) : Bool :=
  match ws.dropWhile isAssign with
  | "read" :: args => args.all isReadArg
  | _ => false

/-- A condition element that runs `read` on the loop's stdin: after leading `!` words and words holding `=`, the first
word is `read`.

$$\mathrm{readSeg}(W) \iff \mathrm{head}(\mathrm{dropWhile}(\mathrm{has}(\cdot, \texttt{=}), \mathrm{dropWhile}(\cdot = \texttt{!}, W))) = \texttt{read}$$
-/
def readSeg (ws : List String) : Bool :=
  ((ws.dropWhile (· == "!")).dropWhile (has · "=")).head? == some "read"

/-- A `read` in a loop condition that is not a plain read (`read -u 3`, `read l < f`, `! read`, `X=$(yes) read`): the
loop counts as unbounded at once.

$$\mathrm{badRead}(W) \iff \mathrm{readSeg}(W) \land \lnot\mathrm{plainRead}(W)$$
-/
def badRead (ws : List String) : Bool := readSeg ws && !plainRead ws

/-- A read-loop condition: the words of the segment (from its command on) are exactly `while` and a plain read
(`while IFS= read -r line`). Nothing else may run in the condition.

$$\mathrm{isReadCond}(K) \iff \mathrm{head}(K) = \texttt{while} \land \mathrm{plainRead}(\mathrm{tail}(K))$$
-/
def isReadCond (k : List String) : Bool := k.head? == some "while" && plainRead k.tail

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
  simp only [isReadCond, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

/-- The state of a loop condition read so far (from `while`/`until` up to `do`): an `until` loop, whether the and-or
list so far is bounded, how the last element ended, whether some element runs `read`, and whether the condition is so
far exactly a read-loop head.

$$\mathrm{Cnd} = (\mathit{until}, \mathit{acc}, \mathit{op}, \mathit{rd}, \mathit{exact}) \in \mathbb{B} \times \mathbb{B} \times \mathrm{Term} \times \mathbb{B} \times \mathbb{B}$$
-/
structure Cnd where
  untl  : Bool
  acc   : Bool
  op    : Term
  rd    : Bool
  exact : Bool
deriving DecidableEq, Repr

/-- Add one condition element (its words $A$ as typed, a leading `!` kept, ended by $t$). An element ended by `|` is not
the last of its pipeline, whose status is that of its last element, so it only adds its `read`; otherwise its bound test
(for this loop kind) joins the list by the previous terminator (`comb`). The `read` check looks past reserved prefix
words (`key`).

$$\mathrm{condStep}(d, A, t) = \begin{cases} d[\mathit{rd} := d.\mathit{rd} \lor \mathrm{readSeg}(\mathrm{key}(A))] & t = \mathrm{pipe} \\ d[\mathit{acc} := \mathrm{comb}(d.\mathit{until}, d.\mathit{op}, d.\mathit{acc}, \mathrm{boundAtom}(d.\mathit{until}, A)),\ \mathit{op} := t,\ \mathit{rd} := d.\mathit{rd} \lor \mathrm{readSeg}(\mathrm{key}(A))] & \text{otherwise} \end{cases}$$
-/
def condStep (cd : Cnd) (atom : List String) (t : Term) : Cnd :=
  if t == .pipe then { cd with rd := cd.rd || readSeg (key atom) }
  else { cd with acc := comb cd.untl cd.op cd.acc (boundAtom cd.untl atom), op := t, rd := cd.rd || readSeg (key atom) }

/-- Read a whole condition: `condStep` over its elements (each its words and terminator), in order. This is what
`condPart` and `blockPart` do between `while`/`until` and `do`.

$$\mathrm{condFold}(d, [\,]) = d, \qquad \mathrm{condFold}(d, (A, t) :: X) = \mathrm{condFold}(\mathrm{condStep}(d, A, t), X)$$
-/
def condFold (cd : Cnd) (xs : List (List String × Term)) : Cnd := xs.foldl (fun d p => condStep d p.1 p.2) cd

/-- `comb` is bounded only if the list so far or the new element is.

$$\forall u, o, x, a.\ \mathrm{comb}(u, o, x, a) \Rightarrow x \lor a$$
-/
theorem comb_true (u : Bool) (op : Term) (x a : Bool) (h : comb u op x a = true) : x = true ∨ a = true := by
  cases op <;> cases u <;> cases x <;> cases a <;> simp_all [comb]

/-- `condStep` keeps the loop kind.

$$\forall d, A, t.\ \mathrm{condStep}(d, A, t).\mathit{until} = d.\mathit{until}$$
-/
theorem condStep_untl (cd : Cnd) (atom : List String) (t : Term) : (condStep cd atom t).untl = cd.untl := by
  unfold condStep; split <;> rfl

/-- **Only the grammar bounds a condition.** If a condition read from a state that is not yet bounded ends bounded,
some element of it that is not piped on (its terminator is not `|`, so its status counts) parses in the grammar B with a
test that passes `relOk` for this loop kind. Command substitutions, `gh`/`ls`/`pgrep` polls, string tests and function
calls never parse, so a condition made of them alone is never bounded.

$$\forall d, X.\ \lnot d.\mathit{acc} \land \mathrm{condFold}(d, X).\mathit{acc} \Rightarrow \exists (A, t) \in X.\ t \ne \mathrm{pipe} \land \exists x, r, y.\ \mathrm{atomParse}(A) = \mathrm{some}(x, r, y) \land \mathrm{relOk}(d.\mathit{until}, x, r, y)$$
-/
theorem grammar_only (cd : Cnd) (xs : List (List String × Term)) (h0 : cd.acc = false)
    (h : (condFold cd xs).acc = true) :
    ∃ p ∈ xs, p.2 ≠ .pipe ∧ ∃ x r y, atomParse p.1 = some (x, r, y) ∧ relOk cd.untl x r y = true := by
  suffices key : ∀ (d : Cnd), (condFold d xs).acc = true →
      d.acc = true ∨ ∃ p ∈ xs, p.2 ≠ .pipe ∧ boundAtom d.untl p.1 = true by
    rcases key cd h with h1 | ⟨p, hp, ht, hb⟩
    · simp [h0] at h1
    · exact ⟨p, hp, ht, (boundAtom_iff _ _).mp hb⟩
  clear h h0
  induction xs with
  | nil => intro d hd; exact Or.inl hd
  | cons p xs ih =>
    intro d hd
    have hd' : (condFold (condStep d p.1 p.2) xs).acc = true := hd
    rcases ih (condStep d p.1 p.2) hd' with h1 | ⟨q, hq, ht, hb⟩
    · unfold condStep at h1
      split at h1
      · exact Or.inl h1
      · rename_i hpipe
        rcases comb_true _ _ _ _ h1 with h2 | h2
        · exact Or.inl h2
        · refine Or.inr ⟨p, List.mem_cons_self .., ?_, h2⟩
          simpa using hpipe
    · rw [condStep_untl] at hb
      exact Or.inr ⟨q, List.mem_cons_of_mem _ hq, ht, hb⟩

/-- Replace the first flag of the innermost open block.

$$\mathrm{setTop}(b, (x, q) :: r) = (b, q) :: r, \qquad \mathrm{setTop}(b, [\,]) = [\,]$$
-/
def setTop (b : Bool) : List (Bool × Bool) → List (Bool × Bool)
  | (_, q) :: r => (b, q) :: r
  | [] => []

/-- An output redirect word: after leading digits it starts with `>` (`>f`, `2>/dev/null`, `1>>log`), or it starts with
`&>`. It writes; it never feeds the command's stdin.

$$\mathrm{outRedir}(w) \iff \mathrm{head}(\mathrm{dropWhile}(\cdot \in \texttt{0-9}, w)) = \texttt{>} \lor w \text{ starts with } \texttt{\&>}$$
-/
def outRedir (w : String) : Bool :=
  (w.toList.dropWhile Char.isDigit).head? == some '>' || w.startsWith "&>"

/-- A device path read as input: it holds `/dev/` or starts with `dev/` (so `//dev/zero` and `./../../dev/zero` count),
is not exactly `/dev/null`, and is not an output redirect word (`2>/dev/null`, `>/dev/stderr` write, they read nothing).

$$\mathrm{isDev}(w) \iff (\mathrm{has}(w, \texttt{/dev/}) \lor w \text{ starts with } \texttt{dev/}) \land w \ne \texttt{/dev/null} \land \lnot\mathrm{outRedir}(w)$$
-/
def isDev (w : String) : Bool := (has w "/dev/" || w.startsWith "dev/") && w != "/dev/null" && !outRedir w

/-- A word a finite producer must not hold: `-` (read stdin), a device (`isDev`), a subshell or a process or command
substitution (a word starting with `(`, or holding `<(`, `$(` or a backquote), or a descriptor duplication `<&`.

$$\mathrm{badWord}(w) \iff w = \texttt{-} \lor \mathrm{isDev}(w) \lor w \text{ starts with } \texttt{(} \lor \mathrm{has}(w, \texttt{<(}) \lor \mathrm{has}(w, \texttt{\$(}) \lor \mathrm{has}(w, \texttt{`}) \lor \mathrm{has}(w, \texttt{<\&})$$
-/
def badWord (w : String) : Bool :=
  w == "-" || isDev w || w.startsWith "(" || has w "<(" || has w "$(" || has w "`" || has w "<&"

/-- The git subcommand: the first word after the global options (`-C dir`, `-c k=v` take a value; other `-...` words
none); `""` if there is none.

$$\mathrm{gitSub}([\,]) = \varepsilon, \quad \mathrm{gitSub}(\texttt{-C} :: x :: r) = \mathrm{gitSub}(\texttt{-c} :: x :: r) = \mathrm{gitSub}(r), \quad \mathrm{gitSub}(w :: r) = \begin{cases} \mathrm{gitSub}(r) & w \text{ starts with } \texttt{-} \\ w & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def gitSub : List String → String
  | "-C" :: _ :: r => gitSub r
  | "-c" :: _ :: r => gitSub r
  | w :: r => if w.startsWith "-" then gitSub r else w
  | [] => ""

/-- The git global options set no configuration and no exec path: no option word before the subcommand starts with
`-c`, `--config-env` or `--exec-path` (a config value can name a command: `diff.external`, `alias.x='!yes'`).

$$\mathrm{gitSafe}([\,]) = \top, \quad \mathrm{gitSafe}(\texttt{-C} :: x :: r) = \mathrm{gitSafe}(r), \quad \mathrm{gitSafe}(w :: r) = \begin{cases} \bot & w \text{ starts with } \texttt{-c}, \texttt{-{}-config-env} \text{ or } \texttt{-{}-exec-path} \\ \mathrm{gitSafe}(r) & w \text{ starts with } \texttt{-} \\ \top & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def gitSafe : List String → Bool
  | "-C" :: _ :: r => gitSafe r
  | w :: r =>
    if w.startsWith "-c" || w.startsWith "--config-env" || w.startsWith "--exec-path" then false
    else if w.startsWith "-" then gitSafe r else true
  | [] => true

/-- The git subcommands that read the repository, print and end (no watch, no pager without a tty, no command run).

$$\mathrm{gitFinite} = [\texttt{ls-files}, \texttt{ls-tree}, \texttt{diff}, \texttt{log}, \texttt{show}, \texttt{status}, \texttt{branch}, \texttt{tag}, \texttt{for-each-ref}, \texttt{rev-list}, \texttt{rev-parse}, \texttt{grep}, \texttt{shortlog}, \texttt{describe}, \texttt{cat-file}, \texttt{blame}, \texttt{merge-base}, \texttt{name-rev}, \texttt{reflog}]$$
-/
def gitFinite : List String :=
  ["ls-files", "ls-tree", "diff", "log", "show", "status", "branch", "tag", "for-each-ref", "rev-list", "rev-parse",
   "grep", "shortlog", "describe", "cat-file", "blame", "merge-base", "name-rev", "reflog"]

/-- The words after the git subcommand (the global options skipped as in `gitSub`); `[]` if there is no subcommand.

$$\mathrm{gitAfter}([\,]) = [\,], \quad \mathrm{gitAfter}(\texttt{-C} :: x :: r) = \mathrm{gitAfter}(\texttt{-c} :: x :: r) = \mathrm{gitAfter}(r), \quad \mathrm{gitAfter}(w :: r) = \begin{cases} \mathrm{gitAfter}(r) & w \text{ starts with } \texttt{-} \\ r & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def gitAfter : List String → List String
  | "-C" :: _ :: r => gitAfter r
  | "-c" :: _ :: r => gitAfter r
  | w :: r => if w.startsWith "-" then gitAfter r else r
  | [] => []

/-- A git subcommand $s$ with its words $A$ that reads, prints and ends: $s$ in `gitFinite`, or `worktree list`,
`stash list`, `remote` alone, `remote -v`, `remote get-url ...`, or `config` with a `--list`, `-l` or `--get...` word
and no `--edit`/`-e` word.

$$\mathrm{gitReadOnly}(s, A) \iff s \in \mathrm{gitFinite} \lor (s \in \{\texttt{worktree}, \texttt{stash}\} \land \mathrm{head}(A) = \texttt{list}) \lor (s = \texttt{remote} \land (A = [\,] \lor \mathrm{head}(A) \in \{\texttt{-v}, \texttt{get-url}\})) \lor (s = \texttt{config} \land \exists x \in A.\ x \in \{\texttt{-{}-list}, \texttt{-l}\} \lor x \text{ starts with } \texttt{-{}-get}) \land \forall x \in A.\ x \notin \{\texttt{-{}-edit}, \texttt{-e}\})$$
-/
def gitReadOnly (s : String) (a : List String) : Bool :=
  gitFinite.contains s || ((s == "worktree" || s == "stash") && a.head? == some "list") ||
    (s == "remote" && (a.isEmpty || a.head? == some "-v" || a.head? == some "get-url")) ||
    (s == "config" && a.any (fun x => x == "--list" || x == "-l" || x.startsWith "--get") &&
      !a.any (fun x => x == "--edit" || x == "-e"))

/-- Substrings that may make a jq program loop or generate without end.

$$\mathrm{jqLoopWords} = [\texttt{repeat}, \texttt{recurse}, \texttt{until}, \texttt{while}, \texttt{range}, \texttt{def}, \texttt{infinite}]$$
-/
def jqLoopWords : List String := ["repeat", "recurse", "until", "while", "range", "def", "infinite"]

/-- A sed word that may loop or hide its script: a label (`:a` at the start of a word or after `;`, `; ` or a newline;
a branch back to it can loop), or a short option cluster holding `f` or a `--file` option (script in a file).

$$\mathrm{sedLoop}(w) \iff w \text{ starts with } \texttt{:} \lor \mathrm{has}(w, \texttt{;:}) \lor \mathrm{has}(w, \texttt{; :}) \lor \mathrm{has}(w, \text{⏎}\texttt{:}) \lor (w \text{ starts with } \texttt{-} \land w \text{ does not start with } \texttt{-{}-} \land \texttt{f} \in w) \lor w \text{ starts with } \texttt{-{}-file}$$
-/
def sedLoop (w : String) : Bool :=
  w.startsWith ":" || has w ";:" || has w "; :" || has w "\n:" ||
    (w.startsWith "-" && !w.startsWith "--" && w.contains 'f') || w.startsWith "--file"

/-- Substrings that may make an awk program loop, read more input or run a command: loops, `getline`, `system`, an
output pipe to a command.

$$\mathrm{awkLoopWords} = [\texttt{while}, \texttt{for(}, \texttt{for (}, \texttt{do\{}, \texttt{do \{}, \texttt{getline}, \texttt{system}, \texttt{|"}, \texttt{| "}]$$
-/
def awkLoopWords : List String := ["while", "for(", "for (", "do{", "do {", "getline", "system", "|\"", "| \""]

/-- An awk word that may loop or hide its program: it holds an `awkLoopWords` substring, or it is a short option cluster
holding `f` or a `--file` option (program in a file).

$$\mathrm{awkLoop}(w) \iff (\exists j \in \mathrm{awkLoopWords}.\ \mathrm{has}(w, j)) \lor (w \text{ starts with } \texttt{-} \land w \text{ does not start with } \texttt{-{}-} \land \texttt{f} \in w) \lor w \text{ starts with } \texttt{-{}-file}$$
-/
def awkLoop (w : String) : Bool :=
  awkLoopWords.any (has w ·) || (w.startsWith "-" && !w.startsWith "--" && w.contains 'f') || w.startsWith "--file"

/-- The duration word of `timeout` (after its options; `-s` and `-k` take a value), if any.

$$\mathrm{timeoutArg}(\texttt{-s} :: x :: r) = \mathrm{timeoutArg}(\texttt{-k} :: x :: r) = \mathrm{timeoutArg}(r), \quad \mathrm{timeoutArg}(w :: r) = \begin{cases} \mathrm{timeoutArg}(r) & w \text{ starts with } \texttt{-} \\ \mathrm{some}(w) & \text{otherwise} \end{cases}, \quad \mathrm{timeoutArg}([\,]) = \mathrm{none} \quad \text{(first matching row)}$$
-/
def timeoutArg : List String → Option String
  | "-s" :: _ :: r => timeoutArg r
  | "-k" :: _ :: r => timeoutArg r
  | w :: r => if w.startsWith "-" then timeoutArg r else some w
  | [] => none

/-- `timeout N cmd` with a whole positive duration (`secs?`; `0` disables the timeout, `0.5` and `$n` are not read).

$$\mathrm{timeoutOk}(r) \iff \exists w, n.\ \mathrm{timeoutArg}(r) = \mathrm{some}(w) \land \mathrm{secs?}(w) = \mathrm{some}(n) \land 0 < n$$
-/
def timeoutOk (r : List String) : Bool :=
  match timeoutArg r with
  | some w => match secs? w with
    | some n => decide (0 < n)
    | none => false
  | none => false

/-- The xargs options that take a value as the next word.

$$\mathrm{xargsValOpts} = [\texttt{-I}, \texttt{-n}, \texttt{-P}, \texttt{-L}, \texttt{-s}, \texttt{-d}, \texttt{-E}, \texttt{-J}, \texttt{-a}, \texttt{-R}, \texttt{-S}]$$
-/
def xargsValOpts : List String := ["-I", "-n", "-P", "-L", "-s", "-d", "-E", "-J", "-a", "-R", "-S"]

/-- The command xargs runs: its words after the xargs options (`[]`: xargs runs `echo`).

$$\mathrm{xargsCmd}(w :: x :: r) = \begin{cases} \mathrm{xargsCmd}(r) & w \in \mathrm{xargsValOpts} \\ \mathrm{xargsCmd}(x :: r) & w \text{ starts with } \texttt{-} \\ w :: x :: r & \text{otherwise} \end{cases}, \quad \mathrm{xargsCmd}([w]) = \begin{cases} [\,] & w \text{ starts with } \texttt{-} \\ [w] & \text{otherwise} \end{cases}, \quad \mathrm{xargsCmd}([\,]) = [\,]$$
-/
def xargsCmd : List String → List String
  | w :: rest@(_ :: r) =>
    if xargsValOpts.contains w then xargsCmd r
    else if w.startsWith "-" then xargsCmd rest else w :: rest
  | [w] => if w.startsWith "-" then [] else [w]
  | [] => []

/-- The command allowlist on the key words $K$ of a producer; $i$ says its stdin is finite. Sources (output independent
of stdin): `git` with safe global options, a read-only subcommand (`gitReadOnly`) and no `--stdin`; `gh run|pr|issue list|view`;
`cat` with an operand (a word not starting with `-`) and no option word holding `u`; `find` with no
`-exec -execdir -ok -okdir`; `seq` with no word holding `inf` or `nan` (any case); `ls`, `printf`, `echo`. Only when $i$:
`node scripts/X.mjs` (a repo script: the path starts with `scripts/` or `./scripts/`, ends with `.mjs`, holds no `..`;
MEASURED 2026-10-18: no repo `scripts/*.mjs` listens, watches or loops forever), `jq` with no `jqLoopWords` substring,
`rg` with no `--pre...` word, `sort` with no `--compress...` word, `sed` with no `sedLoop` word, `awk` with no `awkLoop`
word, `grep`, `head`, `wc`, `tr`, `cut`, `uniq`. Anything else (`pnpm`, `npm`, other `node` runs, `tail`, `yes`) is not.

$$\mathrm{finiteCmd}(i, K) = \begin{cases} \mathrm{gitSafe}(r) \land \mathrm{gitReadOnly}(\mathrm{gitSub}(r), \mathrm{gitAfter}(r)) \land \texttt{-{}-stdin} \notin r & K = \texttt{git} :: r \\ g \in \{\texttt{run}, \texttt{pr}, \texttt{issue}\} \land v \in \{\texttt{list}, \texttt{view}\} & K = \texttt{gh} :: g :: v :: r \\ (\exists x \in r.\ x \text{ not starting with } \texttt{-}) \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-} \land \texttt{u} \in x & K = \texttt{cat} :: r \\ r \cap \{\texttt{-exec}, \texttt{-execdir}, \texttt{-ok}, \texttt{-okdir}\} = \emptyset & K = \texttt{find} :: r \\ \lnot\exists x \in r.\ \mathrm{has}(\mathrm{lower}(x), \texttt{inf}) \lor \mathrm{has}(\mathrm{lower}(x), \texttt{nan}) & K = \texttt{seq} :: r \\ \top & K = k :: r,\ k \in \{\texttt{ls}, \texttt{printf}, \texttt{echo}\} \\ i \land p \text{ starts with } \texttt{scripts/} \text{ or } \texttt{./scripts/} \land p \text{ ends with } \texttt{.mjs} \land \lnot\mathrm{has}(p, \texttt{..}) & K = \texttt{node} :: p :: r \\ i \land \lnot\exists x \in r, j \in \mathrm{jqLoopWords}.\ \mathrm{has}(x, j) & K = \texttt{jq} :: r \\ i \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-{}-pre} & K = \texttt{rg} :: r \\ i \land \lnot\exists x \in r.\ x \text{ starts with } \texttt{-{}-compress} & K = \texttt{sort} :: r \\ i \land \lnot\exists x \in r.\ \mathrm{sedLoop}(x) & K = \texttt{sed} :: r \\ i \land \lnot\exists x \in r.\ \mathrm{awkLoop}(x) & K = \texttt{awk} :: r \\ i & K = k :: r,\ k \in \{\texttt{grep}, \texttt{head}, \texttt{wc}, \texttt{tr}, \texttt{cut}, \texttt{uniq}\} \\ \bot & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def finiteCmd (inFin : Bool) : List String → Bool
  | "git" :: r => gitSafe r && gitReadOnly (gitSub r) (gitAfter r) && !r.contains "--stdin"
  | "gh" :: g :: v :: _ => (g == "run" || g == "pr" || g == "issue") && (v == "list" || v == "view")
  | "cat" :: r => r.any (fun x => !x.startsWith "-") && !r.any (fun x => x.startsWith "-" && x.contains 'u')
  | "find" :: r => !r.any (fun x => x == "-exec" || x == "-execdir" || x == "-ok" || x == "-okdir")
  | "seq" :: r => !r.any (fun x => has x.toLower "inf" || has x.toLower "nan")
  | "ls" :: _ => true
  | "printf" :: _ => true
  | "echo" :: _ => true
  | "node" :: p :: _ =>
    inFin && (p.startsWith "scripts/" || p.startsWith "./scripts/") && p.endsWith ".mjs" && !has p ".."
  | "jq" :: r => inFin && !r.any (fun x => jqLoopWords.any (has x ·))
  | "rg" :: r => inFin && !r.any (·.startsWith "--pre")
  | "sort" :: r => inFin && !r.any (·.startsWith "--compress")
  | "sed" :: r => inFin && !r.any sedLoop
  | "awk" :: r => inFin && !r.any awkLoop
  | "grep" :: _ => inFin
  | "head" :: _ => inFin
  | "wc" :: _ => inFin
  | "tr" :: _ => inFin
  | "cut" :: _ => inFin
  | "uniq" :: _ => inFin
  | _ => false

/-- The producer allowlist by first command word: sources (their output does not depend on stdin; `timeout` bounds its
command) and filters (they end when their stdin ends, so they need a finite stdin).

$$\mathrm{sourceCmds} = [\texttt{git}, \texttt{gh}, \texttt{cat}, \texttt{find}, \texttt{ls}, \texttt{printf}, \texttt{echo}, \texttt{seq}, \texttt{timeout}, \texttt{gtimeout}]$$
-/
def sourceCmds : List String := ["git", "gh", "cat", "find", "ls", "printf", "echo", "seq", "timeout", "gtimeout"]

/-- The filters of the producer allowlist (see `sourceCmds`).

$$\mathrm{filterCmds} = [\texttt{grep}, \texttt{rg}, \texttt{jq}, \texttt{sort}, \texttt{head}, \texttt{wc}, \texttt{sed}, \texttt{tr}, \texttt{cut}, \texttt{uniq}, \texttt{awk}, \texttt{xargs}, \texttt{node}]$$
-/
def filterCmds : List String := ["grep", "rg", "jq", "sort", "head", "wc", "sed", "tr", "cut", "uniq", "awk", "xargs", "node"]

/-- Every command name a finite producer may start with.

$$\mathrm{producerCmds} = \mathrm{sourceCmds} \mathbin{+\!\!+} \mathrm{filterCmds}$$
-/
def producerCmds : List String := sourceCmds ++ filterCmds

/-- Is the output of a segment known to be finite (an allowlist)? $\mathit{inFin}$ says its stdin is finite; $K =
\mathrm{key}(W)$. `timeout N cmd` (also `gtimeout`) is finite whatever `cmd` is, for a whole $N > 0$ (`timeoutOk`).
`xargs` needs a finite stdin, and the command it runs (`xargsCmd`, an argument `{}` appended for the items it adds; none
means `echo`) must be on the allowlist with a finite stdin. Any other segment needs no bad word, no long shape, and
`finiteCmd`.

$$\mathrm{producerOut}_c(\mathit{inFin}, W) = \begin{cases} \mathrm{timeoutOk}(r) & K = k :: r,\ k \in \{\texttt{timeout}, \texttt{gtimeout}\} \\ \mathit{inFin} \land \mathrm{clean} \land (X = [\,] \lor \mathrm{finiteCmd}(\top, X \mathbin{+\!\!+} [\texttt{\{\}}])) & K = \texttt{xargs} :: r,\ X = \mathrm{xargsCmd}(r) \\ \mathrm{clean} \land \mathrm{finiteCmd}(\mathit{inFin}, K) & \text{otherwise} \end{cases} \quad \text{(first matching row)},\quad \text{where } K = \mathrm{key}(W),\ \mathrm{clean} \iff (\forall x \in K.\ \lnot\mathrm{badWord}(x)) \land \mathrm{shapesOf}_c(W) = [\,]$$
The rows are tried in order.
-/
def producerOut (c : Caps) (inFin : Bool) (ws : List String) : Bool :=
  let ks := key ws
  let clean := !ks.any badWord && (shapesOf c ws).isEmpty
  match ks with
  | "timeout" :: r => timeoutOk r
  | "gtimeout" :: r => timeoutOk r
  | "xargs" :: r => inFin && clean && (match xargsCmd r with
    | [] => true
    | x => finiteCmd true (x ++ ["{}"]))
  | _ => clean && finiteCmd inFin ks

/-- **A producer outside the allowlist is never finite**, whatever its stdin: `ping`, `tail`, `yes`, `log stream`,
`sleep`, `pnpm`, a block word, an empty segment.

$$\forall c, i, W.\ \mathrm{head}(\mathrm{key}(W)) \notin \mathrm{producerCmds} \ \Rightarrow\ \lnot\mathrm{producerOut}_c(i, W)$$
where $\mathrm{head}$ of an empty list is the empty word $\varepsilon$ (not in the list).
-/
theorem producer_outside_list (c : Caps) (inFin : Bool) (ws : List String)
    (h : producerCmds.contains ((key ws).head?.getD "") = false) : producerOut c inFin ws = false := by
  unfold producerOut
  generalize key ws = ks at *
  dsimp only
  split
  · simp_all [producerCmds, sourceCmds, filterCmds]
  · simp_all [producerCmds, sourceCmds, filterCmds]
  · simp_all [producerCmds, sourceCmds, filterCmds]
  · rename_i hx1 hx2 hx3
    have : finiteCmd inFin ks = false := by
      unfold finiteCmd
      split <;> simp_all [producerCmds, sourceCmds, filterCmds]
    simp [this]

/-- A filter (`grep rg jq sort head wc sed tr cut uniq awk xargs node`) reading an input not known to be finite is not
finite (`tail -f x | grep y`).

$$\forall c, W.\ \mathrm{head}(\mathrm{key}(W)) \in \mathrm{filterCmds} \ \Rightarrow\ \lnot\mathrm{producerOut}_c(\bot, W)$$
where $\mathrm{head}$ of an empty list is the empty word $\varepsilon$.
-/
theorem filter_needs_finite_input (c : Caps) (ws : List String)
    (h : filterCmds.contains ((key ws).head?.getD "") = true) : producerOut c false ws = false := by
  unfold producerOut
  generalize key ws = ks at *
  dsimp only
  split
  · simp_all [filterCmds]
  · simp_all [filterCmds]
  · simp
  · have : finiteCmd false ks = false := by
      unfold finiteCmd
      split <;> simp_all [filterCmds]
    simp [this]

/-- A redirect target that is a finite input: non-empty, not a process substitution or subshell (`(...` or `<(...`),
not a descriptor (`&3`) or a read-write `<>`, and not a device (`isDev`: `/dev/zero`, `/dev/stdin`, `//dev/zero` and ttys
may never end; `/dev/null` is fine), and no command substitution (`< "$(yes)"` runs `yes` to name the file).

$$\mathrm{finiteTarget}(t) \iff t \ne \varepsilon \land t \text{ starts with none of } \texttt{(},\ \texttt{<(},\ \texttt{\&},\ \texttt{>} \land \lnot\mathrm{isDev}(t) \land \lnot\mathrm{has}(t, \texttt{\$(}) \land \lnot\mathrm{has}(t, \texttt{`})$$
-/
def finiteTarget (t : String) : Bool :=
  t != "" && !t.startsWith "(" && !t.startsWith "<(" && !t.startsWith "&" && !t.startsWith ">" && !isDev t &&
    !has t "$(" && !has t "`"

/-- The redirect scan state: whether the last stdin redirect seen is finite (`none`: no stdin redirect yet), whether the
previous word was a bare `<` or `0<` (its target comes next), whether the previous word was a bare `<<<` (its word comes
next), and the words of an open process substitution read so far with a flag that it is the stdin target (`none`
outside one).

$$\mathrm{RAcc} = \mathrm{Option}(\mathbb{B}) \times \mathbb{B} \times \mathbb{B} \times \mathrm{Option}(\mathrm{String}^{*} \times \mathbb{B}), \quad r = (\mathit{last}, \mathit{lt}, \mathit{hs}, \mathit{sub}), \quad \{\} = (\mathrm{none}, \bot, \bot, \mathrm{none})$$
-/
structure RAcc where
  last : Option Bool := none
  lt   : Bool := false
  hs   : Bool := false
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

/-- A here-string word that is a finite input: it runs no command substitution (no `$(` and no backquote), or it is
exactly one substitution `$(v)` whose text $v$ holds none of `| ; & < > ( )`, a backquote or a newline, and whose words
($v$ split at spaces) are a finite producer (`subFin`). So `<<< "$(gh run list)"` is finite and `<<< "$(yes)"` is not.

$$\mathrm{hereOk}_c(w) = \begin{cases} \top & \lnot\mathrm{has}(w, \texttt{\$(}) \land \lnot\mathrm{has}(w, \texttt{`}) \\ (\forall ch \in v.\ ch \notin \{\texttt{|}, \texttt{;}, \texttt{\&}, \texttt{<}, \texttt{>}, \texttt{(}, \texttt{)}, \texttt{`}, \text{⏎}\}) \land \mathrm{subFin}_c(\mathrm{split}(v, \text{␣})) & w = \texttt{\$(}\,v\,\texttt{)} \\ \bot & \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def hereOk (c : Caps) (w : String) : Bool :=
  if !has w "$(" && !has w "`" then true
  else if w.startsWith "$(" then
    match closeParen (dropS w 2) with
    | some v => !v.toList.any (fun ch => "|;&<>()`\n".toList.contains ch) && subFin c (v.splitOn " ")
    | none => false
  else false

/-- Open a process substitution at the word rest `x` (after `<(`): closed at once if `x` ends with `)`; `st` says it is
the stdin target.

$$\mathrm{openSub}_c(r, x, \mathit{st}) = \begin{cases} r[\mathit{lt} := \bot,\ \mathit{last} := (\mathit{st}\ ?\ \mathrm{some}(\mathrm{subFin}_c([v])) : r.\mathit{last})] & \mathrm{closeParen}(x) = \mathrm{some}(v) \\ r[\mathit{lt} := \bot,\ \mathit{sub} := \mathrm{some}([x], \mathit{st})] & \text{otherwise} \end{cases}$$
-/
def openSub (c : Caps) (r : RAcc) (x : String) (st : Bool) : RAcc :=
  match closeParen x with
  | some v => { r with lt := false, last := if st then some (subFin c [v]) else r.last }
  | none => { r with lt := false, sub := some ([x], st) }

/-- One word of a redirect scan (first matching row). Inside a process substitution words are collected until one ends
with `)`. After a bare `<<<` the word is the here-string; after a bare `<`/`0<` the target. A word `<<<w` is a
here-string, another `<<...` word a here-document (finite); `<t` or `0<t` a file redirect; a `<(` word not after `<` is an
argument, skipped. Other words change nothing.

$$\mathrm{rstep}_c(r, w) = \begin{cases} r[\mathit{sub} := \mathrm{none},\ \mathit{last} := (\mathit{st}\ ?\ \mathrm{some}(\mathrm{subFin}_c(W \mathbin{+\!\!+} [v])) : r.\mathit{last})] & r.\mathit{sub} = \mathrm{some}(W, \mathit{st}),\ \mathrm{closeParen}(w) = \mathrm{some}(v) \\ r[\mathit{sub} := \mathrm{some}(W \mathbin{+\!\!+} [w], \mathit{st})] & r.\mathit{sub} = \mathrm{some}(W, \mathit{st}) \\ r[\mathit{hs} := \bot,\ \mathit{last} := \mathrm{some}(\mathrm{hereOk}_c(w))] & r.\mathit{hs} \\ \mathrm{openSub}_c(r, \mathrm{dropS}(w, 2), \top) & r.\mathit{lt},\ w \text{ starts with } \texttt{<(} \\ r[\mathit{lt} := \bot,\ \mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(w))] & r.\mathit{lt} \\ r[\mathit{lt} := \top] & w \in \{\texttt{<}, \texttt{0<}\} \\ r[\mathit{hs} := \top] & w = \texttt{<<<} \\ r[\mathit{last} := \mathrm{some}(\mathrm{hereOk}_c(\mathrm{dropS}(w, 3)))] & w \text{ starts with } \texttt{<<<} \\ r[\mathit{last} := \mathrm{some}(\top)] & w \text{ starts with } \texttt{<<} \\ \mathrm{openSub}_c(r, \mathrm{dropS}(w, 2), \bot) & w \text{ starts with } \texttt{<(} \\ r[\mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(\mathrm{dropS}(w, 1)))] & w \text{ starts with } \texttt{<} \\ r[\mathit{last} := \mathrm{some}(\mathrm{finiteTarget}(\mathrm{dropS}(w, 2)))] & w \text{ starts with } \texttt{0<} \\ r & \text{otherwise} \end{cases}$$
-/
def rstep (c : Caps) (r : RAcc) (w : String) : RAcc :=
  match r.sub with
  | some (ws, st) =>
    match closeParen w with
    | some v => { r with sub := none, last := if st then some (subFin c (ws ++ [v])) else r.last }
    | none => { r with sub := some (ws ++ [w], st) }
  | none =>
    if r.hs then { r with hs := false, last := some (hereOk c w) }
    else if r.lt then
      if w.startsWith "<(" then openSub c r (dropS w 2) true
      else { r with lt := false, last := some (finiteTarget w) }
    else if w == "<" || w == "0<" then { r with lt := true }
    else if w == "<<<" then { r with hs := true }
    else if w.startsWith "<<<" then { r with last := some (hereOk c (dropS w 3)) }
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

/-- The running state of the unit grouping: the open blocks (innermost first; each with two flags: its condition runs
`read`, and it reads a finite pipe), the shapes so far, whether a loop with no bound was seen (`free`), whether the unit is
still empty, the previous segment, the loop condition being read (`none` outside one), whether the previous segment's
output is known finite, and the finished units.

$$\mathrm{UAcc} = (\mathbb{B} \times \mathbb{B})^{*} \times \mathrm{Shape}^{*} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Seg} \times \mathrm{Option}(\mathrm{Cnd}) \times \mathbb{B} \times \mathrm{Job}^{*}$$
$$u = (\mathit{stack}, \mathit{shapes}, \mathit{free}, \mathit{fresh}, \mathit{last}, \mathit{cnd}, \mathit{lastFin}, \mathit{units}), \quad \{\} = ([\,], [\,], \bot, \top, ([\,], \mathrm{fin}), \mathrm{none}, \bot, [\,])$$
-/
structure UAcc where
  stack   : List (Bool × Bool) := []
  shapes  : List Shape := []
  free    : Bool := false
  fresh   : Bool := true
  last    : Seg := ⟨[], .fin⟩
  cnd     : Option Cnd := none
  lastFin : Bool := false
  units   : List Job := []

/-- A block word: a block opener or closer.

$$\mathrm{blockWord}(f) \iff f \in \mathrm{openers} \lor f \in \mathrm{closers}$$
-/
def blockWord (f : String) : Bool := openers.contains f || closers.contains f

/-- The condition part of a step: with no condition open, nothing changes. A segment starting with `do` ends the
condition: the open loop's first flag records whether the condition ran `read`, and the loop is free unless the condition
is bounded (`acc`) or exactly a read-loop head (`exact`; its input is checked at `done`). A block word inside a condition
makes the loop free. Any other segment is one more condition element ($K = \mathrm{key}(s.\mathit{words})$, $f$ its head,
`""` if none).

$$\mathrm{condPart}(u, s) = \begin{cases} (u.\mathit{stack},\ u.\mathit{free},\ \mathrm{none}) & u.\mathit{cnd} = \mathrm{none} \\ (\mathrm{setTop}(d.\mathit{rd}, u.\mathit{stack}),\ u.\mathit{free} \lor \lnot(d.\mathit{acc} \lor d.\mathit{exact}),\ \mathrm{none}) & u.\mathit{cnd} = \mathrm{some}(d),\ \mathrm{head}(s.\mathit{words}) = \texttt{do} \\ (u.\mathit{stack},\ \top,\ \mathrm{none}) & u.\mathit{cnd} = \mathrm{some}(d),\ \mathrm{blockWord}(f) \\ (u.\mathit{stack},\ u.\mathit{free} \lor \mathrm{badRead}(K),\ \mathrm{some}(\mathrm{condStep}(d[\mathit{exact} := \bot], s.\mathit{words}, s.\mathit{term}))) & u.\mathit{cnd} = \mathrm{some}(d),\ \text{otherwise} \end{cases} \quad \text{(first matching row)}$$
-/
def condPart (u : UAcc) (s : Seg) : List (Bool × Bool) × Bool × Option Cnd :=
  match u.cnd with
  | none => (u.stack, u.free, none)
  | some cd =>
    if s.words.head? == some "do" then (setTop cd.rd u.stack, u.free || !(cd.acc || cd.exact), none)
    else if blockWord ((key s.words).head?.getD "") then (u.stack, true, none)
    else (u.stack, u.free || badRead (key s.words), some (condStep { cd with exact := false } s.words s.term))

/-- The block part of a step, on the stack $S$ and condition $D$ left by `condPart` ($K = \mathrm{key}(s.\mathit{words})$,
$f$ its head, `""` if none; $\pi$: the segment reads a finite pipe). An opener pushes a block; a `while`/`until` also opens
its condition with the rest of its segment. A closer pops the innermost block, and a loop whose condition ran `read` is
free when its stdin is not known finite (the `done` segment's last stdin redirect, else the pipe it reads).

$$\mathrm{blockPart}_c(\pi, s, S, D) = \begin{cases} ((\bot, \pi) :: S,\ \bot,\ \mathrm{some}(\mathrm{condStep}((f = \texttt{until}, \bot, \mathrm{seq}, \bot, \mathrm{readHead}(s)), \mathrm{tail}(K), s.\mathit{term}))) & f \in \{\texttt{while}, \texttt{until}\} \\ ((\bot, \pi) :: S,\ \bot,\ D) & f \in \mathrm{openers} \setminus \{\texttt{while}, \texttt{until}\} \\ (r,\ p_1 \land \lnot\,\mathrm{getD}(\mathrm{inRedir}_c(s.\mathit{words}), p_2),\ D) & f \in \mathrm{closers},\ S = (p_1, p_2) :: r \\ ([\,],\ \bot,\ D) & f \in \mathrm{closers},\ S = [\,] \\ (S,\ \bot,\ D) & \text{otherwise} \end{cases} \quad \text{(first matching row)},\quad \text{where } K = \mathrm{key}(s.\mathit{words}),\ f = \mathrm{head}(K) \text{ (\texttt{""} if } K = [\,]),\ \mathrm{getD}(\mathrm{some}(b), x) = b,\ \mathrm{getD}(\mathrm{none}, x) = x$$
The `done` redirect overrides the pipe.
-/
def blockPart (c : Caps) (piped : Bool) (s : Seg) (st : List (Bool × Bool)) (cd : Option Cnd) :
    List (Bool × Bool) × Bool × Option Cnd :=
  let k := key s.words
  let f := k.head?.getD ""
  if openers.contains f then
    ((false, piped) :: st, false,
      if f == "until" || f == "while" then some (condStep ⟨f == "until", false, .seq, false, readHead s⟩ k.tail s.term)
      else cd)
  else if closers.contains f then
    match st with
    | p :: r => (r, p.1 && !(inRedir c s.words).getD p.2, cd)
    | [] => ([], false, cd)
  else (st, false, cd)

/-- Add one segment to the grouping; close the unit when no block is open and the segment ends the and-or list. Here
$K = \mathrm{key}(s.\mathit{words})$, $f$ its head (`""` if none), $\ell \iff f \in \{\texttt{until}, \texttt{while}\}$,
$\iota \iff u.\mathit{last}.\mathit{term} \ne \mathrm{pipe} \lor u.\mathit{lastFin}$ (this segment's stdin is finite: a
pipeline head reads the tool's stdin), $\pi \iff u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land u.\mathit{lastFin}$
(it reads a finite pipe), $(S_0, F_0, D_0) = \mathrm{condPart}(u, s)$ and $(S, \phi, D) = \mathrm{blockPart}_c(\pi, s, S_0,
D_0)$.

$$\mathrm{addSeg}_c(u, s) = \begin{cases} \{\}[\mathit{units} := (s.\mathit{term} = \mathrm{bg},\ u'.\mathit{shapes},\ u'.\mathit{free}) :: u.\mathit{units}] & S = [\,] \land s.\mathit{term} \notin \{\mathrm{andIf}, \mathrm{orElse}, \mathrm{pipe}\} \\ u' & \text{otherwise} \end{cases}$$
$$u' = u[\mathit{stack} := S,\ \mathit{shapes} := u.\mathit{shapes} \mathbin{+\!\!+} [\mathrm{loop} \mid \ell] \mathbin{+\!\!+} \mathrm{shapesOf}_c(s.\mathit{words}),\ \mathit{free} := F_0 \lor (\ell \land \mathrm{badRead}(\mathrm{tail}(K))) \lor \phi,$$
$$\qquad \mathit{fresh} := \bot,\ \mathit{last} := s,\ \mathit{cnd} := D,\ \mathit{lastFin} := \mathrm{producerOut}_c(\iota, s.\mathit{words})]$$
-/
def addSeg (c : Caps) (u : UAcc) (s : Seg) : UAcc :=
  let k := key s.words
  let f := k.head?.getD ""
  let isLoop := f == "until" || f == "while"
  let inFin := u.last.term != .pipe || u.lastFin
  let piped := u.last.term == .pipe && u.lastFin
  let a := condPart u s
  let b := blockPart c piped s a.1 a.2.2
  let sh := (if isLoop then [Shape.loop] else []) ++ shapesOf c s.words
  let u' := { u with stack := b.1, shapes := u.shapes ++ sh, free := a.2.1 || (isLoop && badRead k.tail) || b.2.1,
                     fresh := false, last := s, cnd := b.2.2, lastFin := producerOut c inFin s.words }
  if b.1.isEmpty && s.term != .andIf && s.term != .orElse && s.term != .pipe then
    { units := ⟨s.term == .bg, u'.shapes, u'.free⟩ :: u.units }
  else u'

/-- The units of a command (a trailing open unit is closed at the end; a loop condition still open there, or an open
loop whose condition ran `read`, counts as unbounded). Here $u = \mathrm{foldl}(\mathrm{addSeg}_c, \{\},
\mathrm{parse}(\mathit{cmd}))$.

$$\mathrm{units}_c(\mathit{cmd}) = \mathrm{rev}\begin{cases} u.\mathit{units} & u.\mathit{fresh} \\ (\bot,\ u.\mathit{shapes},\ u.\mathit{free} \lor u.\mathit{cnd} \ne \mathrm{none} \lor \exists p \in u.\mathit{stack}.\ p_1) :: u.\mathit{units} & \text{otherwise} \end{cases}$$
-/
def units (c : Caps) (cmd : String) : List Job :=
  let u := (parse cmd).foldl (addSeg c) {}
  let u := if u.fresh then u
    else { u with units := ⟨false, u.shapes, u.free || u.cnd.isSome || u.stack.any (·.1)⟩ :: u.units }
  u.units.reverse

/-- A `while`/`until` segment, read with no condition open, pushes a block whose read flag is still off and opens its
condition with the rest of its words; it marks the loop free exactly when that first element is a bad read, and it closes
no unit.

$$\forall c, u, s.\ u.\mathit{cnd} = \mathrm{none} \land f \in \{\texttt{while}, \texttt{until}\} \ \Rightarrow\ v.\mathit{stack} = (\bot, \pi) :: u.\mathit{stack} \land v.\mathit{cnd} = \mathrm{some}(\mathrm{condStep}((f = \texttt{until}, \bot, \mathrm{seq}, \bot, \mathrm{readHead}(s)), \mathrm{tail}(K), s.\mathit{term}))$$
$$\qquad \land\ v.\mathit{free} = (u.\mathit{free} \lor \mathrm{badRead}(\mathrm{tail}(K))) \land v.\mathit{units} = u.\mathit{units},\quad \text{where } K = \mathrm{key}(s.\mathit{words}),\ f = \mathrm{head}(K)\text{ (\texttt{""} if } K = [\,]),\ \pi \iff u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land u.\mathit{lastFin},\ v = \mathrm{addSeg}_c(u, s)$$
-/
theorem addSeg_loop (c : Caps) (u : UAcc) (s : Seg) (hn : u.cnd = none)
    (hf : (key s.words).head? = some "while" ∨ (key s.words).head? = some "until") :
    (addSeg c u s).stack = (false, u.last.term == .pipe && u.lastFin) :: u.stack ∧
      (addSeg c u s).cnd = some (condStep ⟨(key s.words).head? == some "until", false, .seq, false, readHead s⟩
        (key s.words).tail s.term) ∧
      (addSeg c u s).free = (u.free || badRead (key s.words).tail) ∧ (addSeg c u s).units = u.units := by
  have ho : openers.contains ((key s.words).head?.getD "") = true := by
    rcases hf with h | h <;> simp [h, openers]
  have hu : ((key s.words).head?.getD "" == "until") = ((key s.words).head? == some "until") := by
    rcases hf with h | h <;> simp [h]
  unfold addSeg blockPart condPart
  simp only [hn, ho, hu, ite_true]
  rcases hf with h | h <;> simp [h]

/-- One segment inside an open block, read with no condition open, whose command is no block opener or closer changes
neither the open blocks, nor the free flag, nor the finished units, and opens no condition.

$$\forall c, u, s.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{none} \land f \notin \mathrm{openers} \cup \mathrm{closers} \ \Rightarrow\ v.\mathit{stack} = u.\mathit{stack} \land v.\mathit{free} = u.\mathit{free} \land v.\mathit{units} = u.\mathit{units} \land v.\mathit{cnd} = \mathrm{none},\quad \text{where } f = \mathrm{head}(\mathrm{key}(s.\mathit{words}))\text{ (\texttt{""} if none)},\ v = \mathrm{addSeg}_c(u, s)$$
-/
theorem addSeg_inner (c : Caps) (u : UAcc) (s : Seg) (hs : u.stack ≠ []) (hn : u.cnd = none)
    (ho : openers.contains ((key s.words).head?.getD "") = false)
    (hc : closers.contains ((key s.words).head?.getD "") = false) :
    (addSeg c u s).stack = u.stack ∧ (addSeg c u s).free = u.free ∧ (addSeg c u s).units = u.units ∧
      (addSeg c u s).cnd = none := by
  have hl : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = false := by
    cases h1 : ((key s.words).head?.getD "" == "until") <;> cases h2 : ((key s.words).head?.getD "" == "while") <;>
      simp_all [openers]
  unfold addSeg blockPart condPart
  simp only [hn, ho, hc, hl]
  simp [hs]

/-- A segment starting with `do` that ends an open condition $d$ (its command no block opener or closer, a block open)
sets the innermost block's read flag to $d.\mathit{rd}$, marks the loop free unless $d$ is bounded or exactly a read-loop
head, closes the condition and no unit.

$$\forall c, u, s, d.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{some}(d) \land \mathrm{head}(s.\mathit{words}) = \texttt{do} \land f \notin \mathrm{openers} \cup \mathrm{closers} \ \Rightarrow$$
$$\qquad v.\mathit{stack} = \mathrm{setTop}(d.\mathit{rd}, u.\mathit{stack}) \land v.\mathit{free} = (u.\mathit{free} \lor \lnot(d.\mathit{acc} \lor d.\mathit{exact})) \land v.\mathit{units} = u.\mathit{units} \land v.\mathit{cnd} = \mathrm{none},\quad \text{where } f = \mathrm{head}(\mathrm{key}(s.\mathit{words}))\text{ (\texttt{""} if none)},\ v = \mathrm{addSeg}_c(u, s)$$
-/
theorem addSeg_do (c : Caps) (u : UAcc) (s : Seg) (cd : Cnd) (hs : u.stack ≠ []) (hn : u.cnd = some cd)
    (h0 : s.words.head? = some "do")
    (ho : openers.contains ((key s.words).head?.getD "") = false)
    (hc : closers.contains ((key s.words).head?.getD "") = false) :
    (addSeg c u s).stack = setTop cd.rd u.stack ∧ (addSeg c u s).free = (u.free || !(cd.acc || cd.exact)) ∧
      (addSeg c u s).units = u.units ∧ (addSeg c u s).cnd = none := by
  have hl : ((key s.words).head?.getD "" == "until" || (key s.words).head?.getD "" == "while") = false := by
    cases h1 : ((key s.words).head?.getD "" == "until") <;> cases h2 : ((key s.words).head?.getD "" == "while") <;>
      simp_all [openers]
  obtain ⟨p, r, hpr⟩ := List.exists_cons_of_ne_nil hs
  unfold addSeg blockPart condPart
  simp only [hn, h0, ho, hc, hl]
  simp [hpr, setTop]

/-- The body of a block (segments with no block opener or closer), read with no condition open, changes neither the open
blocks, nor the free flag, nor the finished units, and opens no condition.

$$\forall c, B, u.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{none} \land (\forall s \in B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \ \Rightarrow\ v.\mathit{stack} = u.\mathit{stack} \land v.\mathit{free} = u.\mathit{free} \land v.\mathit{units} = u.\mathit{units} \land v.\mathit{cnd} = \mathrm{none},\quad \text{where } v = \mathrm{foldl}(\mathrm{addSeg}_c, u, B)$$
The head of an empty key is `""`.
-/
theorem addSeg_body (c : Caps) (body : List Seg) (u : UAcc) (hs : u.stack ≠ []) (hn : u.cnd = none)
    (hb : ∀ s ∈ body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false) :
    (body.foldl (addSeg c) u).stack = u.stack ∧ (body.foldl (addSeg c) u).free = u.free ∧
      (body.foldl (addSeg c) u).units = u.units ∧ (body.foldl (addSeg c) u).cnd = none := by
  induction body generalizing u with
  | nil => simp [hn]
  | cons s body ih =>
    have h1 := addSeg_inner c u s hs hn (hb s (by simp)).1 (hb s (by simp)).2
    have := ih (addSeg c u s) (h1.1 ▸ hs) h1.2.2.2 (fun x hx => hb x (by simp [hx]))
    simp only [List.foldl_cons]
    exact ⟨this.1.trans h1.1, this.2.1.trans h1.2.1, this.2.2.1.trans h1.2.2.1, this.2.2.2⟩

/-- `setTop` keeps a non-empty stack non-empty.

$$\forall b, S.\ S \ne [\,] \Rightarrow \mathrm{setTop}(b, S) \ne [\,]$$
-/
theorem setTop_ne_nil (b : Bool) (st : List (Bool × Bool)) (h : st ≠ []) : setTop b st ≠ [] := by
  cases st with
  | nil => exact absurd rfl h
  | cons p r => simp [setTop]

/-- **The loop body does not matter.** After an open condition $d$, a segment $d_0$ starting with `do` and a body $B$
(no block opener or closer in $d_0 :: B$) leave the open blocks, the free flag and the finished units as a function of
$u$ and $d$ alone: whatever the body says (`date`, `deadline`, `$((n+1))`, `[ $i -lt 9 ]`), it can neither bound nor
unbound the loop.

$$\forall c, u, d, d_0, B.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{some}(d) \land \mathrm{head}(d_0.\mathit{words}) = \texttt{do} \land (\forall s \in d_0 :: B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \ \Rightarrow$$
$$\qquad v.\mathit{stack} = \mathrm{setTop}(d.\mathit{rd}, u.\mathit{stack}) \land v.\mathit{free} = (u.\mathit{free} \lor \lnot(d.\mathit{acc} \lor d.\mathit{exact})) \land v.\mathit{units} = u.\mathit{units} \land v.\mathit{cnd} = \mathrm{none},\quad \text{where } v = \mathrm{foldl}(\mathrm{addSeg}_c, u, d_0 :: B)$$
The head of an empty key is `""`.
-/
theorem loop_body (c : Caps) (u : UAcc) (cd : Cnd) (d0 : Seg) (body : List Seg) (hs : u.stack ≠ [])
    (hn : u.cnd = some cd) (h0 : d0.words.head? = some "do")
    (hb : ∀ s ∈ d0 :: body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false) :
    ((d0 :: body).foldl (addSeg c) u).stack = setTop cd.rd u.stack ∧
      ((d0 :: body).foldl (addSeg c) u).free = (u.free || !(cd.acc || cd.exact)) ∧
      ((d0 :: body).foldl (addSeg c) u).units = u.units ∧ ((d0 :: body).foldl (addSeg c) u).cnd = none := by
  have h1 := addSeg_do c u d0 cd hs hn h0 (hb d0 (by simp)).1 (hb d0 (by simp)).2
  have hne : (addSeg c u d0).stack ≠ [] := by rw [h1.1]; exact setTop_ne_nil _ _ hs
  have h2 := addSeg_body c body (addSeg c u d0) hne h1.2.2.2 (fun x hx => hb x (by simp [hx]))
  simp only [List.foldl_cons]
  exact ⟨h2.1.trans h1.1, h2.2.1.trans h1.2.1, h2.2.2.1.trans h1.2.2.1, h2.2.2.2⟩

/-- A `done` segment read with no condition open: it pops the innermost block $(p_1, p_2) :: r$; the free flag gains
$\phi$ (a loop whose condition ran `read` with a stdin not known finite); and the unit closes, carrying that flag, when
no block stays open and the segment ends the and-or list.

$$\forall c, v, d, p, r.\ v.\mathit{cnd} = \mathrm{none} \land v.\mathit{stack} = p :: r \land \mathrm{head}(\mathrm{key}(d.\mathit{words})) = \texttt{done} \ \Rightarrow\ w.\mathit{stack} = r \land w.\mathit{cnd} = \mathrm{none} \land {}$$
$$\qquad \begin{cases} w.\mathit{units} = (d.\mathit{term} = \mathrm{bg},\ \sigma,\ v.\mathit{free} \lor \phi) :: v.\mathit{units} \land \lnot w.\mathit{free} & r = [\,] \land d.\mathit{term} \notin \{\mathrm{andIf}, \mathrm{orElse}, \mathrm{pipe}\} \\ w.\mathit{units} = v.\mathit{units} \land w.\mathit{free} = (v.\mathit{free} \lor \phi) & \text{otherwise} \end{cases},\quad \text{where } \phi \iff p_1 \land \lnot\,\mathrm{getD}(\mathrm{inRedir}_c(d.\mathit{words}), p_2),\ \sigma = v.\mathit{shapes} \mathbin{+\!\!+} \mathrm{shapesOf}_c(d.\mathit{words}),\ w = \mathrm{addSeg}_c(v, d)$$
-/
theorem addSeg_done (c : Caps) (v : UAcc) (d : Seg) (p : Bool × Bool) (r : List (Bool × Bool))
    (hn : v.cnd = none) (hs : v.stack = p :: r) (hd : (key d.words).head? = some "done") :
    (addSeg c v d).stack = r ∧ (addSeg c v d).cnd = none ∧
      (if r = [] ∧ d.term ≠ .andIf ∧ d.term ≠ .orElse ∧ d.term ≠ .pipe then
        (addSeg c v d).units =
          ⟨d.term == .bg, v.shapes ++ shapesOf c d.words, v.free || (p.1 && !(inRedir c d.words).getD p.2)⟩ ::
            v.units ∧ (addSeg c v d).free = false
      else (addSeg c v d).units = v.units ∧
        (addSeg c v d).free = (v.free || (p.1 && !(inRedir c d.words).getD p.2))) := by
  have hk : (key d.words).head?.getD "" = "done" := by simp [hd]
  have ho : openers.contains "done" = false := by decide
  have hc : closers.contains "done" = true := by decide
  unfold addSeg blockPart condPart
  simp only [hk, hn, ho, hc, hs]
  by_cases hr : r = [] ∧ d.term ≠ .andIf ∧ d.term ≠ .orElse ∧ d.term ≠ .pipe
  · obtain ⟨h1, h2, h3, h4⟩ := hr
    simp [h1, h2, h3, h4]
  · simp only [hr, ite_false]
    cases r <;> cases ht : d.term <;> simp_all

/-- **The loop body is irrelevant.** Two loops with the same open condition $d$ and the same `done` segment, but any
two bodies $d_0 :: B$ and $d_0' :: B'$ (each starting with `do`, with no block opener or closer), end with the same open
blocks, the same free flag, no open condition, and finished units that agree on being unbounded.

$$\forall c, u, d, d_0, B, d_0', B', e.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{some}(d) \land \mathrm{head}(d_0.\mathit{words}) = \mathrm{head}(d_0'.\mathit{words}) = \texttt{do} \land (\forall s \in d_0 :: B \mathbin{+\!\!+} d_0' :: B'.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers})$$
$$\qquad \land\ \mathrm{head}(\mathrm{key}(e.\mathit{words})) = \texttt{done} \ \Rightarrow\ v.\mathit{stack} = v'.\mathit{stack} \land v.\mathit{free} = v'.\mathit{free} \land v.\mathit{cnd} = v'.\mathit{cnd} = \mathrm{none} \land [j.\mathit{unbounded} \mid j \in v.\mathit{units}] = [j.\mathit{unbounded} \mid j \in v'.\mathit{units}],\quad \text{where } v = \mathrm{foldl}(\mathrm{addSeg}_c, u, d_0 :: B \mathbin{+\!\!+} [e]),\ v' = \mathrm{foldl}(\mathrm{addSeg}_c, u, d_0' :: B' \mathbin{+\!\!+} [e])$$
-/
theorem body_irrelevant (c : Caps) (u : UAcc) (cd : Cnd) (d0 d0' e : Seg) (body body' : List Seg)
    (hs : u.stack ≠ []) (hn : u.cnd = some cd) (h0 : d0.words.head? = some "do") (h0' : d0'.words.head? = some "do")
    (hb : ∀ s ∈ (d0 :: body) ++ (d0' :: body'), openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false)
    (he : (key e.words).head? = some "done") :
    ((d0 :: body ++ [e]).foldl (addSeg c) u).stack = ((d0' :: body' ++ [e]).foldl (addSeg c) u).stack ∧
      ((d0 :: body ++ [e]).foldl (addSeg c) u).free = ((d0' :: body' ++ [e]).foldl (addSeg c) u).free ∧
      ((d0 :: body ++ [e]).foldl (addSeg c) u).cnd = none ∧ ((d0' :: body' ++ [e]).foldl (addSeg c) u).cnd = none ∧
      ((d0 :: body ++ [e]).foldl (addSeg c) u).units.map (·.unbounded) =
        ((d0' :: body' ++ [e]).foldl (addSeg c) u).units.map (·.unbounded) := by
  have h1 := loop_body c u cd d0 body hs hn h0 (fun x hx => hb x (List.mem_append_left _ hx))
  have h2 := loop_body c u cd d0' body' hs hn h0' (fun x hx => hb x (List.mem_append_right _ hx))
  have hf1 : (d0 :: body ++ [e]).foldl (addSeg c) u = addSeg c ((d0 :: body).foldl (addSeg c) u) e := by
    simp [List.foldl_append]
  have hf2 : (d0' :: body' ++ [e]).foldl (addSeg c) u = addSeg c ((d0' :: body').foldl (addSeg c) u) e := by
    simp [List.foldl_append]
  rw [hf1, hf2]
  generalize (d0 :: body).foldl (addSeg c) u = v at h1
  generalize (d0' :: body').foldl (addSeg c) u = v' at h2
  obtain ⟨p, r, hpr⟩ := List.exists_cons_of_ne_nil (setTop_ne_nil cd.rd u.stack hs)
  have a := addSeg_done c v e p r h1.2.2.2 (h1.1.trans hpr) he
  have b := addSeg_done c v' e p r h2.2.2.2 (h2.1.trans hpr) he
  refine ⟨a.1.trans b.1.symm, ?_, a.2.1, b.2.1, ?_⟩
  · split at a <;> split at b <;> simp_all
  · split at a <;> split at b <;> simp_all

/-- **A read loop with an unbounded input stays unbounded, whatever its condition and body.** If the open condition ran
`read` and the loop's stdin is not known finite (the `done` segment's last stdin redirect is not finite, or it has none
and the loop does not read a finite pipe), then after a `do` segment, any body and `done`, the loop is free, or the unit
it closes is unbounded. A bound test in the condition (`acc`) cannot clear it.

$$\forall c, u, d, b, p, r, d_0, B, e.\ u.\mathit{stack} = (b, p) :: r \land u.\mathit{cnd} = \mathrm{some}(d) \land d.\mathit{rd} \land \mathrm{head}(d_0.\mathit{words}) = \texttt{do} \land (\forall s \in d_0 :: B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers})$$
$$\qquad \land\ \mathrm{head}(\mathrm{key}(e.\mathit{words})) = \texttt{done} \land \lnot\,\mathrm{getD}(\mathrm{inRedir}_c(e.\mathit{words}), p) \ \Rightarrow\ v.\mathit{free} \lor \exists j.\ v.\mathit{units} = j :: u.\mathit{units} \land j.\mathit{unbounded},\quad \text{where } v = \mathrm{foldl}(\mathrm{addSeg}_c, u, d_0 :: B \mathbin{+\!\!+} [e])$$
-/
theorem readLoop_input_free (c : Caps) (u : UAcc) (cd : Cnd) (b p : Bool) (r : List (Bool × Bool))
    (d0 e : Seg) (body : List Seg) (hs : u.stack = (b, p) :: r) (hn : u.cnd = some cd) (hrd : cd.rd = true)
    (h0 : d0.words.head? = some "do")
    (hb : ∀ s ∈ d0 :: body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false)
    (he : (key e.words).head? = some "done") (hin : (inRedir c e.words).getD p = false) :
    ((d0 :: body ++ [e]).foldl (addSeg c) u).free = true ∨
      ∃ j, ((d0 :: body ++ [e]).foldl (addSeg c) u).units = j :: u.units ∧ j.unbounded = true := by
  have h1 := loop_body c u cd d0 body (by simp [hs]) hn h0 hb
  have hf1 : (d0 :: body ++ [e]).foldl (addSeg c) u = addSeg c ((d0 :: body).foldl (addSeg c) u) e := by
    simp [List.foldl_append]
  rw [hf1]
  generalize (d0 :: body).foldl (addSeg c) u = v at h1
  have hvs : v.stack = (true, p) :: r := by rw [h1.1, hs, hrd]; rfl
  have a := addSeg_done c v e (true, p) r h1.2.2.2 hvs he
  split at a
  · exact Or.inr ⟨_, a.2.2.1.trans (by rw [h1.2.2.1]), by simp [hin]⟩
  · exact Or.inl (by rw [a.2.2.2]; simp [hin])

/-- A condition that is neither bounded nor exactly a read-loop head makes its loop free at `do`, whatever follows.

$$\forall c, u, s, d.\ u.\mathit{stack} \ne [\,] \land u.\mathit{cnd} = \mathrm{some}(d) \land \lnot d.\mathit{acc} \land \lnot d.\mathit{exact} \land \mathrm{head}(s.\mathit{words}) = \texttt{do} \land f \notin \mathrm{openers} \cup \mathrm{closers} \ \Rightarrow\ \mathrm{addSeg}_c(u, s).\mathit{free},\quad \text{where } f = \mathrm{head}(\mathrm{key}(s.\mathit{words}))\text{ (\texttt{""} if none)}$$
-/
theorem unbounded_cond_free (c : Caps) (u : UAcc) (s : Seg) (cd : Cnd) (hs : u.stack ≠ []) (hn : u.cnd = some cd)
    (ha : cd.acc = false) (hx : cd.exact = false) (h0 : s.words.head? = some "do")
    (ho : openers.contains ((key s.words).head?.getD "") = false)
    (hc : closers.contains ((key s.words).head?.getD "") = false) :
    (addSeg c u s).free = true := by
  rw [(addSeg_do c u s cd hs hn h0 ho hc).2.1, ha, hx]
  simp

/-- **Read loops: a fact about the classification.** Take a read-loop head $w$ (`while [assignments] read [args]` ended
by `;` or a newline), then a segment $d_0$ starting with `do`, a body $B$, with no block opener or closer in $d_0 :: B$,
and a `done` segment $e$, read with no free loop and no condition open. If the loop's stdin is classified finite (the
`done` segment's last stdin redirect is finite, or it has none and the loop reads a pipe whose producer is classified
finite), the grouping still has no free loop and the unit closed by `done` (if any) is bounded. That such a loop ends in
bash is not proved here: it rests on the premises that `read` fails at the end of a finite input and that the
allowlisted producers (`producerOut`) end.

$$\forall c, u, w, d_0, B, e.\ \lnot u.\mathit{free} \land u.\mathit{cnd} = \mathrm{none} \land \mathrm{readHead}(w) \land \mathrm{head}(d_0.\mathit{words}) = \texttt{do} \land (\forall s \in d_0 :: B.\ \mathrm{head}(\mathrm{key}(s.\mathit{words})) \notin \mathrm{openers} \cup \mathrm{closers}) \land \mathrm{head}(\mathrm{key}(e.\mathit{words})) = \texttt{done}$$
$$\land\ \big(\mathrm{inRedir}_c(e.\mathit{words}) = \mathrm{some}(\top) \lor (\mathrm{inRedir}_c(e.\mathit{words}) = \mathrm{none} \land u.\mathit{last}.\mathit{term} = \mathrm{pipe} \land u.\mathit{lastFin})\big)$$
$$\Rightarrow\ \lnot v.\mathit{free} \land (v.\mathit{units} = u.\mathit{units} \lor \exists j.\ v.\mathit{units} = j :: u.\mathit{units} \land \lnot j.\mathit{unbounded}), \quad v = \mathrm{foldl}(\mathrm{addSeg}_c, u, w :: d_0 :: B \mathbin{+\!\!+} [e])$$
-/
theorem readLoop_bounded (c : Caps) (u : UAcc) (w d0 e : Seg) (body : List Seg)
    (hu : u.free = false) (hn : u.cnd = none) (hw : readHead w = true) (h0 : d0.words.head? = some "do")
    (hb : ∀ s ∈ d0 :: body, openers.contains ((key s.words).head?.getD "") = false ∧
      closers.contains ((key s.words).head?.getD "") = false)
    (he : (key e.words).head? = some "done")
    (hin : inRedir c e.words = some true ∨
      (inRedir c e.words = none ∧ u.last.term = .pipe ∧ u.lastFin = true)) :
    ((w :: d0 :: body ++ [e]).foldl (addSeg c) u).free = false ∧
      (((w :: d0 :: body ++ [e]).foldl (addSeg c) u).units = u.units ∨
        ∃ j, ((w :: d0 :: body ++ [e]).foldl (addSeg c) u).units = j :: u.units ∧ j.unbounded = false) := by
  have hw' : isReadCond (key w.words) = true ∧ w.term = .seq := by
    simp only [readHead, Bool.and_eq_true, beq_iff_eq] at hw
    exact hw
  have hwh : (key w.words).head? = some "while" := isReadCond_head _ hw'.1
  have hpl : plainRead (key w.words).tail = true := by
    simp only [isReadCond, Bool.and_eq_true] at hw'
    exact hw'.1.2
  have hbr : badRead (key w.words).tail = false := by simp [badRead, hpl]
  have h1 := addSeg_loop c u w hn (Or.inl hwh)
  let piped := u.last.term == .pipe && u.lastFin
  let cd := condStep ⟨(key w.words).head? == some "until", false, .seq, false, readHead w⟩ (key w.words).tail w.term
  have hcx : cd.exact = true := by simp [cd, condStep, hw'.2, hw]
  have h2 := loop_body c (addSeg c u w) cd d0 body (by rw [h1.1]; simp) h1.2.1 h0 hb
  have hf : (w :: d0 :: body ++ [e]).foldl (addSeg c) u =
      addSeg c ((d0 :: body).foldl (addSeg c) (addSeg c u w)) e := by
    simp [List.foldl_append]
  rw [hf]
  generalize (d0 :: body).foldl (addSeg c) (addSeg c u w) = v at h2
  have hvs : v.stack = (cd.rd, piped) :: u.stack := by rw [h2.1, h1.1]; rfl
  have hvf : v.free = false := by rw [h2.2.1, h1.2.2.1, hu, hbr, hcx]; simp
  have hphi : (inRedir c e.words).getD piped = true := by
    rcases hin with h | ⟨h1, h2, h3⟩
    · simp [h]
    · simp [h1, piped, h2, h3]
  have a := addSeg_done c v e (cd.rd, piped) u.stack h2.2.2.2 hvs he
  have hu2 : v.units = u.units := h2.2.2.1.trans h1.2.2.2
  split at a
  · refine ⟨a.2.2.2, Or.inr ⟨_, a.2.2.1.trans (by rw [hu2]), ?_⟩⟩
    simp [hvf, hphi]
  · refine ⟨?_, Or.inl (a.2.2.1.trans hu2)⟩
    rw [a.2.2.2, hvf, hphi]; simp

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
#guard readHead ⟨["while", "read", "l"], .seq⟩ && !readHead ⟨["while", "read", "l"], .orElse⟩
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
#guard (parse "a | b || c").map (·.term) == [.pipe, .orElse, .fin]
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

/-! Round 3: the bound comes from the loop condition only; more finite producers; device paths and here-strings. -/

#guard isName "i".toList && isName "_x1".toList && !isName "1x".toList && !isName "$".toList && !isName [] && !isName "#".toList
#guard isDec "10".toList && isDec "0".toList && !isDec "010".toList && !isDec "0x1".toList && !isDec [] && !isDec "-1".toList
#guard opd false "$i" == some (.var "i") && opd false "${i}" == some (.var "i") && opd false "10" == some (.num 10)
#guard opd false "i" == none && opd true "i" == some (.var "i") && opd true "0x0" == none && opd false "010" == none
#guard opd false "$$" == none && opd false "$#" == none && opd false "$?" == none && opd false "$!" == none && opd false "$1" == none
#guard opd false "$(echo 0)" == none && opd false "$((0))" == none && opd false "${x:-0}" == none && opd false "`date`" == none
#guard opd false "${i" == none && opd false "$" == none && opd false "" == none
#guard relOf false "-lt" == some .lt && relOf false "<" == none && relOf true "<=" == some .le && relOf true "-lt" == none
#guard relOf false "-eq" == none && relOf true "==" == none && relOf true "=<" == none
#guard arithToks "i<10".toList == some ["i", "<", "10"] && arithToks " i < 10 ".toList == some ["i", "<", "10"]
#guard arithToks "i < 1 0".toList == some ["i", "<", "1", "0"] && arithToks "i<10,1".toList == none && arithToks [] == some []
#guard atomParse ["[", "$i", "-lt", "10", "]"] == some (.var "i", .lt, .num 10)
#guard atomParse ["[[", "10", "-ge", "${n}", "]]"] == some (.num 10, .ge, .var "n")
#guard atomParse ["((i<10))"] == some (.var "i", .lt, .num 10) && atomParse ["((", "i", "<=", "3", "))"] == some (.var "i", .le, .num 3)
#guard atomParse ["(( i", ">", "0 ))"] == some (.var "i", .gt, .num 0) && atomParse ["[", "$i", "-lt", "10", "]]"] == none
#guard atomParse ["!", "[", "$i", "-lt", "10", "]"] == none && atomParse ["test", "$i", "-lt", "10"] == none
#guard atomParse ["[", "$i", "-lt", "10", "-o", "1", "]"] == none && atomParse ["[", "$i", "<", "10", "]"] == none
#guard atomParse ["[[", "$i", "<", "10", "]]"] == none && atomParse [] == none && atomParse ["true"] == none
-- B: counters both ways, clocks only towards the exit
#guard boundAtom false ["[", "$i", "-lt", "10", "]"] && boundAtom false ["[", "$i", "-ge", "10", "]"] && boundAtom true ["[[", "$i", "-le", "3", "]]"]
#guard boundAtom false ["[", "$SECONDS", "-lt", "60", "]"] && boundAtom false ["[", "60", "-gt", "$SECONDS", "]"]
#guard boundAtom true ["[", "$SECONDS", "-ge", "60", "]"] && boundAtom true ["((SECONDS>600))"] && boundAtom false ["((", "SECONDS", "<", "60", "))"]
#guard !boundAtom false ["[", "$SECONDS", "-ge", "0", "]"] && !boundAtom false ["[", "$SECONDS", "-gt", "5", "]"]
#guard !boundAtom true ["[", "$SECONDS", "-lt", "0", "]"] && !boundAtom false ["((", "SECONDS", ">=", "0", "))"]
#guard !boundAtom false ["[", "0", "-lt", "$SECONDS", "]"] && !boundAtom false ["[", "$EPOCHSECONDS", "-gt", "1", "]"]
-- the round-3 reviewer probes: never a bound
#guard !boundAtom true ["[", "$(gh run list -b ci/x --json status -q '[.[]|select(.status==\"completed\")]|length')", "-ge", "1", "]"]
#guard !boundAtom true ["[", "$(ls out/*.json 2>/dev/null", "-gt", "0", "]"] && !boundAtom false ["[", "$(pgrep -c node)", "-gt", "0", "]"]
#guard !boundAtom false ["[", "$$", "-gt", "0", "]"] && !boundAtom false ["[", "$#", "-ge", "0", "]"] && !boundAtom false ["[", "$((0))", "-lt", "1", "]"]
#guard !boundAtom false ["[", "${x:-0}", "-lt", "1", "]"] && !boundAtom false ["[", "$RANDOM", "-ge", "0", "]"] && !boundAtom false ["[", "$(echo 0)", "-lt", "1", "]"]
#guard !boundAtom false ["((", "i", "<", "10", ",", "1", "))"] && !boundAtom false ["((", "i", "<", "10", "?", "1", ":", "1", "))"]
#guard !boundAtom false ["((", "0x0", "<", "1", "))"] && !boundAtom false ["((", "RANDOM", ">=", "0", "))"] && !boundAtom false ["((i<10,1))"]
#guard !boundAtom false ["[", "1", "-lt", "2", "]"] && !boundAtom false ["[", "$i", "-lt", "$n", "]"] && !boundAtom false ["((1<2))"]
#guard !boundAtom false ["date"] && !boundAtom false ["[", "$SECONDS", "]"] && !boundAtom false [] && !boundAtom false ["((i<<2))"]
#guard !boundAtom false ["[", "`date +%s`", "-lt", "9", "]"] && !boundAtom false ["((", "$i", "<", "9", "))"] && !boundAtom false ["((", "i++", "<", "9", "))"]
#guard comb false .andIf false true && !comb false .orElse false true && comb true .orElse false true
#guard !comb true .andIf false true && !comb false .seq true false && comb true .pipe false true
#guard condStep ⟨false, false, .seq, false, false⟩ ["[", "$i", "-lt", "3", "]"] .andIf == ⟨false, true, .andIf, false, false⟩
#guard condStep ⟨false, true, .andIf, false, true⟩ ["read", "l"] .pipe == ⟨false, true, .andIf, true, true⟩
#guard setTop true [(false, true), (false, false)] == [(true, true), (false, false)] && setTop true [] == []
#guard ansiArg "$\\0" && ansiArg "$\\n" && !ansiArg "$\\" && !ansiArg "$x" && !ansiArg ""
#guard isReadArg "$\\0" && plainRead ["IFS=", "read", "-r", "-d", "$\\0", "f"] && !plainRead ["read", "<", "f"]
#guard readSeg ["!", "read", "l"] && badRead ["!", "read", "l"] && !badRead ["read", "-r", "l"] && !readSeg ["true"]
#guard badRead ["X=$(yes)", "read", "l"] && !readSeg []
#guard isDev "//dev/zero" && isDev "./../../dev/zero" && isDev "dev/zero" && !isDev "/dev/null" && !isDev "f.txt"
#guard badWord "//dev/zero" && !finiteTarget "./../../dev/zero" && !finiteTarget "$(yes)" && finiteTarget "/dev/null"
#guard gitSafe ["-C", "d", "log"] && !gitSafe ["-c", "diff.external=x", "diff"] && !gitSafe ["--exec-path=/x", "log"]
#guard sedLoop ":a" && sedLoop "s/a/b/;:a" && sedLoop "-nf" && !sedLoop "s/a/b/g" && !sedLoop "-n"
#guard awkLoop "{while(1)print}" && awkLoop "{getline x}" && awkLoop "-f" && !awkLoop "{print $1}" && !awkLoop "-F:"
#guard timeoutArg ["-s", "KILL", "60", "x"] == some "60" && timeoutArg ["--foreground", "5", "x"] == some "5"
#guard timeoutArg [] == none && timeoutArg ["-k", "5"] == none
#guard timeoutOk ["60", "tail", "-f", "x"] && timeoutOk ["5m", "x"] && !timeoutOk ["0", "x"] && !timeoutOk ["$n", "x"]
#guard xargsCmd ["-n", "1", "echo"] == ["echo"] && xargsCmd ["-0"] == [] && xargsCmd ["-I", "{}", "cat", "{}"] == ["cat", "{}"]
#guard xargsCmd [] == [] && xargsCmd ["wc"] == ["wc"]
#guard producerOut {} true ["sed", "s/a/b/"] && !producerOut {} false ["sed", "s/a/b/"] && !producerOut {} true ["sed", ":a;N;ba"]
#guard producerOut {} true ["awk", "{print $1}"] && !producerOut {} true ["awk", "BEGIN{while(1)print}"]
#guard !producerOut {} true ["awk", "-f", "x.awk"] && !producerOut {} true ["sed", "-f", "x.sed"]
#guard producerOut {} true ["tr", "a", "b"] && producerOut {} true ["cut", "-d:", "-f1"] && producerOut {} true ["uniq", "-c"]
#guard producerOut {} true ["xargs", "-n", "1", "echo"] && producerOut {} true ["xargs", "cat"] && producerOut {} true ["xargs"]
#guard !producerOut {} false ["xargs", "echo"] && !producerOut {} true ["xargs", "tail", "-f"] && !producerOut {} true ["xargs", "yes"]
#guard producerOut {} true ["gh", "pr", "list"] && producerOut {} true ["gh", "pr", "view", "3"]
#guard !producerOut {} true ["gh", "pr", "checks", "--watch"] && !producerOut {} true ["gh", "run", "watch", "1"]
#guard producerOut {} true ["node", "scripts/x.mjs"] && producerOut {} true ["node", "./scripts/x.mjs", "a"]
#guard !producerOut {} false ["node", "scripts/x.mjs"] && !producerOut {} true ["node", "server.mjs"]
#guard !producerOut {} true ["node", "scripts/../x.mjs"] && !producerOut {} true ["node", "scripts/x.js"]
#guard !producerOut {} true ["pnpm", "-s", "fw", "list"] && !producerOut {} true ["npm", "ls"]
#guard producerOut {} false ["timeout", "60", "tail", "-f", "x"] && !producerOut {} true ["timeout", "0", "yes"]
#guard !producerOut {} true ["git", "-c", "alias.x=!yes", "x"] && !producerOut {} true ["cat", "//dev/zero"]
#guard producerOut {} true ["git", "reflog", "show", "main"] && producerOut {} true ["git", "-C", "d", "reflog"]
#guard hereOk {} "$x" && !hereOk {} "$(yes)" && hereOk {} "$(gh run list --json x)" && !hereOk {} "$(git log | yes)"
#guard !hereOk {} "a $(ls)" && !hereOk {} "`yes`" && !hereOk {} "$(ls"
#guard inRedir {} ["done", "<<<", "$(yes)"] == some false && inRedir {} ["done", "<<<$(yes)"] == some false
#guard inRedir {} ["done", "<<<", "$(git diff --name-only)"] == some true && inRedir {} ["done", "<", "//dev/zero"] == some false
#guard inRedir {} ["done", "<", "./../../dev/zero"] == some false && inRedir {} ["done", "<", "$(yes)"] == some false
#guard decideCmd {} "tail -f log | while read l; do echo $((n+1)); done" == .deny .unboundedLoop
#guard decideCmd {} "yes | while read l; do echo; date; done" == .deny .unboundedLoop
#guard decideCmd {} "while true; do date; sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "until gh run view 1 --exit-status; do date; sleep 120; done" == .deny .unboundedLoop
#guard decideCmd {} "until false; do sleep 1; echo deadline; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ \"$SECONDS\" ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ 1 -lt 2 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while :; do [ $i -lt 5 ] || break; i=$((i+1)); done" == .deny .unboundedLoop
#guard decideCmd {} "tail -f log | while read l && [ $i -lt 9 ]; do i=$((i+1)); done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $i -lt 9 ] || true; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ $i -ge 9 ] && false; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done <<< \"$(yes)\"" == .deny .unboundedLoop
#guard decideCmd {} "while read l; do echo $l; done < //dev/zero" == .deny .unboundedLoop
#guard decideCmd {} "cat ./../../dev/zero | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "pnpm -s fw list | while read l; do echo $l; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $i -lt 3 ]; do while true; do sleep 1; done; done" == .deny .unboundedLoop
#guard decideCmd {} "i=0; while [ ! -s \"$F\" ] && [ $i -lt 55 ]; do sleep 10; i=$((i+1)); done" == .allow
#guard decideCmd {} "i=0; until gh run view 1 --exit-status || [ $i -ge 10 ]; do sleep 30; i=$((i+1)); done" == .allow
#guard decideCmd {} "end=$((SECONDS+60)); while [ $SECONDS -lt $end ]; do sleep 5; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( i < 10 )); do i=$((i+1)); done" == .allow
#guard decideCmd {} "git ls-files | sed 's/a/b/' | while read -r f; do echo $f; done" == .allow
#guard decideCmd {} "git log --oneline | awk '{print $1}' | while read h; do echo $h; done" == .allow
#guard decideCmd {} "find . -name '*.json' -print0 | while IFS= read -r -d $'\\0' f; do echo \"$f\"; done" == .allow
#guard decideCmd {} "ls | xargs -n 1 echo | while read l; do echo $l; done" == .allow
#guard decideCmd {} "gh pr list --json number -q '.[].number' | while read n; do gh pr view $n; done" == .allow
#guard decideCmd {} "node scripts/list.mjs | while read l; do echo $l; done" == .allow
#guard decideCmd {} "while read -r f; do echo $f; done <<< \"$(git diff --name-only)\"" == .allow
#guard decideCmd {} "timeout 600 bash -c 'until gh run view 1 --exit-status; do sleep 30; done'" == .allow

/-! Round 4: the bound grammar B (`atomParse`, `relOk`); every round-3 reviewer probe is denied. -/

#guard (condFold ⟨false, false, .seq, false, false⟩ [(["[", "$i", "-lt", "3", "]"], .andIf), (["true"], .seq)]).acc
#guard !(condFold ⟨false, false, .seq, false, false⟩ [(["[", "$i", "-lt", "3", "]"], .orElse), (["true"], .seq)]).acc
#guard (condFold ⟨true, false, .seq, false, false⟩ [(["gh", "run", "view"], .orElse), (["[", "$i", "-ge", "9", "]"], .seq)]).acc
#guard dollarParen "a$(b".toList && dollarParen "$((0))".toList && !dollarParen "$x(".toList && !dollarParen [] && !dollarParen "(($".toList
#guard zeroArg "0" && zeroArg "-n0" && zeroArg "-t00" && zeroArg "00" && !zeroArg "-n1" && !zeroArg "-r" && !zeroArg "x0" && !zeroArg "10"
#guard !isReadArg "0" && !isReadArg "-n0" && isReadArg "-n" && isReadArg "1" && isReadArg "x0"
#guard outRedir "2>/dev/null" && outRedir ">/dev/stderr" && outRedir "&>/dev/null" && outRedir "1>>f" && !outRedir "</dev/zero" && !outRedir "f"
#guard !isDev "2>/dev/null" && !isDev ">/dev/tty" && isDev "</dev/zero" && isDev "/dev/stdin"
#guard gitAfter ["-C", "d", "worktree", "list"] == ["list"] && gitAfter ["--no-pager", "stash", "list"] == ["list"] && gitAfter [] == []
#guard gitReadOnly "worktree" ["list", "--porcelain"] && !gitReadOnly "worktree" ["add", "x"] && gitReadOnly "stash" ["list"]
#guard !gitReadOnly "stash" [] && gitReadOnly "remote" [] && gitReadOnly "remote" ["-v"] && !gitReadOnly "remote" ["add", "o", "u"]
#guard gitReadOnly "config" ["--list"] && gitReadOnly "config" ["--get", "user.name"] && !gitReadOnly "config" ["-l", "--edit"]
#guard !gitReadOnly "config" ["user.name", "x"] && gitReadOnly "log" [] && !gitReadOnly "fetch" []
#guard parse "whi\\\nle true; do sleep 1; done" == parse "while true; do sleep 1; done"
-- the round-3 reviewer probes, end to end: deny
#guard decideCmd {} "until [ \"$(gh run list -b ci/x --json status -q '[.[]|select(.status==\"completed\")]|length')\" -ge 1 ]; do sleep 120; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ \"$(ls out/*.json 2>/dev/null | wc -l)\" -gt 0 ]; do sleep 30; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ \"$(pgrep -c node)\" -gt 0 ]; do sleep 5; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ $(curl -s -o /dev/null -w '%{http_code}' localhost:3000) -ge 200 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $$ -gt 0 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $# -ge 0 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $((0)) -lt 1 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ \"${x:-0}\" -lt 1 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $RANDOM -ge 0 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ \"$(echo 0)\" -lt 1 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ `echo 0` -lt 1 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $SECONDS -ge 0 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $SECONDS -gt 5 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "until [ $SECONDS -lt 0 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( SECONDS >= 0 )); do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while ! [ $SECONDS -lt 60 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while true && ! [ $SECONDS -ge 60 ]; do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( i < 10 , 1 )); do sleep 1; ((i++)); done" == .deny .unboundedLoop
#guard decideCmd {} "while (( i < 10 ? 1 : 1 )); do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( 0x0 < 1 )); do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( RANDOM >= 0 )); do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while (( 010 < i )); do sleep 1; done" == .deny .unboundedLoop
#guard decideCmd {} "while [ $i -lt $n ]; do i=$((i+1)); done" == .deny .unboundedLoop
#guard decideCmd {} "while [[ $i < 10 ]]; do i=$((i+1)); done" == .deny .unboundedLoop
#guard decideCmd {} "while read -n 0 x; do :; done < f.txt" == .deny .unboundedLoop
#guard decideCmd {} "while read -N 0 x; do :; done < f.txt" == .deny .unboundedLoop
#guard decideCmd {} "while read -t 0; do :; done < f.txt" == .deny .unboundedLoop
#guard decideCmd {} "whi\\\nle true; do sleep 1; done" == .deny .unboundedLoop
-- B, allowed
#guard decideCmd {} "while [ $SECONDS -lt 600 ]; do sleep 5; done" == .allow
#guard decideCmd {} "until [ \"$SECONDS\" -ge 600 ] || gh run view 1 --exit-status; do sleep 30; done" == .allow
#guard decideCmd {} "i=0; while (( i < 10 )); do i=$((i+1)); done" == .allow
#guard decideCmd {} "until (( SECONDS > 600 )); do sleep 5; done" == .allow
#guard decideCmd {} "while [[ ${i} -le 3 ]]; do i=$((i+1)); done" == .allow
#guard decideCmd {} "while read -t 5 -r l; do echo $l; done < f.txt" == .allow
#guard decideCmd {} "git worktree list --porcelain | awk '/^worktree /{print $2}' | while read p; do echo $p; done" == .allow
#guard decideCmd {} "ls -t a*.jsonl 2>/dev/null | head -3 | while read f; do echo $f; done" == .allow
#guard decideCmd {} "git stash list | while read s; do echo $s; done" == .allow

end Fw.Ops.Wait
