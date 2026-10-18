import Fw.Gate.Reach
import Fw.Gate.State
/-!
# Probe scope of a pilot part (`gate-probe-scope`)

A part's **scope** is the set of matrix loads and live-resize sweeps the breakpoint gate must run to judge that
part. It is derived from the media conditions the part's CSS and JS read (the inventory's conditions of its owner
parts, the rewrite's `MEDIA_IDS`, and non-catalogue width facts such as `css.floor-320`).

**Hypothesis H** (what makes a smaller run sound; it is an assumption about the pages, not proved here): for a fixed
engine port, the part's verdict at a fresh load with environment $e$ is $\mathrm{hv}([\kappa(e)])$ and at stop $i$ of
a live-resize sweep it is $\mathrm{hv}(\mathrm{collapse}(\kappa(s_0), \dots, \kappa(s_i)))$, where $\kappa(e)$ is the
truth vector of the scope conditions at $e$, `collapse` drops consecutive repeats, and $\mathrm{hv}$ never returns
`unreachable`; a load is unreachable only for the port's proved reason (`envReason`). H fails when the part's
CSS or JS reads a condition outside its scope, when the rewrite's media text differs from Lean's (the breakpoint lint
and `media.test.ts` guard that), or when a continuous value (a `clamp()` in `vw`) differs between the arms only at
some widths inside one class; those continuous entries are listed per part as assumed.

Under H, `scoped_verdict_eq` proves the generic statement and `scope_sound` the four pilot instances: the rollup of
the part's verdicts over the scoped loads and sweeps equals the rollup over the full matrix and all sweeps, on every
port, also when the run holds more loads or sweeps (several parts at once). `scope_observes_edges` adds that the scope
still holds an observing `N | N+1` pair for every edge of every scope condition, so an off-by-one edge in the rewrite
(which would break H) is still caught inside the scope.
-/
namespace Fw.Gate
open Fw.Site.Breakpoints

/-! ## Generic: verdicts that depend only on the history of a key -/

/-- Drop consecutive repeats (a key history where only changes count).

$$\forall a, b \in \kappa,\ \forall t \in \kappa^*,\quad \operatorname{collapse}([\,]) = [\,],\quad \operatorname{collapse}([a]) = [a],\quad \operatorname{collapse}(a :: b :: t) = \begin{cases} \operatorname{collapse}(b :: t) & a = b \\ a :: \operatorname{collapse}(b :: t) & a \ne b \end{cases}$$

A resize that keeps every scope condition's value adds nothing to the history. -/
def collapse {κ : Type} [DecidableEq κ] : List κ → List κ
  | [] => []
  | [a] => [a]
  | a :: b :: t => if a = b then collapse (b :: t) else a :: collapse (b :: t)

#guard collapse [1, 1, 2, 2, 2, 1] = [1, 2, 1]
#guard collapse ([] : List Nat) = []
#guard collapse [true, true] = [true]

/-- A nonempty constant history collapses to one entry.

$$\forall k \in \kappa,\ \forall l \in \kappa^*,\quad l \ne [\,] \wedge (\forall x \in l,\ x = k) \implies \operatorname{collapse}(l) = [k]$$

A sweep along which the key never changes has the history of a single fresh load. -/
theorem collapse_const {κ : Type} [DecidableEq κ] (k : κ) :
    ∀ l : List κ, l ≠ [] → (∀ x ∈ l, x = k) → collapse l = [k]
  | [], h, _ => absurd rfl h
  | [a], _, h => by rw [h a List.mem_cons_self]; rfl
  | a :: b :: t, _, h => by
    have ha := h a List.mem_cons_self
    have hb := h b (List.mem_cons_of_mem _ List.mem_cons_self)
    have rest := collapse_const k (b :: t) (by simp) (fun x hx => h x (List.mem_cons_of_mem _ hx))
    simp only [collapse, ha, hb, ite_true]
    rw [← hb]; rw [hb] at rest ⊢; exact rest

/-- A live-resize sweep: an id, a description, and its stops (the page loads at the first stop and is only
resized after that).

$$w = (\mathit{id}, \mathit{blurb}, (s_0, \dots, s_{n-1})) \in \Sigma^* \times \Sigma^* \times \mathrm{Env}^*$$

One sweep of `spec.mjs`. -/
structure Sweep where
  /-- sweep id, e.g. `phone-rotation` -/
  id : String
  /-- one line for the report -/
  blurb : String
  /-- the environments in order -/
  stops : List Env

/-- The part's verdicts at the stops of one sweep under hypothesis H: stop $i$ gets the verdict of the collapsed
key history of stops $0..i$.

$$\forall \kappa, \mathrm{hv},\ \forall n \ge 0,\ \forall (s_0, \dots, s_{n-1}),\quad \operatorname{stops}_{\kappa,\mathrm{hv}}(s_0, \dots, s_{n-1}) = \big(\mathrm{hv}(\operatorname{collapse}(\kappa(s_0), \dots, \kappa(s_i)))\big)_{0 \le i < n} \quad (= (\,) \text{ for } n = 0)$$

What a sweep contributes to the part's row. -/
def stopVerdicts {κ : Type} [DecidableEq κ] (key : Env → κ) (hv : List κ → Verdict) (stops : List Env) :
    List Verdict :=
  (List.range stops.length).map fun i => hv (collapse ((stops.take (i + 1)).map key))

#guard stopVerdicts (fun e => decide (e.width.LeNat 600)) (fun h => if h.length > 1 then .fail else .pass)
  [deskEnv (.ofNat 700) (.ofNat 900) (.ofNat 1) .noPreference, deskEnv (.ofNat 701) (.ofNat 900) (.ofNat 1) .noPreference,
   deskEnv (.ofNat 600) (.ofNat 900) (.ofNat 1) .noPreference] = [.pass, .pass, .fail]

/-- Along a sweep whose key is constant, every stop gets the verdict of a fresh load.

$$\forall \kappa, \mathrm{hv}, s, k,\quad (\forall e \in s,\ \kappa(e) = k) \implies \forall v \in \operatorname{stops}_{\kappa,\mathrm{hv}}(s),\ v = \mathrm{hv}([k])$$

A sweep that never crosses a scope edge adds no new verdict. -/
theorem stopVerdicts_const {κ : Type} [DecidableEq κ] (key : Env → κ) (hv : List κ → Verdict)
    (stops : List Env) (k : κ) (h : ∀ e ∈ stops, key e = k) :
    ∀ v ∈ stopVerdicts key hv stops, v = hv [k] := by
  intro v hv'
  simp only [stopVerdicts, List.mem_map, List.mem_range] at hv'
  obtain ⟨i, hi, rfl⟩ := hv'
  congr 1
  apply collapse_const
  · simp only [ne_eq, List.map_eq_nil_iff, List.take_eq_nil_iff]
    rintro (h0 | h0)
    · omega
    · subst h0; simp at hi
  · intro x hx
    simp only [List.mem_map] at hx
    obtain ⟨e, he, rfl⟩ := hx
    exact h e (List.mem_of_mem_take he)

