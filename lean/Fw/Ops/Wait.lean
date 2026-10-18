/-!
# Wait guard (PLAN §8.3 `PreToolUse` matcher `Bash`; mistake class `c-orphan-wait`)

Two things, both pure.

**1. Waits are bounded and owned.** A wait is an owner plus a deadline. `waitOk` admits it only with a
non-empty owner and a deadline in `1..cap`; `waitEnd` is when the wait stops whatever the condition
does. Proved: `wait_bounded` (every admitted wait stops by its deadline, which is `≤ cap`, and has an
owner). Handback: `handbackOk` allows an agent to hand back only when every background task it
started has ended; proved `handback_no_open_bg`.

**2. A foreground `Bash` call must not start a long-running process with `&`.** The command is parsed
(`parse`) into segments split at `; \n | || && &`, grouped into *units* (an and-or list or a whole
`until/while/for/if/case ... done/fi/esac` compound, the thing a trailing `&` backgrounds). A unit is
*long* when it holds one of the `Shape`s: `fw watch`, an `until`/`while` loop, a server or watcher, a
`tail -f`, or a `sleep` longer than `caps.maxSleepSec`. `decide` refuses a backgrounded long unit
(`bgLong`: use the tool's `run_in_background`, which has an owner and a stop) and any `until`/`while`
loop with no bound (`unboundedLoop`: no `timeout` wrapper and no counter / clock test).

The shapes are a small documented set, tested by goldens; the parse is approximate on purpose.
Known blind spots (shadow-logged, not claimed): code inside `$( )`, `( )` or `sh -c '...'` strings,
here-documents, and aliases.
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

/-- How a segment ends: `;` or newline (`seq`), `&&`/`||`/`|` (`join`: the same and-or list or pipeline goes on),
`&` (`bg`), or the end of the text.

$$\mathrm{Term} = \mathrm{seq} \mid \mathrm{join} \mid \mathrm{bg} \mid \mathrm{end}$$
-/
inductive Term where
  | seq | join | bg | fin
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
(reversed) and the finished segments (reversed).

$$\mathrm{Acc} = \mathbb{N} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Char} \times \mathrm{Char}^{*} \times \mathrm{String}^{*} \times \mathrm{Seg}^{*}, \quad a = (\mathit{quote}, \mathit{esc}, \mathit{pend}, \mathit{comment}, \mathit{prev}, \mathit{word}, \mathit{words}, \mathit{segs}), \quad \{\} = (0, \bot, \bot, \bot, \texttt{' '}, [\,], [\,], [\,])$$
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

/-- Finish the current word (if any).

$$\mathrm{flushWord}(a) = \begin{cases} a & a.\mathit{word} = [\,] \\ a[\mathit{words} := \mathrm{str}(\mathrm{rev}(a.\mathit{word})) :: a.\mathit{words},\ \mathit{word} := [\,]] & \text{otherwise} \end{cases}$$
-/
def flushWord (a : Acc) : Acc :=
  if a.word.isEmpty then a else { a with words := String.ofList a.word.reverse :: a.words, word := [] }

/-- Finish the current segment with a terminator. An empty segment is dropped (so `a &&⏎ b` stays one list), except a
`bg` or `fin` terminator on an empty segment is dropped too: there is nothing to background.

$$\mathrm{endSeg}(a, t) = \begin{cases} a' & a'.\mathit{words} = [\,] \\ a'[\mathit{words} := [\,],\ \mathit{segs} := (\mathrm{rev}(a'.\mathit{words}), t) :: a'.\mathit{segs}] & \text{otherwise} \end{cases}, \quad a' = \mathrm{flushWord}(a)$$
-/
def endSeg (a : Acc) (t : Term) : Acc :=
  let a := flushWord a
  if a.words.isEmpty then a
  else { a with words := [], segs := ⟨a.words.reverse, t⟩ :: a.segs }

/-- Add a character to the current word.

$$\mathrm{push}(a, c) = a[\mathit{word} := c :: a.\mathit{word}]$$
-/
def push (a : Acc) (c : Char) : Acc := { a with word := c :: a.word }

/-- Process one character that is not a pending `&` resolver (the first matching row applies; ⏎ is newline).

