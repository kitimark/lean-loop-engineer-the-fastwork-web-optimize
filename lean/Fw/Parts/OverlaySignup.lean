import Fw.Parts.Bezier
/-!
# overlays.signup: the waitlist sign-up dialog (wave 2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/chunks/D313Dngs.js`
  * 1927-1933 (`Mn`): the unit direction from the viewport centre to the trigger, times 16, rounded;
  * 1985-2030: on open, remember the focused element, set `--dialog-dir-x/y` from it (or `(0, 16)` when focus is on
    the body), `showModal()`; on close, `close()` and give the focus back; `Escape` handler; body overflow hidden;
  * 2031-2038 (`k`, `j`): backdrop click closes for purpose `info`; the `cancel` event is always prevented and closes
    only when no other layer is open and the purpose is not `required`.
* `nodes/2.DyWL8TcE.js`
  * 3910-3912 (`iD`): the form is valid iff the trimmed name is non-empty and the trimmed email matches
    `^[^\s@]+@[^\s@]+\.[^\s@]+$`;
  * 7201-7270 (`WO`): every close goes through `onBeforeClose`, which here refuses while a request is running;
  * 13265-13296 and 13330-13400 (`gN`): submit, error, success flow.
* `assets/DialogHeader.Qcgwm6ST.css` 698-714: the enter animation (`0.4s`, the design system's `--ease-standard`,
  from `opacity 0`, `translate(dir)`, `scale(.95)`); none under `prefers-reduced-motion: reduce`.

All values `Rat`. No `Float`.
-/
namespace Fw.Parts.OverlaySignup
open Fw.Parts.Bezier

/-! ## Constants -/

/-- Enter animation length in ms (`--duration-medium-max`, 0.4s). $$T = 400$$ How long the dialog takes to appear. -/
def enterMs : Rat := 400

/-- Start scale of the enter animation (CSS `scale(0.95)`). $$k_0 = 0.95 = \tfrac{19}{20}$$ -/
def scale0 : Rat := 19 / 20