/-- The part's verdict at a fresh load under hypothesis H: the port's reason when it cannot reach the
environment, else the verdict of the one-entry history.

$$\forall \rho, \kappa, \mathrm{hv}, e,\quad \operatorname{load}_{\rho,\kappa,\mathrm{hv}}(e) = \begin{cases} \mathrm{unreachable}(r) & \rho(e) = \mathrm{some}(r) \\ \mathrm{hv}([\kappa(e)]) & \rho(e) = \bot \end{cases}$$

One matrix probe's cell in the part's row. -/
def keyedVerdict {κ : Type} (reach : Env → Option Reason) (key : Env → κ) (hv : List κ → Verdict) (e : Env) :
    Verdict :=
  match reach e with
  | some r => .unreachable r
  | none => hv [key e]

#guard keyedVerdict (fun _ => some .wholeWidth) (fun _ => 0) (fun _ => .pass)
  (deskEnv (.ofNat 700) (.ofNat 900) (.ofNat 1) .noPreference) = .unreachable .wholeWidth
#guard keyedVerdict (fun _ => none) (fun _ => 0) (fun _ => .fail)
  (deskEnv (.ofNat 700) (.ofNat 900) (.ofNat 1) .noPreference) = .fail

/-- The part's verdict over a run: the rollup of its verdicts at the run's loads and at every stop of the run's
sweeps.

$$\forall \rho, \kappa, \mathrm{hv}, S, K,\quad V_{\rho,\kappa,\mathrm{hv}}(S, K) = \operatorname{rollup}\big([\operatorname{load}_{\rho,\kappa,\mathrm{hv}}(e(p)) \mid p \in S] \mathbin{+\!\!+} [v \mid w \in K,\ v \in \operatorname{stops}_{\kappa,\mathrm{hv}}(w)]\big)$$

The part's row of the gate, rolled up into one verdict. -/
def scopedVerdict {κ : Type} [DecidableEq κ] (reach : Env → Option Reason) (key : Env → κ)
    (hv : List κ → Verdict) (S : List Probe) (K : List Sweep) : Verdict :=
  rollup (S.map (fun p => keyedVerdict reach key hv p.env) ++ K.flatMap fun w => stopVerdicts key hv w.stops)

/-- **Scoped runs keep the verdict (generic).** Let the run's loads $S \subseteq M$ and sweeps $K \subseteq W$. If
every reachable load of $M$ has a reachable load in $S$ with the same key, every sweep of $W$ left out of $K$ has a
constant key that a reachable load of $S$ shows, some load of $M$ is reachable, and $\mathrm{hv}$ never says
unreachable, then the part's verdict over $(S, K)$ equals its verdict over $(M, W)$.

$$\begin{aligned} &\forall \rho, \kappa, \mathrm{hv}, S, M, K, W,\quad (\forall h,\ \neg\operatorname{isU}(\mathrm{hv}(h))) \wedge S \subseteq M \wedge K \subseteq W \\ &\wedge (\forall p \in M,\ \rho(e(p)) = \bot \Rightarrow \exists q \in S,\ \rho(e(q)) = \bot \wedge \kappa(e(q)) = \kappa(e(p))) \\ &\wedge (\forall w \in W,\ w \notin K \Rightarrow \exists q \in S,\ \rho(e(q)) = \bot \wedge \forall x \in w,\ \kappa(x) = \kappa(e(q))) \\ &\wedge (\exists p \in M,\ \rho(e(p)) = \bot) \implies V_{\rho,\kappa,\mathrm{hv}}(S, K) = V_{\rho,\kappa,\mathrm{hv}}(M, W) \end{aligned}$$