$$\mathrm{stepPlain}(a, c) = \begin{cases} \mathrm{endSeg}(a[\mathit{comment} := \bot], \mathrm{seq}) & a.\mathit{comment},\ c = \text{⏎} \\ a & a.\mathit{comment},\ c \ne \text{⏎} \\ \mathrm{push}(a[\mathit{esc} := \bot], c) & a.\mathit{esc} \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 1,\ c = \texttt{'} \\ \mathrm{push}(a, c) & a.\mathit{quote} = 1 \\ a[\mathit{quote} := 0] & a.\mathit{quote} = 2,\ c = \texttt{"} \\ a[\mathit{esc} := \top] & a.\mathit{quote} = 2,\ c = \backslash \\ \mathrm{push}(a, c) & a.\mathit{quote} = 2 \\ a[\mathit{quote} := 1] & c = \texttt{'} \\ a[\mathit{quote} := 2] & c = \texttt{"} \\ a[\mathit{esc} := \top] & c = \backslash \\ \mathrm{flushWord}(a) & c \in \{\text{space}, \text{tab}, \text{CR}\} \\ \mathrm{endSeg}(a, \mathrm{seq}) & c \in \{\text{⏎}, \texttt{;}\} \\ \mathrm{endSeg}(a, \mathrm{join}) & c = \texttt{|} \\ a[\mathit{comment} := \top] & c = \texttt{\#},\ a.\mathit{word} = [\,] \\ \mathrm{push}(a, c) & c = \texttt{\&},\ a.\mathit{prev} \in \{\texttt{>}, \texttt{<}\} \\ a[\mathit{pend} := \top] & c = \texttt{\&} \\ \mathrm{push}(a, c) & \text{otherwise} \end{cases}$$
-/
def stepPlain (a : Acc) (c : Char) : Acc :=
  if a.comment then
    if c == '\n' then endSeg { a with comment := false } .seq else a
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
  else if c == '\n' || c == ';' then endSeg a .seq
  else if c == '|' then endSeg a .join
  else if c == '#' && a.word.isEmpty then { a with comment := true }
  else if c == '&' then
    if a.prev == '>' || a.prev == '<' then push a c else { a with pend := true }
  else push a c

/-- One scanner step: a pending `&` is resolved by the next character (`&&` is a join, `&>` stays in the word,
anything else makes the `&` a background operator), then the character is processed.

$$\mathrm{step}(a, c) = b[\mathit{prev} := c], \quad b = \begin{cases} \mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{join}) & a.\mathit{pend},\ c = \texttt{\&} \\ \mathrm{stepPlain}(\mathrm{push}(a[\mathit{pend} := \bot], \texttt{\&}), c) & a.\mathit{pend},\ c = \texttt{>} \\ \mathrm{stepPlain}(\mathrm{endSeg}(a[\mathit{pend} := \bot], \mathrm{bg}), c) & a.\mathit{pend},\ c \notin \{\texttt{\&}, \texttt{>}\} \\ \mathrm{stepPlain}(a, c) & \lnot a.\mathit{pend} \end{cases}$$
-/
def step (a : Acc) (c : Char) : Acc :=
  let a' :=
    if a.pend then
      if c == '&' then (endSeg { a with pend := false } .join, true)
      else if c == '>' then (push { a with pend := false } '&', false)
      else (endSeg { a with pend := false } .bg, false)
    else (a, false)
  if a'.2 then { a'.1 with prev := c }
  else { stepPlain a'.1 c with prev := c }

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

/-- The words that bound a loop on their own: a clock, a counter or an arithmetic test.

$$\mathrm{boundWords} = [\texttt{-lt}, \texttt{-le}, \texttt{-gt}, \texttt{-ge}, \texttt{date}, \texttt{SECONDS}, \texttt{\$SECONDS}, \texttt{deadline}, \texttt{DEADLINE}, \texttt{seq}]$$
-/
def boundWords : List String := ["-lt", "-le", "-gt", "-ge", "date", "SECONDS", "$SECONDS", "deadline", "DEADLINE", "seq"]

/-- Does a word bound a loop (also `$((...))` and `SECONDS=`-style words)?

$$\mathrm{isBoundWord}(w) \iff w \in \mathrm{boundWords} \lor w \text{ starts with one of } \texttt{\$((},\ \texttt{((},\ \texttt{SECONDS},\ \texttt{deadline=},\ \texttt{DEADLINE=}$$
-/
def isBoundWord (w : String) : Bool :=
  boundWords.contains w || w.startsWith "$((" || w.startsWith "((" || w.startsWith "SECONDS" || w.startsWith "deadline=" || w.startsWith "DEADLINE="

/-- Facts about one unit (the thing a trailing `&` backgrounds).

$$\mathrm{Job} = (\mathit{bg} \in \mathbb{B},\ \mathit{shapes} \in \mathrm{Shape}^{*},\ \mathit{unbounded} \in \mathbb{B})$$
-/
structure Job where
  bg        : Bool
  shapes    : List Shape
  unbounded : Bool
deriving DecidableEq, Repr

/-- The running state of the unit grouping: block depth and the facts gathered so far.

$$\mathrm{UAcc} = \mathbb{N} \times \mathrm{Shape}^{*} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathbb{B} \times \mathrm{Job}^{*}, \quad u = (\mathit{depth}, \mathit{shapes}, \mathit{loop}, \mathit{bound}, \mathit{wrapped}, \mathit{fresh}, \mathit{units}), \quad \{\} = (0, [\,], \bot, \bot, \bot, \top, [\,])$$
-/
structure UAcc where
  depth   : Nat := 0
  shapes  : List Shape := []
  loop    : Bool := false
  bound   : Bool := false
  wrapped : Bool := false
  fresh   : Bool := true
  units   : List Job := []

/-- Add one segment to the grouping; close the unit when the block depth is 0 and the segment ends the list. Here
$f$ is the first word of $s$ (`""` if none), $\ell \iff f \in \{\texttt{until}, \texttt{while}\}$, $[P]$ is 1 if $P$ else 0,
and $\dot-$ is truncated subtraction.

$$\mathrm{addSeg}_c(u, s) = \begin{cases} (0, [\,], \bot, \bot, \bot, \top,\ (s.\mathit{term} = \mathrm{bg},\ u'.\mathit{shapes},\ u'.\mathit{loop} \land \lnot(u'.\mathit{bound} \lor u'.\mathit{wrapped})) :: u'.\mathit{units}) & d = 0 \land s.\mathit{term} \ne \mathrm{join} \\ u' & \text{otherwise} \end{cases}, \quad d = (u.\mathit{depth} + [f \in \mathrm{openers}]) \mathbin{\dot-} [f \in \mathrm{closers}], \quad u' = u[\mathit{depth} := d,\ \mathit{shapes} := u.\mathit{shapes} \mathbin{+\!\!+} [\mathrm{loop} \mid \ell] \mathbin{+\!\!+} \mathrm{shapesOf}_c(s.\mathit{words}),\ \mathit{loop} := u.\mathit{loop} \lor \ell,\ \mathit{bound} := u.\mathit{bound} \lor \exists x \in s.\mathit{words}.\ \mathrm{isBoundWord}(x),\ \mathit{wrapped} := (u.\mathit{fresh}\ ?\ f \in \{\texttt{timeout}, \texttt{gtimeout}\} : u.\mathit{wrapped}),\ \mathit{fresh} := \bot]$$
-/
def addSeg (c : Caps) (u : UAcc) (s : Seg) : UAcc :=
  let f := s.words.head?.getD ""
  let isLoop := f == "until" || f == "while"
  let depth := (if openers.contains f then u.depth + 1 else u.depth) - (if closers.contains f then 1 else 0)
  let wrapped := if u.fresh then (f == "timeout" || f == "gtimeout") else u.wrapped
  let sh := (if isLoop then [Shape.loop] else []) ++ shapesOf c s.words
  let u := { u with depth, shapes := u.shapes ++ sh, loop := u.loop || isLoop,
                    bound := u.bound || s.words.any isBoundWord, wrapped, fresh := false }
  if depth == 0 && s.term != .join then
    { depth := 0, units := ⟨s.term == .bg, u.shapes, u.loop && !(u.bound || u.wrapped)⟩ :: u.units }
  else u

/-- The units of a command (a trailing open unit is closed at the end).

$$\mathrm{units}: \mathrm{String} \to \mathrm{Job}^{*}$$
-/
def units (c : Caps) (cmd : String) : List Job :=
  let u := (parse cmd).foldl (addSeg c) {}
  let u := if u.fresh then u else { u with units := ⟨false, u.shapes, u.loop && !(u.bound || u.wrapped)⟩ :: u.units }
  u.units.reverse

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

end Fw.Ops.Wait