/-- Length of the direction vector, px (`Mn`'s default argument). $$L = 16$$ -/
def dirLength : Rat := 16

/-! ## The direction of the enter animation -/

/-- The sign-safe test $c\sqrt{d} \le 32x$ (for the half-integer thresholds of the rounding), decided on squares.

$$c\sqrt{d} \le 32x \iff \begin{cases} \top & c \le 0 \le x \\ \bot & x < 0 < c \\ c^2 d \le 1024\,x^2 & c > 0,\ x \ge 0 \\ c^2 d \ge 1024\,x^2 & c \le 0,\ x < 0\end{cases}$$ -/
def leSqrt (c : Int) (x d : Rat) : Bool :=
  if c ≤ 0 then
    if 0 ≤ x then true else decide ((c : Rat) * c * d ≥ 1024 * x * x)
  else if x < 0 then false else decide ((c : Rat) * c * d ≤ 1024 * x * x)

/-- One component of `Mn`: $\operatorname{round}(16\,x/\sqrt{d})$ with $d = x^2 + y^2$, JS `Math.round` (ties go up).

$$\operatorname{comp}(x, d) = \max\{k \in [-16, 16] : (2k - 1)\sqrt{d} \le 32x\} = \lfloor 16x/\sqrt{d} + \tfrac12 \rfloor,\quad d > 0$$

Exact, with no square root. -/
def comp (x d : Rat) : Int :=
  (List.range 33).foldl (fun (acc : Int) (i : Nat) =>
    let k : Int := (i : Int) - 16
    if leSqrt (2 * k - 1) x d then k else acc) (-16)

/-- The direction vector from the viewport centre to the trigger centre (offsets $x, y$), `Mn(e, 16)`.

$$\operatorname{dir}(x, y) = \begin{cases} (0, 0) & x^2 + y^2 = 0 \\ (\operatorname{comp}(x, d), \operatorname{comp}(y, d)) & d = x^2 + y^2 > 0\end{cases}$$

(`Math.sqrt(...) || 1` makes the zero vector give $(0,0)$). -/
def dir (x y : Rat) : Int × Int :=
  let d := x * x + y * y
  if d == 0 then (0, 0) else (comp x d, comp y d)

/-- The direction used when the dialog opens (JS 1995-2000): from the trigger when something other than the body has
focus, else $(0, 16)$.

$$\operatorname{openDir}(\text{focused}) = \begin{cases} \operatorname{dir}(x, y) & \text{some trigger offset } (x, y) \\ (0, 16) & \text{none}\end{cases}$$ -/
def openDir (trigger : Option (Rat × Rat)) : Int × Int :=
  match trigger with
  | some (x, y) => dir x y
  | none => (0, 16)

#guard dir 0 0 == (0, 0)
#guard dir 0 1 == (0, 16)
#guard dir 1 0 == (16, 0)
#guard dir (-1) 0 == (-16, 0)
#guard dir 3 4 == (10, 13)
#guard dir 100 (-100) == (11, -11)
#guard openDir none == (0, 16)

/-- Each component is at most 16 in absolute value.

$$\forall x, y:\ |\operatorname{dir}(x,y)_i| \le 16$$ -/
theorem comp_bounds (x d : Rat) : -16 ≤ comp x d ∧ comp x d ≤ 16 := by
  unfold comp
  have key : ∀ (l : List Nat) (acc : Int), -16 ≤ acc → acc ≤ 16 → (∀ i ∈ l, i < 33) →
      -16 ≤ l.foldl (fun (acc : Int) (i : Nat) => if leSqrt (2 * ((i : Int) - 16) - 1) x d then (i : Int) - 16 else acc) acc ∧
      l.foldl (fun (acc : Int) (i : Nat) => if leSqrt (2 * ((i : Int) - 16) - 1) x d then (i : Int) - 16 else acc) acc ≤ 16 := by
    intro l
    induction l with
    | nil => intro acc h1 h2 _; exact ⟨h1, h2⟩
    | cons i t ih =>
      intro acc h1 h2 hl
      have hi : i < 33 := hl i (by simp)
      simp only [List.foldl_cons]
      apply ih
      · split <;> omega
      · split <;> omega
      · intro j hj; exact hl j (by simp [hj])
  exact key (List.range 33) (-16) (by omega) (by omega) (fun i hi => by simpa using hi)

/-- The zero vector gives no direction. $$\operatorname{dir}(0, 0) = (0, 0)$$ -/
theorem dir_zero : dir 0 0 = (0, 0) := by
  have h : ((0 : Rat) * 0 + 0 * 0 == 0) = true := by rw [beq_iff_eq]; grind
  unfold dir
  simp only [h]
  rfl

/-- With no trigger the dialog rises from below. $$\operatorname{openDir}(\bot) = (0, 16)$$ -/
theorem openDir_none : openDir none = (0, 16) := rfl

/-! ## The enter animation -/

/-- The four animated values $e$ ms after the dialog opens, as (opacity, translate x, translate y, scale).

$$p = \operatorname{ease}_{\text{standard}}(e/400),\quad \text{frame}(e) = (p,\ (1-p)\,d_x,\ (1-p)\,d_y,\ k_0 + (1 - k_0)\,p)$$

Reduced motion has no animation, so the frame is the end frame at any time. -/
structure Frame where
  opacity : Rat
  tx : Rat
  ty : Rat
  scale : Rat
deriving Repr, BEq, DecidableEq

/-- Animation progress. $$p(e, r) = \begin{cases} 1 & r \\ \operatorname{ease}_{\text{standard}}(e / 400) & \lnot r\end{cases}$$ -/
def progress (elapsed : Rat) (reduced : Bool) : Rat :=
  if reduced then 1 else ease easeStandard (elapsed / enterMs)

/-- The frame at elapsed time $e$ for direction $(d_x, d_y)$ (keyframes `0%`/`to` with the standard easing).

$$\text{frame}(e) = (p,\ (1-p)\,d_x,\ (1-p)\,d_y,\ k_0 + (1-k_0)\,p)$$ -/
def frame (dx dy : Int) (elapsed : Rat) (reduced : Bool) : Frame :=
  let p := progress elapsed reduced
  ⟨p, (1 - p) * dx, (1 - p) * dy, scale0 + (1 - scale0) * p⟩

/-- At the start: transparent, offset by the direction, scaled to 0.95.
$$\text{frame}(0) = (0,\ d_x,\ d_y,\ \tfrac{19}{20})$$ -/
theorem frame_start (dx dy : Int) : frame dx dy 0 false = ⟨0, dx, dy, 19 / 20⟩ := by
  have z : (0 : Rat) / enterMs = 0 := by unfold enterMs; grind
  have h : progress 0 false = 0 := by simp [progress, z, ease_zero]
  unfold frame
  rw [h]
  unfold scale0
  simp only [Frame.mk.injEq]
  grind

/-- After 400 ms: opaque, in place, full size. $$e \ge 400 \Rightarrow \text{frame}(e) = (1, 0, 0, 1)$$ -/
theorem frame_end (dx dy : Int) (e : Rat) (he : 400 ≤ e) : frame dx dy e false = ⟨1, 0, 0, 1⟩ := by
  have h1 : 1 ≤ e / enterMs := by
    have : e / enterMs = e * (1 / 400) := by unfold enterMs; grind
    grind
  have h : progress e false = 1 := by simp [progress, ease_ge_one _ _ h1]
  unfold frame
  rw [h]
  unfold scale0
  simp only [Frame.mk.injEq]
  grind

/-- Under reduced motion the dialog is at its end frame at once. $$\forall e:\ \text{frame}_{r = \top}(e) = (1,0,0,1)$$ -/
theorem frame_reduced (dx dy : Int) (e : Rat) : frame dx dy e true = ⟨1, 0, 0, 1⟩ := by
  unfold frame progress
  simp only [ite_true]
  unfold scale0
  simp only [Frame.mk.injEq]
  grind

/-- The opacity stays in $[0,1]$. $$\forall e, r:\ 0 \le \operatorname{opacity}(\text{frame}(e)) \le 1$$ -/
theorem opacity_mem (dx dy : Int) (e : Rat) (r : Bool) :
    0 ≤ (frame dx dy e r).opacity ∧ (frame dx dy e r).opacity ≤ 1 := by
  have e : (frame dx dy e r).opacity = progress e r := rfl
  rw [e]
  unfold progress
  split
  · constructor <;> decide
  · exact ease_mem _ _ (by decide) (by decide) (by decide) (by decide)

/-! ## Closing -/

/-- Why a close is asked for. $$\text{escape} \mid \text{backdrop} \mid \text{cancel}$$ -/
inductive Source where
  | escape
  | backdrop
  | cancel
deriving Repr, BEq, DecidableEq

/-- The dialog's purpose. $$\text{info} \mid \text{form} \mid \text{required}$$ The signup is `info`. -/
inductive Purpose where
  | info
  | form
  | required
deriving Repr, BEq, DecidableEq

/-- What the handler does: whether it calls `preventDefault()` and whether it asks to close. $$(\mathit{prevent}, \mathit{close})$$ -/
structure Reaction where
  prevent : Bool
  close : Bool
deriving Repr, BEq, DecidableEq

/-- The reaction to a close source (D313Dngs 2011-2038). The inputs: the purpose, whether the event target is the dialog itself
(backdrop and cancel), whether the key event is a composition (or keyCode 229), and whether another layer is open.

$$\operatorname{react}(\mathit{src}, p, \mathit{self}, \mathit{comp}, \mathit{layer}) = \begin{cases}
(\bot,\bot) & \text{escape},\ \mathit{comp} \lor \mathit{layer} \\
(\top,\ p \ne \text{required}) & \text{escape, otherwise} \\
(\bot,\ \mathit{self} \land p = \text{info}) & \text{backdrop} \\
(\mathit{self},\ \mathit{self} \land \lnot\mathit{layer} \land p \ne \text{required}) & \text{cancel}\end{cases}$$ -/
def react (src : Source) (p : Purpose) (self composing layered : Bool) : Reaction :=
  match src with
  | .escape => if composing || layered then ⟨false, false⟩ else ⟨true, p != .required⟩
  | .backdrop => ⟨false, self && p == .info⟩
  | .cancel => if self then ⟨true, !layered && p != .required⟩ else ⟨false, false⟩

/-- Whether a requested close goes through: `onBeforeClose` is `!submitting` (JS 13307).

$$\operatorname{allowed}(\mathit{submitting}) = \lnot\mathit{submitting}$$ -/
def closeAllowed (submitting : Bool) : Bool := !submitting

/-- The dialog element syncs with the `isOpen` prop (D313Dngs 1999-2008).

$$\operatorname{sync}(\mathit{isOpen}, \mathit{domOpen}) = \begin{cases} \text{showModal} & \mathit{isOpen} \land \lnot\mathit{domOpen} \\ \text{close} & \lnot\mathit{isOpen} \land \mathit{domOpen} \\ \text{none} & \text{otherwise}\end{cases}$$ -/
inductive Sync where
  | showModal
  | close
  | none
deriving Repr, BEq, DecidableEq

/-- See `Sync`. $$\operatorname{sync}(\mathit{isOpen}, \mathit{domOpen})$$ The element operation for a prop value. -/
def sync (isOpen domOpen : Bool) : Sync :=
  if isOpen then (if domOpen then .none else .showModal) else (if domOpen then .close else .none)

#guard react .escape .info true false false == ⟨true, true⟩
#guard react .escape .required true false false == ⟨true, false⟩
#guard react .escape .info true true false == ⟨false, false⟩
#guard react .backdrop .info true false false == ⟨false, true⟩
#guard react .backdrop .form true false false == ⟨false, false⟩
#guard react .cancel .info true false false == ⟨true, true⟩
#guard react .cancel .info true false true == ⟨true, false⟩

/-- A required dialog never closes from the keyboard or backdrop. $$p = \text{required} \Rightarrow \lnot\mathit{close}$$ for escape, backdrop and cancel. -/
theorem required_never_closes (src : Source) (self comp layer : Bool) :
    (react src .required self comp layer).close = false := by
  cases src <;> cases self <;> cases comp <;> cases layer <;> decide

/-- The signup (purpose info) closes on Escape unless composing or another layer is open.
$$\lnot\mathit{comp} \land \lnot\mathit{layer} \Rightarrow \operatorname{react}(\text{escape}, \text{info}) = (\top, \top)$$ -/
theorem escape_closes_info : react .escape .info false false false = ⟨true, true⟩ := by decide

/-- No close goes through while a request runs. $$\mathit{submitting} \Rightarrow \lnot\operatorname{allowed}$$ -/
theorem no_close_while_submitting : closeAllowed true = false := rfl

/-- Props and element agree after a sync. $$\operatorname{sync}(b, b) = \text{none}$$ -/
theorem sync_idem (b : Bool) : sync b b = .none := by cases b <;> rfl

/-! ## The form -/

/-- JavaScript whitespace (`\s` and `String.prototype.trim`): tab, LF, VT, FF, CR, space, NBSP, U+1680, U+2000-200A,
U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.

$$\operatorname{ws}(c) \iff c \in \{9..13, 32, 160, 5760, 8192..8202, 8232, 8233, 8239, 8287, 12288, 65279\}$$ -/
def isSpace (c : Char) : Bool :=
  let n := c.toNat
  (9 ≤ n && n ≤ 13) || n == 32 || n == 160 || n == 5760 || (8192 ≤ n && n ≤ 8202) || n == 8232 || n == 8233
    || n == 8239 || n == 8287 || n == 12288 || n == 65279

/-- JS `trim()` on a character list. $$\operatorname{trim}(s) = s \text{ without leading and trailing whitespace}$$ -/
def trim (s : List Char) : List Char :=
  ((s.dropWhile isSpace).reverse.dropWhile isSpace).reverse

/-- A character allowed in a part of the address. $$\lnot\operatorname{ws}(c) \land c \ne \text{'@'}$$ -/
def plain (c : Char) : Bool := !isSpace c && c != '@'

/-- The tail of the address, `[^\s@]+\.[^\s@]+`: plain characters with a dot that is neither first nor last.

$$\operatorname{domain}(t) \iff \forall c \in t:\ \operatorname{plain}(c) \lor c = \text{'.'},\ \exists i:\ 0 < i < |t| - 1,\ t_i = \text{'.'}$$ -/
def domainOk (t : List Char) : Bool :=
  t.all (fun c => plain c || c == '.') && (List.range t.length).any (fun i => 0 < i && i + 1 < t.length && t[i]? == some '.')

/-- The email test `^[^\s@]+@[^\s@]+\.[^\s@]+$` on an already trimmed string.

$$\operatorname{email}(s) \iff s = a\,\text{'@'}\,t,\ a \ne \varepsilon,\ \forall c \in a: \operatorname{plain}(c),\ \operatorname{domain}(t)$$ -/
def emailOk (s : List Char) : Bool :=
  match s.splitOn '@' with
  | [a, t] => !a.isEmpty && a.all plain && domainOk t
  | _ => false

/-- Form validity (`iD`). $$\operatorname{valid}(n, m) \iff \operatorname{trim}(n) \ne \varepsilon \land \operatorname{email}(\operatorname{trim}(m))$$ -/
def valid (name email : List Char) : Bool := !(trim name).isEmpty && emailOk (trim email)

#guard valid "Ann".toList "a\x40example.com".toList
#guard !valid "".toList "a\x40example.com".toList
#guard !valid "  ".toList "a\x40example.com".toList
#guard !valid "Ann".toList "a@b".toList
#guard !valid "Ann".toList "a\x40.co".toList
#guard !valid "Ann".toList "a\x40b.".toList
#guard !valid "Ann".toList "a b\x40example.com".toList
#guard !valid "Ann".toList "a\x40\x40example.com".toList
#guard valid " Ann ".toList " a\x40b.c.d ".toList

/-- A blank name is never valid. $$\operatorname{trim}(n) = \varepsilon \Rightarrow \lnot\operatorname{valid}(n, m)$$ -/
theorem blank_name_invalid (n m : List Char) (h : trim n = []) : valid n m = false := by
  simp [valid, h]

/-! ## Submit -/

/-- Form flags: a request is running, it succeeded, the last attempt failed.
$$F = (\mathit{submitting}, \mathit{done}, \mathit{error})$$ -/
structure Form where
  submitting : Bool
  done : Bool
  error : Bool
deriving Repr, BEq, DecidableEq

/-- The empty form. $$F_0 = (\bot, \bot, \bot)$$ -/
def Form.init : Form := ⟨false, false, false⟩

/-- Submit pressed (`_`, JS 13276-13293). Returns the new flags and whether a request is sent.

$$\operatorname{submit}(F, v, h) = \begin{cases} (F, \bot) & \lnot v \lor F.\mathit{submitting} \\ (F[\mathit{error} := \top], \bot) & \lnot h \\ (F[\mathit{submitting} := \top, \mathit{error} := \bot], \top) & \text{otherwise}\end{cases}$$

Here $v$ is the form validity and $h$ whether a handler exists. -/
def submit (f : Form) (v h : Bool) : Form × Bool :=
  if !v || f.submitting then (f, false)
  else if !h then ({ f with error := true }, false)
  else ({ f with submitting := true, error := false }, true)

/-- The request finished: success sets `done`, failure sets `error`; `submitting` is cleared either way.

$$\operatorname{settle}(F, \mathit{ok}) = \begin{cases} F[\mathit{done} := \top, \mathit{submitting} := \bot] & \mathit{ok} \\ F[\mathit{error} := \top, \mathit{submitting} := \bot] & \lnot\mathit{ok}\end{cases}$$ -/
def settle (f : Form) (ok : Bool) : Form :=
  if ok then { f with done := true, submitting := false } else { f with error := true, submitting := false }

#guard submit Form.init true true == (⟨true, false, false⟩, true)
#guard submit ⟨true, false, false⟩ true true == (⟨true, false, false⟩, false)
#guard submit Form.init false true == (Form.init, false)
#guard submit Form.init true false == (⟨false, false, true⟩, false)

/-- A running request blocks another one. $$F.\mathit{submitting} \Rightarrow \operatorname{submit}(F, v, h) = (F, \bot)$$ -/
theorem submit_blocked (f : Form) (v h : Bool) (hs : f.submitting = true) : submit f v h = (f, false) := by
  simp [submit, hs]

/-- An invalid form sends nothing. $$\lnot v \Rightarrow \operatorname{submit}(F, v, h) = (F, \bot)$$ -/
theorem submit_invalid (f : Form) (h : Bool) : submit f false h = (f, false) := by
  simp [submit]

/-- A sent request leaves `submitting` set, which blocks closing. $$\operatorname{submit}(F,\top,\top) = (F', \top) \Rightarrow F'.\mathit{submitting}$$ -/
theorem submit_sends (f : Form) (hs : f.submitting = false) :
    (submit f true true).2 = true ∧ (submit f true true).1.submitting = true := by
  simp [submit, hs]

/-- Settling always clears `submitting`, so a finished request can be closed. $$\operatorname{settle}(F, \mathit{ok}).\mathit{submitting} = \bot$$ -/
theorem settle_clears (f : Form) (ok : Bool) : (settle f ok).submitting = false := by
  cases ok <;> simp [settle]

/-- A request that started can always be closed once it settles.
$$\operatorname{closeAllowed}(\operatorname{settle}(F, \mathit{ok}).\mathit{submitting}) = \top$$ -/
theorem closable_after_settle (f : Form) (ok : Bool) : closeAllowed (settle f ok).submitting = true := by
  simp [closeAllowed, settle_clears]

end Fw.Parts.OverlaySignup