Only the set of reachable verdicts matters, and a scoped run produces the same set. -/
theorem scoped_verdict_eq {κ : Type} [DecidableEq κ] (reach : Env → Option Reason) (key : Env → κ)
    (hv : List κ → Verdict) (hU : ∀ h, (hv h).isUnreachable = false)
    (S M : List Probe) (K W : List Sweep) (hS : ∀ p ∈ S, p ∈ M) (hK : ∀ w ∈ K, w ∈ W)
    (hcov : ∀ p ∈ M, reach p.env = none → ∃ q ∈ S, reach q.env = none ∧ key q.env = key p.env)
    (hdrop : ∀ w ∈ W, w ∉ K → ∃ q ∈ S, reach q.env = none ∧ ∀ x ∈ w.stops, key x = key q.env)
    (hex : ∃ p ∈ M, reach p.env = none) :
    scopedVerdict reach key hv S K = scopedVerdict reach key hv M W := by
  -- a load's verdict is reachable exactly when the port reaches it
  have kv_none : ∀ e, reach e = none → keyedVerdict reach key hv e = hv [key e] := by
    intro e h; simp [keyedVerdict, h]
  have kv_reach : ∀ e, (keyedVerdict reach key hv e).isUnreachable = false → reach e = none := by
    intro e h
    cases hr : reach e with
    | none => rfl
    | some r => simp [keyedVerdict, hr, Verdict.isUnreachable] at h
  have sv_reach : ∀ w : Sweep, ∀ v ∈ stopVerdicts key hv w.stops, v.isUnreachable = false := by
    intro w v hv'
    simp only [stopVerdicts, List.mem_map] at hv'
    obtain ⟨i, _, rfl⟩ := hv'
    exact hU _
  -- every reachable verdict of the full run is one of the scoped run
  have back : ∀ v, v ∈ (M.map (fun p => keyedVerdict reach key hv p.env) ++
      W.flatMap fun w => stopVerdicts key hv w.stops) → v.isUnreachable = false →
      v ∈ (S.map (fun p => keyedVerdict reach key hv p.env) ++ K.flatMap fun w => stopVerdicts key hv w.stops) := by
    intro v hm hvu
    rcases List.mem_append.mp hm with hm | hm
    · obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hm
      have hr := kv_reach _ hvu
      obtain ⟨q, hq, hqr, hqk⟩ := hcov p hp hr
      refine List.mem_append_left _ (List.mem_map.mpr ⟨q, hq, ?_⟩)
      rw [kv_none _ hqr, kv_none _ hr, hqk]
    · obtain ⟨w, hw, hvw⟩ := List.mem_flatMap.mp hm
      by_cases hwK : w ∈ K
      · exact List.mem_append_right _ (List.mem_flatMap.mpr ⟨w, hwK, hvw⟩)
      · obtain ⟨q, hq, hqr, hqk⟩ := hdrop w hw hwK
        have := stopVerdicts_const key hv w.stops (key q.env) hqk v hvw
        refine List.mem_append_left _ (List.mem_map.mpr ⟨q, hq, ?_⟩)
        rw [kv_none _ hqr, this]
  have fwd : ∀ v, v ∈ (S.map (fun p => keyedVerdict reach key hv p.env) ++
      K.flatMap fun w => stopVerdicts key hv w.stops) →
      v ∈ (M.map (fun p => keyedVerdict reach key hv p.env) ++ W.flatMap fun w => stopVerdicts key hv w.stops) := by
    intro v hm
    rcases List.mem_append.mp hm with hm | hm
    · obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hm
      exact List.mem_append_left _ (List.mem_map.mpr ⟨p, hS p hp, rfl⟩)
    · obtain ⟨w, hw, hvw⟩ := List.mem_flatMap.mp hm
      exact List.mem_append_right _ (List.mem_flatMap.mpr ⟨w, hK w hw, hvw⟩)
  obtain ⟨p0, hp0, hr0⟩ := hex
  obtain ⟨q0, hq0, hqr0, _⟩ := hcov p0 hp0 hr0
  have exS : ∃ v ∈ (S.map (fun p => keyedVerdict reach key hv p.env) ++
      K.flatMap fun w => stopVerdicts key hv w.stops), v.isUnreachable = false :=
    ⟨_, List.mem_append_left _ (List.mem_map.mpr ⟨q0, hq0, rfl⟩), by rw [kv_none _ hqr0]; exact hU _⟩
  have exM : ∃ v ∈ (M.map (fun p => keyedVerdict reach key hv p.env) ++
      W.flatMap fun w => stopVerdicts key hv w.stops), v.isUnreachable = false :=
    ⟨_, List.mem_append_left _ (List.mem_map.mpr ⟨p0, hp0, rfl⟩), by rw [kv_none _ hr0]; exact hU _⟩
  unfold scopedVerdict
  rw [← rollup_filter_unreachable _ exS, ← rollup_filter_unreachable _ exM]
  apply rollup_congr
  intro v
  simp only [List.mem_filter, Bool.not_eq_true']
  exact ⟨fun ⟨h1, h2⟩ => ⟨fwd v h1, h2⟩, fun ⟨h1, h2⟩ => ⟨back v h1 h2, h2⟩⟩

/-! ## The pilot parts: conditions, key, scope -/

/-- A width fact of a part that is not one of the 30 catalogue conditions (e.g. the root's `min-width: 320px`).

$$x = (\mathit{id}, \mathit{why}, q) \in \Sigma^* \times \Sigma^* \times \mathrm{MQ}$$

An extra edge the part's CSS has. -/
structure ExtraCond where
  /-- inventory id, e.g. `css.floor-320` -/
  id : String
  /-- why it is in the key -/
  why : String
  /-- the condition as a media query -/
  query : MQ

/-- A knee of a continuous value (a `clamp()` in `vw`): the width where it stops being constant.

$$k = (\mathit{expr}, n) \in \Sigma^* \times \mathbb N$$

The key splits at each knee, so each piece of the clamp gets a load. -/
structure Knee where
  /-- the inventory's expression, e.g. `hero h1 font clamp 40px / 4.5vw / 64px` -/
  expr : String
  /-- the knee in CSS px (the band is `(width<=Npx)`) -/
  px : Nat

/-- What a pilot part reads: its owner parts in the inventory, the catalogue conditions the original uses (the
inventory's conditions of the owners) and the rewrite uses (`MEDIA_IDS` of its `media.ts`), extra width facts,
knees of continuous values, and the inventory entries left out of the key with the reason.

$$u = (\mathit{id}, O, C_{\mathrm{orig}}, C_{\mathrm{rw}}, X, \mathit{Kn}, D)$$

The declaration a part's scope is computed from. -/
structure PartUse where
  /-- the gate part id (`anchors.json`) -/
  id : String
  /-- inventory parts whose elements the gate part compares -/
  owners : List String
  /-- catalogue ids the original reads for these elements -/
  orig : List String
  /-- catalogue ids the rewrite reads (`MEDIA_IDS`) -/
  rewrite : List String
  /-- non-catalogue width facts -/
  extra : List ExtraCond
  /-- knees of continuous values -/
  knees : List Knee
  /-- inventory entries of the owners that are not in the key, with the reason -/
  dismissed : List (String × String)

/-- The query of a catalogue id, if the id exists.

$$\forall s \in \Sigma^*,\quad \operatorname{cond}(s) = \begin{cases} q_i & \text{the first } i < 30 \text{ with } \mathrm{id}(c_i) = s \\ \bot & \text{no such } i \end{cases}$$

Looks a condition up by its inventory id. -/
def lookupCond (s : String) : Option MQ := (catalogue.find? (·.id == s)).map (·.query)

#guard lookupCond "mq.w-le-600" = some wLe600
#guard lookupCond "mq.nope" = none

/-- The part's catalogue ids: the original's then the rewrite's, first occurrence kept.

$$\forall u,\quad C(u) = \operatorname{dedup}_{\text{first}}(C_{\mathrm{orig}}(u) \mathbin{+\!\!+} C_{\mathrm{rw}}(u))$$

Every condition either arm reads. -/
def PartUse.conds (u : PartUse) : List String := (u.orig ++ u.rewrite).foldl MQ.pushNew []

/-- The queries whose edges the scope must observe: the catalogue conditions, then the extra width facts.

$$\forall u,\quad Q_E(u) = [\,q \mid s \in C(u),\ \operatorname{cond}(s) = q\,] \mathbin{+\!\!+} [\,q(x) \mid x \in X(u)\,]$$

The part's media edges. -/
def PartUse.edgeQueries (u : PartUse) : List MQ := u.conds.filterMap lookupCond ++ u.extra.map (·.query)

/-- The band query of a knee: `(width<=Npx)`.

$$\forall k,\quad \forall e,\ e \models \operatorname{band}(k) \iff \mathrm{width}(e) \le n(k)$$

Which side of the knee a load is on. -/
def kneeQuery (k : Knee) : MQ := ⟨[[.widthLe k.px]]⟩

/-- All queries of the key: the edge queries, then the knee bands.

$$\forall u,\quad Q(u) = Q_E(u) \mathbin{+\!\!+} [\,\operatorname{band}(k) \mid k \in \mathit{Kn}(u)\,]$$

What the part's verdict may depend on under hypothesis H. -/
def PartUse.queries (u : PartUse) : List MQ := u.edgeQueries ++ u.knees.map kneeQuery

/-- **The key** of a part at an environment: the truth vector of its queries.

$$\forall u, e,\quad \kappa_u(e) = (\llbracket q \rrbracket_e)_{q \in Q(u)} \in \mathbb B^{|Q(u)|}$$

Two loads with the same key look the same to the part's media conditions. -/
def PartUse.key (u : PartUse) (e : Env) : List Bool := u.queries.map (·.eval e)

/-- `css.floor-320`: the root's `min-width: 320px` as the query `(width>=320px)`.

$$\forall e,\quad e \models \mathtt{floor320} \iff \mathrm{width}(e) \ge 320$$

Below 320 px the page stops shrinking. -/
def floor320 : ExtraCond :=
  ⟨"css.floor-320", "root min-width 320px: below it the page stops shrinking and scrolls sideways (the scroller's size)",
   ⟨[[.widthGeSucc 319]]⟩⟩

/-- The pilot parts of `anchors.json` (14 parts, in this order) and what they read (inventory `research/kickoff/11-breakpoints/
breakpoints.json`: conditions and continuous entries of the owners; rewrite: `apps/site/src/parts/*/media.ts`).
Per part: owners, original and rewrite catalogue ids, extra width facts, knees as (expression, px) and dismissed
ids (each with its reason, listed in the source).

$$\begin{aligned} \mathrm{pilot} = [\ &(\texttt{engine.scroll},\ O = [\texttt{engine.scroll}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}], \\ &\quad C_{\mathrm{rw}} = [\,],\ X = [\texttt{css.floor-320}],\ \mathit{Kn} = [\,],\ D = [\texttt{html.viewport-meta}, \texttt{js.preload-hover}, \texttt{js.firefox-ua}]), \\ &(\texttt{nav.hitTest},\ O = [\texttt{nav.hitTest}],\ C_{\mathrm{orig}} = [\,], \\ &\quad C_{\mathrm{rw}} = [\,],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\texttt{js.nav-on-dark}]), \\ &(\texttt{hero.countdown},\ O = [\texttt{hero.countdown}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-400}, \texttt{mq.c1000-nodw}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-400}, \texttt{mq.c1000-nodw}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\texttt{js.countdown-cell}]), \\ &(\texttt{morph.countdown},\ O = [\texttt{morph.countdown}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-400}, \texttt{mq.c1000-nodw}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-400}, \texttt{mq.c1000-nodw}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\texttt{js.countdown-cell}]), \\ &(\texttt{hero.exit},\ O = [\texttt{hero.exit}, \texttt{hero}, \texttt{hero.cue}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-600}, \texttt{mq.w-gt-600}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-600}, \texttt{mq.w-gt-600}],\ X = [\,],\ \mathit{Kn} = [(e_h, 889), (e_h, 1422), (e_g, 875), (e_g, 1500)],\ D = [\texttt{css.hover-ungated}]), \\ &(\texttt{morph.mount},\ O = [\texttt{morph.mount}],\ C_{\mathrm{orig}} = [\,], \\ &\quad C_{\mathrm{rw}} = [\,],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\texttt{js.morph-arm}]), \\ &(\texttt{morph.columns},\ O = [\texttt{morph.columns}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-640}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-640}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,]), \\ &(\texttt{morph.tween},\ O = [\texttt{morph.tween}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-640}, \texttt{mq.c860}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\texttt{js.morph-arm}]), \\ &(\texttt{platform},\ O = [\texttt{platform}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.rm-nopref}, \texttt{mq.w-le-640}, \texttt{mq.w-le-720}, \texttt{mq.w-le-860}, \texttt{mq.w-ge-861}, \texttt{mq.w-861-1000}, \texttt{mq.w-le-960}, \texttt{mq.w-le-1000}, \texttt{mq.w-ge-1001}, \texttt{mq.w-le-1100}, \texttt{mq.c860}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}, \texttt{mq.rm-nopref}, \texttt{mq.w-ge-1001}, \texttt{mq.w-861-1000}, \texttt{mq.w-ge-861}, \texttt{mq.w-le-960}, \texttt{mq.w-le-1000}, \texttt{mq.w-le-720}, \texttt{mq.c860}, \texttt{mq.w-le-640}],\ X = [\,],\ \mathit{Kn} = [(e_t, 900), (e_t, 1200), (e_p, 400), (e_p, 500)],\ D = [\texttt{css.hover-ungated}]), \\ &(\texttt{platform.sweep},\ O = [\texttt{platform.sweep}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-nopref}, \texttt{mq.w-ge-861}, \texttt{mq.w-le-1000}, \texttt{mq.c860}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-nopref}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,]), \\ &(\texttt{platform.stageBg},\ O = [\texttt{platform.stageBg}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}, \texttt{mq.w-le-640}, \texttt{mq.w-le-960}, \texttt{mq.c860}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.c860}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,]), \\ &(\texttt{platform.glint},\ O = [\texttt{platform.glint}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,]), \\ &(\texttt{platform.entries},\ O = [\texttt{platform.entries}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,]), \\ &(\texttt{platform.marquee},\ O = [\texttt{platform.marquee}],\ C_{\mathrm{orig}} = [\texttt{mq.rm-reduce}], \\ &\quad C_{\mathrm{rw}} = [\texttt{mq.rm-reduce}],\ X = [\,],\ \mathit{Kn} = [\,],\ D = [\,])\ ], \\ e_h = {} &\text{``hero h1 font clamp 40px / 4.5vw / 64px''},\quad e_g = \text{``hero title gap clamp 14 / 1.6vw / 24''}, \\ e_t = {} &\text{``future / platform / mission title clamp 36 / 4vw / 48''},\quad e_p = \text{``platform title clamp 32 / 8vw / 40 (inside width<=640)''} \end{aligned}$$

The scope declarations of the pilot, in this order: owners, original and rewrite catalogue ids, extra width facts,
knees and dismissed inventory entries per part. -/
def pilotParts : List PartUse := [
  { id := "engine.scroll", owners := ["engine.scroll"], orig := ["mq.rm-reduce"], rewrite := [],
    extra := [floor320], knees := [],
    dismissed := [
      ("html.viewport-meta", "the same meta on both arms; it fixes layout width = viewport width and adds no edge"),
      ("js.preload-hover", "link preload on pointer events: network only, no visual effect"),
      ("js.firefox-ua", "user agent, not a media feature; no visual effect")] },
  { id := "nav.hitTest", owners := ["nav.hitTest"], orig := [], rewrite := [], extra := [], knees := [],
    dismissed := [
      ("js.nav-on-dark", "elementFromPoint at a scroll position, not a media condition: no edge; the gate loads at the top")] },
  { id := "hero.countdown", owners := ["hero.countdown"], orig := ["mq.rm-reduce", "mq.w-le-400", "mq.c1000-nodw"],
    rewrite := ["mq.rm-reduce", "mq.w-le-400", "mq.c1000-nodw"], extra := [], knees := [],
    dismissed := [
      ("js.countdown-cell", "measures the cell height that the key's conditions set (font at 400 / 1000-or-touch-1200)")] },
  { id := "morph.countdown", owners := ["morph.countdown"], orig := ["mq.rm-reduce", "mq.w-le-400", "mq.c1000-nodw"],
    rewrite := ["mq.rm-reduce", "mq.w-le-400", "mq.c1000-nodw"], extra := [], knees := [],
    dismissed := [
      ("js.countdown-cell", "measures the cell height that the key's conditions set (font at 400 / 1000-or-touch-1200)")] },
  { id := "hero.exit", owners := ["hero.exit", "hero", "hero.cue"],
    orig := ["mq.rm-reduce", "mq.w-le-600", "mq.w-gt-600"], rewrite := ["mq.rm-reduce", "mq.w-le-600", "mq.w-gt-600"],
    extra := [],
    knees := [⟨"hero h1 font clamp 40px / 4.5vw / 64px", 889⟩, ⟨"hero h1 font clamp 40px / 4.5vw / 64px", 1422⟩,
              ⟨"hero title gap clamp 14 / 1.6vw / 24", 875⟩, ⟨"hero title gap clamp 14 / 1.6vw / 24", 1500⟩],
    dismissed := [("css.hover-ungated", "plain :hover rules; the gate never hovers an element")] },
  { id := "morph.mount", owners := ["morph.mount"], orig := [], rewrite := [], extra := [], knees := [],
    dismissed := [
      ("js.morph-arm", "platform rect against the visual viewport height at a scroll position, not a width edge; the part restates no CSS and the gate loads at the top")] },
  { id := "morph.columns", owners := ["morph.columns"],
    orig := ["mq.rm-reduce", "mq.w-le-640"], rewrite := ["mq.rm-reduce", "mq.w-le-640"],
    extra := [], knees := [], dismissed := [] },
  { id := "morph.tween", owners := ["morph.tween"], orig := ["mq.rm-reduce", "mq.w-le-640", "mq.c860"], rewrite := ["mq.rm-reduce"],
    extra := [], knees := [],
    dismissed := [
      ("js.morph-arm", "platform rect height and bottom against the visual viewport at a scroll position, armed by wheel and touch: not a media condition and no edge; the rewrite page has no platform section and the gate loads at the top")] },
  { id := "platform", owners := ["platform"],
    orig := ["mq.rm-reduce", "mq.rm-nopref", "mq.w-le-640", "mq.w-le-720", "mq.w-le-860", "mq.w-ge-861", "mq.w-861-1000",
             "mq.w-le-960", "mq.w-le-1000", "mq.w-ge-1001", "mq.w-le-1100", "mq.c860"],
    rewrite := ["mq.rm-reduce", "mq.rm-nopref", "mq.w-ge-1001", "mq.w-861-1000", "mq.w-ge-861", "mq.w-le-960",
                "mq.w-le-1000", "mq.w-le-720", "mq.c860", "mq.w-le-640"],
    extra := [],
    knees := [⟨"future / platform / mission title clamp 36 / 4vw / 48", 900⟩, ⟨"future / platform / mission title clamp 36 / 4vw / 48", 1200⟩,
              ⟨"platform title clamp 32 / 8vw / 40 (inside width<=640)", 400⟩, ⟨"platform title clamp 32 / 8vw / 40 (inside width<=640)", 500⟩],
    dismissed := [("css.hover-ungated", "plain :hover rules; the gate never hovers an element")] },
  { id := "platform.sweep", owners := ["platform.sweep"],
    orig := ["mq.rm-nopref", "mq.w-ge-861", "mq.w-le-1000", "mq.c860"], rewrite := ["mq.rm-nopref"],
    extra := [], knees := [], dismissed := [] },
  { id := "platform.stageBg", owners := ["platform.stageBg"],
    orig := ["mq.rm-reduce", "mq.w-le-640", "mq.w-le-960", "mq.c860"], rewrite := ["mq.c860"],
    extra := [], knees := [], dismissed := [] },
  { id := "platform.glint", owners := ["platform.glint"],
    orig := ["mq.rm-reduce"], rewrite := ["mq.rm-reduce"], extra := [], knees := [], dismissed := [] },
  { id := "platform.entries", owners := ["platform.entries"],
    orig := ["mq.rm-reduce"], rewrite := ["mq.rm-reduce"], extra := [], knees := [], dismissed := [] },
  { id := "platform.marquee", owners := ["platform.marquee"],
    orig := ["mq.rm-reduce"], rewrite := ["mq.rm-reduce"], extra := [], knees := [], dismissed := [] },
  -- engine.scene (variant `hidden-pause`): an IntersectionObserver pauses a scene's CSS animations while it paints
  -- nothing; no media condition and no width edge, so the key is empty and one load judges it (as for nav.hitTest)
  { id := "engine.scene", owners := ["engine.scene"], orig := [], rewrite := [], extra := [], knees := [],
    dismissed := [
      ("js.scene-activation", "scene active when its rect is within [-innerHeight, 2 x innerHeight] (IntersectionObserver, rootMargin 100%): viewport height at a scroll position, not a width edge; the gate loads at the top")] }
]

/-- Every catalogue id a pilot part names exists in the catalogue.

$$\forall u \in \mathrm{pilot},\ \forall s \in C(u),\quad \operatorname{cond}(s) \ne \bot$$

No declared condition is silently dropped from the key. -/
theorem pilot_conds_known : pilotParts.all (fun u => u.conds.all fun s => (lookupCond s).isSome) = true := by
  decide +kernel

/-! ### Choosing the loads -/

/-- The engine ports the scope must serve.

$$\mathcal P = [\mathrm{chromium}, \mathrm{webkitApple}, \mathrm{webkitGLib}]$$

Every port the gate can run on. -/
def ports : List Port := [.chromium, .webkitApple, .webkitGLib]

/-- The first observing pair of an edge in matrix order (as `observesFlip` searches), as a two-element list, or
nothing.

$$\forall q, a, n,\quad \operatorname{pair}(q, a, n) = \begin{cases} [p, p'] & (p, p') \text{ the first pair in matrix order with } a(p) = n,\ a(p') = n{+}1,\ \mathrm{blk}(p) = \mathrm{blk}(p'),\ p \sim p',\ \llbracket q \rrbracket_p \ne \llbracket q \rrbracket_{p'} \\ [\,] & \text{no such pair} \end{cases}$$

The two loads that show the flip of `q` at edge `n`. -/
def edgePair (q : MQ) (tag : Axis) (n : Nat) : List Probe :=
  match (matrix.filter fun p => axisOf tag p.env == .ofNat n).findSome? fun p =>
      ((matrix.filter fun p' => axisOf tag p'.env == .ofNat (n + 1)).find? fun p' =>
        p.block == p'.block && decide (Agree p.env p'.env) && q.eval p.env != q.eval p'.env).map (p, ·) with
  | some (p, p') => [p, p']
  | none => []

#guard (edgePair wLe600 .width 600).map (·.id) = ["desk-600", "desk-601"]

/-- The seed loads: the observing pair of every edge of every edge query.

$$\forall u,\quad \operatorname{seeds}(u) = [\,p \mid q \in Q_E(u),\ (a, n) \in E(q),\ p \in \operatorname{pair}(q, a, n)\,]$$

Edges are always tested on both sides. -/
def seeds (u : PartUse) : List Probe :=
  u.edgeQueries.flatMap fun q => q.taggedEdges.flatMap fun (tag, n) => edgePair q tag n

/-- A load is still needed when some port reaches it and no kept load that port reaches has its key.

$$\forall \kappa, T, p,\quad \operatorname{need}_\kappa(T, p) \iff \exists \pi \in \mathcal P,\ \rho_\pi(e(p)) = \bot \wedge \neg \exists t \in T,\ \rho_\pi(e(t)) = \bot \wedge \kappa(e(t)) = \kappa(e(p))$$

Greedy cover test. -/
def needed (key : Env → List Bool) (kept : List Probe) (p : Probe) : Bool :=
  ports.any fun π => (envReason π p.env).isNone &&
    !(kept.any fun t => (envReason π t.env).isNone && key t.env == key p.env)

/-- Greedy cover: walk the candidates in order and keep each one still needed.

$$\forall \kappa, T,\quad \operatorname{greedy}_\kappa(T, [\,]) = T,\qquad \forall p, c,\quad \operatorname{greedy}_\kappa(T, p :: c) = \operatorname{greedy}_\kappa\big(\text{if } \operatorname{need}_\kappa(T, p) \text{ then } T \mathbin{+\!\!+} [p] \text{ else } T,\ c\big)$$

One load per (port, key) class, in matrix order. -/
def greedy (key : Env → List Bool) : List Probe → List Probe → List Probe
  | kept, [] => kept
  | kept, p :: rest => greedy key (if needed key kept p then kept ++ [p] else kept) rest

/-- **The scope of a part**: the matrix loads whose id is among the seeds or the greedy cover (started from the
seeds, run over the matrix in order), in matrix order.

$$\forall u,\quad S(u) = [\,p \in M \mid \exists t \in \operatorname{greedy}_{\kappa_u}(\operatorname{seeds}(u), M),\ \mathrm{id}(t) = \mathrm{id}(p)\,]$$

The loads `--parts` runs for this part. -/
def scopeProbes (u : PartUse) : List Probe :=
  let chosen := greedy u.key (seeds u) matrix
  matrix.filter fun p => chosen.any (·.id == p.id)

/-- The scope is part of the matrix.

$$\forall u,\ \forall p \in S(u),\quad p \in M$$

A scoped run never runs a load the full run lacks. -/
theorem scopeProbes_sub (u : PartUse) : ∀ p ∈ scopeProbes u, p ∈ matrix := fun _ hp =>
  (List.mem_filter.mp hp).1

/-! ### The sweeps -/

/-- A desktop sweep stop (`DESK` of `spec.mjs`): height 900, DPR 1, hover, fine, no preference, light.

$$\forall n,\quad \operatorname{deskStop}(n) = \operatorname{desk}(n, 900, 1, \text{no-preference})$$

One stop of the desktop sweeps. -/
def deskStop (n : Nat) : Env := deskEnv (.ofNat n) (.ofNat 900) (.ofNat 1) .noPreference

/-- A touch sweep stop (`TOUCH` of `spec.mjs`): height 900, DPR 2, no hover, coarse, no preference, light.

$$\forall n,\quad \operatorname{touchStop}(n) = \operatorname{touch}(n, 900, 2, \text{no-preference})$$

One stop of the tablet sweep. -/
def touchStop (n : Nat) : Env := touchEnv (.ofNat n) (.ofNat 900) (.ofNat 2) .noPreference

/-- A phone stop (`PHONE` of `spec.mjs`): screen 430 x 932, DPR 3, no hover, coarse, no preference, light.

$$\forall n, m,\quad \operatorname{phoneStop}(n, m) = (w{=}n, h{=}m, d_w{=}430, d_h{=}932, r{=}3, \text{none}, \text{coarse}, \text{no-preference}, \text{light})$$

One stop of the rotation sweep. -/
def phoneStop (n m : Nat) : Env :=
  { width := .ofNat n, height := .ofNat m, deviceWidth := .ofNat 430, deviceHeight := .ofNat 932, dpr := .ofNat 3,
    hover := .none, pointer := .coarse, motion := .noPreference, scheme := .light }

/-- The desktop sweep widths, high to low: both sides of every width edge pair, at least 320.

$$D = \operatorname{reverse}\big([\,m \mid n \in \mathrm{widthEdgePairs},\ m \in [n,\ n{+}1],\ m \ge 320\,]\big) = (1512, 1511, 1280, \dots, 401, 400, 320)$$

The stops of the long desktop sweep on its way down. -/
def deskSweepWidths : List Nat := ((widthEdgePairs.flatMap fun n => [n, n + 1]).filter (320 ≤ ·)).reverse

#guard deskSweepWidths.length = 29
#guard deskSweepWidths.head? = some 1512 ∧ deskSweepWidths.getLast? = some 320

/-- The four live-resize sweeps of `spec.mjs`, in its order.

$$\begin{aligned} W = [\ &\texttt{desktop-1512-320-1512}: \operatorname{deskStop}(D \mathbin{+\!\!+} \operatorname{tail}(\operatorname{reverse} D)), \\ &\texttt{phone-rotation}: \operatorname{phoneStop}((430,932),(932,430),(430,932),(932,430),(430,932)), \\ &\texttt{touch-1024-1201}: \operatorname{touchStop}(1024, 1201, 1024, 1201, 1024), \\ &\texttt{pain-1440-600-1440}: \operatorname{deskStop}(1440, 600, 1440, 600, 1440)\ ] \end{aligned}$$

The sweeps the full gate runs. -/
def sweeps : List Sweep := [
  ⟨"desktop-1512-320-1512", "desktop 1512 down through every edge to 320 and back up",
   (deskSweepWidths ++ deskSweepWidths.reverse.drop 1).map deskStop⟩,
  ⟨"phone-rotation", "phone 430x932 <-> 932x430 (device width stays 430), twice",
   [(430, 932), (932, 430), (430, 932), (932, 430), (430, 932)].map fun (n, m) => phoneStop n m⟩,
  ⟨"touch-1024-1201", "touch tablet 1024 <-> 1201, twice", [1024, 1201, 1024, 1201, 1024].map touchStop⟩,
  ⟨"pain-1440-600-1440", "v1's 1440 -> 600 -> 1440 pain sequence, twice", [1440, 600, 1440, 600, 1440].map deskStop⟩
]

/-- Every sweep stop is reachable on every port (whole widths, primary input pairs, whole device px).

$$\forall \pi \in \mathcal P,\ \forall w \in W,\ \forall e \in w,\quad \rho_\pi(e) = \bot$$

A sweep never has an unreachable stop, so its verdicts come from the page alone. -/
theorem sweeps_reachable :
    (ports.all fun π => sweeps.all fun w => w.stops.all fun e => (envReason π e).isNone) = true := by
  decide +kernel

/-- Whether two environments have the same Lean vector key (what `expectFor` of `spec.mjs` looks up: width, device width, hover,
pointer, reduced motion and scheme; height and DPR do not matter, `MQ.eval_indep_height_dpr`).

$$\operatorname{sameVec}(a, b) \iff a.w = b.w \wedge a.d_w = b.d_w \wedge a.\eta = b.\eta \wedge a.\pi = b.\pi \wedge a.\mu = b.\mu \wedge a.\sigma = b.\sigma$$

Two loads with the same key have the same expected truth. -/
def _root_.Fw.Site.Breakpoints.Env.sameVector (a b : Env) : Bool :=
  a.width == b.width && a.deviceWidth == b.deviceWidth && a.hover == b.hover && a.pointer == b.pointer &&
    a.motion == b.motion && a.scheme == b.scheme

/-- **The 1024 stops of the tablet sweep have no Lean vector, so their Lean rows are not comparable by construction.**

$$\Bigl(\forall p \in M,\ \neg\operatorname{sameVec}(p.\mathit{env}, \operatorname{touchStop}(1024))\Bigr) \wedge \bigl\{\, i \mid s_i = \operatorname{touchStop}(1024) \,\bigr\} = \{0, 2, 4\} \wedge \bigl(\forall o, r, \mathit{ach}, \forall it \in \operatorname{truthItems}(o, r, \bot, \bot, \mathit{ach}),\ it.\mathrm{cls} \in \{\mathrm{lean}, \mathrm{neutral.lean}\} \implies it.\mathrm{status} = \mathrm{na}\bigr)$$

where $(s_0, \dots, s_4)$ are the stops of `touch-1024-1201`. No matrix probe has the environment of stops 0, 2 and 4 (width 1024 is not
a width edge pair), so the lookup finds no vector and every check against Lean's value at those stops is `na`
(`truthItems_lean_na_no_vector`). This is the premise of the exemption `touch-1024-1201-no-vector`: it excuses those readings of the row `matchMedia =Lean` and no others. -/
theorem touch1024_lean_na :
    (matrix.all fun p => !p.env.sameVector (touchStop 1024)) = true ∧
    ((sweeps.find? (·.id == "touch-1024-1201")).map fun w =>
      (List.range w.stops.length).filter fun i => w.stops[i]? == some (touchStop 1024)) = some [0, 2, 4] ∧
    ∀ (o r : TruthRaw) (ach : Bool) (it : TItem), it ∈ truthItems o r none none ach →
      (it.cls = .lean ∨ it.cls = .neutralLean) → it.status = .na :=
  ⟨by decide +kernel, by decide +kernel, fun o r ach it h hc => truthItems_lean_na_no_vector o r ach it h hc⟩

/-- Whether the part's key changes along a sweep.

$$\forall u, w,\quad \operatorname{moves}_u(w) \iff \exists i \ge 1,\ \kappa_u(s_i) \ne \kappa_u(s_0) \quad (w = (s_0, s_1, \dots);\ \text{false for no stops})$$

A sweep the part must run. -/
def keyMoves (u : PartUse) (w : Sweep) : Bool :=
  match w.stops with
  | [] => false
  | e0 :: rest => rest.any fun e => u.key e != u.key e0

/-- **The sweep scope**: the sweeps along which the part's key changes.

$$\forall u,\quad K(u) = [\,w \in W \mid \operatorname{moves}_u(w)\,]$$

A sweep with a constant key is a fresh load repeated, which the scoped loads already show. -/
def scopeSweeps (u : PartUse) : List Sweep := sweeps.filter (keyMoves u)

/-! ### Facts about the four pilot scopes (checked by the kernel) -/

/-- Every reachable class is in the scope, on every port.

$$\forall u \in \mathrm{pilot},\ \forall \pi \in \mathcal P,\ \forall p \in M,\quad \rho_\pi(e(p)) = \bot \implies \exists q \in S(u),\ \rho_\pi(e(q)) = \bot \wedge \kappa_u(e(q)) = \kappa_u(e(p))$$

The scope shows every key the full matrix shows, on the same port. -/
theorem scope_covers :
    (pilotParts.all fun u => ports.all fun π => matrix.all fun p =>
      !(envReason π p.env).isNone ||
        (scopeProbes u).any fun q => (envReason π q.env).isNone && u.key q.env == u.key p.env) = true := by
  decide +kernel

/-- Every sweep left out has a constant key that a reachable scoped load shows, on every port.

$$\forall u \in \mathrm{pilot},\ \forall \pi \in \mathcal P,\ \forall w \in W,\quad \neg\operatorname{moves}_u(w) \implies \exists q \in S(u),\ \rho_\pi(e(q)) = \bot \wedge \forall x \in w,\ \kappa_u(x) = \kappa_u(e(q))$$

Dropping a flat sweep loses no verdict. -/
theorem scope_sweeps_covered :
    (pilotParts.all fun u => ports.all fun π => sweeps.all fun w =>
      keyMoves u w || (scopeProbes u).any fun q =>
        (envReason π q.env).isNone && w.stops.all fun x => u.key x == u.key q.env) = true := by
  decide +kernel

/-- **Edges stay observed inside the scope.** For every edge query of every pilot part and every edge it lists,
the scope holds two loads of one block that agree on every discrete feature, sit at `N` and `N+1` on the edge's
axis, and give the query different values.

$$\forall u \in \mathrm{pilot},\ \forall q \in Q_E(u),\ \forall (a, N) \in E(q),\ \exists p, p' \in S(u),\quad a(p) = N \wedge a(p') = N{+}1 \wedge \mathrm{blk}(p) = \mathrm{blk}(p') \wedge p \sim p' \wedge \llbracket q \rrbracket_p \ne \llbracket q \rrbracket_{p'}$$

An off-by-one edge in the rewrite would still show up in a scoped run. -/
theorem scope_observes_edges :
    (pilotParts.all fun u => u.edgeQueries.all fun q => q.taggedEdges.all fun (tag, n) =>
      (scopeProbes u).any fun p => (scopeProbes u).any fun p' =>
        axisOf tag p.env == .ofNat n && axisOf tag p'.env == .ofNat (n + 1) && p.block == p'.block &&
          decide (Agree p.env p'.env) && q.eval p.env != q.eval p'.env) = true := by
  decide +kernel

/-- Every port reaches some matrix load.

$$\forall \pi \in \mathcal P,\ \exists p \in M,\quad \rho_\pi(e(p)) = \bot$$

No port sees an all-unreachable matrix. -/
theorem matrix_some_reachable : (ports.all fun π => matrix.any fun p => (envReason π p.env).isNone) = true := by
  decide +kernel

/-- Every port is in `ports`.

$$\forall \pi,\quad \pi \in \mathcal P$$

The list of ports is complete. -/
theorem mem_ports (π : Port) : π ∈ ports := by cases π <;> simp [ports]

/-- **Scoped runs keep each pilot part's verdict.** For a pilot part $u$, any port, any verdict function
$\mathrm{hv}$ of key histories that never says unreachable (hypothesis H), and any run whose loads $S_r$ lie between
the scope and the matrix and whose sweeps $K_r$ lie between the sweep scope and all sweeps, the part's verdict over
the run equals its verdict over the full matrix and all sweeps.

$$\begin{aligned} &\forall u \in \mathrm{pilot},\ \forall \pi \in \mathcal P,\ \forall \mathrm{hv} : (\mathbb B^*)^* \to \mathcal V,\ \forall S_r \in \mathrm{Probe}^*,\ \forall K_r \in \mathrm{Sweep}^*, \\ &\quad (\forall h,\ \neg\operatorname{isU}(\mathrm{hv}(h))) \wedge S(u) \subseteq S_r \subseteq M \wedge K(u) \subseteq K_r \subseteq W \implies V_{\rho_\pi,\kappa_u,\mathrm{hv}}(S_r, K_r) = V_{\rho_\pi,\kappa_u,\mathrm{hv}}(M, W) \end{aligned}$$

Running only the part's scope, alone or together with other parts' scopes, gives the full matrix's verdict. -/
theorem scope_sound (u : PartUse) (hu : u ∈ pilotParts) (π : Port) (hv : List (List Bool) → Verdict)
    (hU : ∀ h, (hv h).isUnreachable = false) (S : List Probe) (K : List Sweep)
    (hS1 : ∀ p ∈ scopeProbes u, p ∈ S) (hS2 : ∀ p ∈ S, p ∈ matrix)
    (hK1 : ∀ w ∈ scopeSweeps u, w ∈ K) (hK2 : ∀ w ∈ K, w ∈ sweeps) :
    scopedVerdict (envReason π) u.key hv S K = scopedVerdict (envReason π) u.key hv matrix sweeps := by
  have hπ := mem_ports π
  apply scoped_verdict_eq _ _ hv hU S matrix K sweeps hS2 hK2
  · intro p hp hr
    have h := scope_covers
    simp only [List.all_eq_true] at h
    have h' := h u hu π hπ p hp
    simp only [hr, Option.isNone_none, Bool.not_true, Bool.false_or, List.any_eq_true, Bool.and_eq_true,
      Option.isNone_iff_eq_none, beq_iff_eq] at h'
    obtain ⟨q, hq, hqr, hqk⟩ := h'
    exact ⟨q, hS1 q hq, hqr, hqk⟩
  · intro w hw hwK
    have hmv : keyMoves u w = false := by
      cases hm : keyMoves u w with
      | false => rfl
      | true => exact absurd (hK1 w (List.mem_filter.mpr ⟨hw, hm⟩)) hwK
    have h := scope_sweeps_covered
    simp only [List.all_eq_true] at h
    have h' := h u hu π hπ w hw
    simp only [hmv, Bool.false_or, List.any_eq_true, Bool.and_eq_true, Option.isNone_iff_eq_none,
      List.all_eq_true, beq_iff_eq] at h'
    obtain ⟨q, hq, hqr, hqk⟩ := h'
    exact ⟨q, hS1 q hq, hqr, hqk⟩
  · have h := matrix_some_reachable
    simp only [List.all_eq_true, List.any_eq_true, Option.isNone_iff_eq_none] at h
    exact h π hπ

/-- With every pilot part's scope run together, each part keeps its verdict (the union run of `--parts` with
several parts).

$$\forall u \in \mathrm{pilot},\ \forall \pi \in \mathcal P,\ \forall \mathrm{hv},\quad (\forall h,\ \neg\operatorname{isU}(\mathrm{hv}(h))) \implies V_{\rho_\pi,\kappa_u,\mathrm{hv}}(S_\cup, K_\cup) = V_{\rho_\pi,\kappa_u,\mathrm{hv}}(M, W),\quad S_\cup = [\,p \in M \mid \exists u' \in \mathrm{pilot},\ p \in S(u')\,],\ K_\cup = [\,w \in W \mid \exists u' \in \mathrm{pilot},\ w \in K(u')\,]$$

The union of scopes is a valid run for each part in it. -/
theorem scope_union_sound (u : PartUse) (hu : u ∈ pilotParts) (π : Port) (hv : List (List Bool) → Verdict)
    (hU : ∀ h, (hv h).isUnreachable = false) :
    scopedVerdict (envReason π) u.key hv
        (matrix.filter fun p => pilotParts.any fun u' => (scopeProbes u').any (·.id == p.id))
        (sweeps.filter fun w => pilotParts.any fun u' => (scopeSweeps u').any (·.id == w.id)) =
      scopedVerdict (envReason π) u.key hv matrix sweeps := by
  apply scope_sound u hu π hv hU
  · intro p hp
    refine List.mem_filter.mpr ⟨scopeProbes_sub u p hp, List.any_eq_true.mpr ⟨u, hu, ?_⟩⟩
    exact List.any_eq_true.mpr ⟨p, hp, beq_self_eq_true _⟩
  · exact fun p hp => (List.mem_filter.mp hp).1
  · intro w hw
    refine List.mem_filter.mpr ⟨(List.mem_filter.mp hw).1, List.any_eq_true.mpr ⟨u, hu, ?_⟩⟩
    exact List.any_eq_true.mpr ⟨w, hw, beq_self_eq_true _⟩
  · exact fun w hw => (List.mem_filter.mp hw).1

end Fw.Gate
