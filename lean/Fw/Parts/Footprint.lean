/-! Code footprint of the parts: the access records `apps/site/scripts/part-footprint.mjs` extracts from each part
folder's TS and CSS, the rule that sorts an access into a phase, and the signal wires a read or write carries.
`Fw.Parts.Contract` diffs these wires against its rows; the extractor's data is `Fw.Parts.FootprintData`. -/

namespace Fw.Parts.Footprint

/-- Kind of an extracted access. Reads: box (`rect`), viewport, scroll offset, clock, media query, event listener,
scroll-list registration, hit test, computed style, attribute, class, and the CSS reads `var()`, `[attr]`,
`:global(.c)`, `:has()` and a custom property defined from another. Writes: custom property, inline style, class,
CSS-module class, attribute, window scroll.

$$\mathrm{op} \in \{\mathrm{rect}, \mathrm{vw}, \mathrm{vh}, \mathrm{scrollY}, \mathrm{clock}, \mathrm{media},
\mathrm{listen}, \mathrm{register}, \mathrm{hitTest}, \mathrm{styleRead}, \mathrm{attrRead}, \mathrm{classRead},
\mathrm{cssVar}, \mathrm{cssAttr}, \mathrm{cssClass}, \mathrm{cssHas}, \mathrm{cssAlias}, \mathrm{setVar},
\mathrm{setStyle}, \mathrm{setClass}, \mathrm{setModuleClass}, \mathrm{setAttr}, \mathrm{scroll}\}$$

The constructor names are the `op` strings of the footprint golden. -/
inductive Op
  | rect | vw | vh | scrollY | clock | media | listen | register | hitTest | styleRead | attrRead | classRead
  | cssVar | cssAttr | cssClass | cssHas | cssAlias
  | setVar | setStyle | setClass | setModuleClass | setAttr | scroll
deriving Repr, DecidableEq, Inhabited

/-- Every op, in constructor order. $$\mathrm{ops} = [\mathrm{rect}, \dots, \mathrm{scroll}]$$
Each constructor once. -/
def Op.all : List Op :=
  [.rect, .vw, .vh, .scrollY, .clock, .media, .listen, .register, .hitTest, .styleRead, .attrRead, .classRead,
   .cssVar, .cssAttr, .cssClass, .cssHas, .cssAlias, .setVar, .setStyle, .setClass, .setModuleClass, .setAttr, .scroll]

/-- Golden name of an op. $$\operatorname{name}(\mathrm{op}) = \text{the constructor name}$$
The `op` field of a footprint record. -/
def Op.name : Op → String
  | .rect => "rect" | .vw => "vw" | .vh => "vh" | .scrollY => "scrollY" | .clock => "clock" | .media => "media"
  | .listen => "listen" | .register => "register" | .hitTest => "hitTest" | .styleRead => "styleRead"
  | .attrRead => "attrRead" | .classRead => "classRead" | .cssVar => "cssVar" | .cssAttr => "cssAttr"
  | .cssClass => "cssClass" | .cssHas => "cssHas" | .cssAlias => "cssAlias" | .setVar => "setVar"
  | .setStyle => "setStyle" | .setClass => "setClass" | .setModuleClass => "setModuleClass" | .setAttr => "setAttr"
  | .scroll => "scroll"

/-- Op of a golden name, the first op in `Op.all` carrying it.
$$\operatorname{ofName}(s) = \begin{cases} \mathrm{some}(o) & o \text{ the first } o \in \mathrm{ops} \text{ with }
\operatorname{name}(o) = s \\ \mathrm{none} & \text{no op has name } s \end{cases}$$
Inverse of `Op.name`. -/
def Op.ofName (s : String) : Option Op := Op.all.find? (·.name == s)

/-- Reading back a golden name gives the op.
$$\forall o \in \mathrm{Op},\ \operatorname{ofName}(\operatorname{name}(o)) = \mathrm{some}(o)$$
So distinct ops have distinct names. -/
theorem Op.ofName_name : ∀ o : Op, Op.ofName o.name = some o := by
  intro o; cases o <;> decide

/-- The golden names tell the ops apart.
$$\forall a\, b \in \mathrm{Op},\ \operatorname{name}(a) = \operatorname{name}(b) \to a = b$$
So the golden's `op` field determines the op. -/
theorem Op.name_injective (a b : Op) (h : a.name = b.name) : a = b := by
  have hb := Op.ofName_name b
  rw [← h, Op.ofName_name] at hb
  exact Option.some.inj hb

/-- `Op.all` lists every op. $$\forall o \in \mathrm{Op},\ o \in \mathrm{ops}$$
The enumeration is complete. -/
theorem Op.mem_all : ∀ o : Op, o ∈ Op.all := by
  intro o; cases o <;> decide

/-- A write op: it changes a property, class, attribute or the scroll offset.
$$\operatorname{isWrite}(o) \iff o \in \{\mathrm{setVar}, \mathrm{setStyle}, \mathrm{setClass}, \mathrm{setModuleClass},
\mathrm{setAttr}, \mathrm{scroll}\}$$
Every other op reads. -/
def Op.isWrite : Op → Bool
  | .setVar | .setStyle | .setClass | .setModuleClass | .setAttr | .scroll => true
  | _ => false

/-- One extracted access. `part`: the part whose code runs it; `file`, `line`: its site under `apps/site/src/parts/`;
`name`: the property, class, attribute, query, event or order it names; `owner`: the part id rendering the element it
touches (`""` for a CSS read of any element, `"?"` unresolved, `"document"` the window or document, a trailing `^` an
element's parent); `ctx`: the callback it runs in.

$$a = (\mathrm{part}, \mathrm{file}, \mathrm{line}, \mathrm{op}, \mathrm{name}, \mathrm{owner}, \mathrm{ctx})$$

One golden record. -/
structure Access where
  part : String
  file : String
  line : Nat
  op : Op
  name : String
  owner : String
  ctx : String
deriving Repr, DecidableEq, Inhabited

/-- One extractor finding: an unresolved target, a dead, dynamic or templated selector, a dynamic class.
$$f = (\mathrm{part}, \mathrm{file}, \mathrm{line}, \mathrm{kind}, \mathrm{detail})$$
One golden record. -/
structure Finding where
  part : String
  file : String
  line : Nat
  kind : String
  detail : String
deriving Repr, DecidableEq, Inhabited

/-- When an access runs. `frame`: scroll, wheel, touch, pointer-move, clock, timer, observer and render callbacks and
CSS; `event`: click, key and other handlers; `hover`: enter, leave, focus and blur; `mount`: effects, module code,
props, refs and page show; `resize`: window resize and media-query change; `cleanup`: effect teardown.

$$\phi \in \{\mathrm{frame}, \mathrm{event}, \mathrm{hover}, \mathrm{mount}, \mathrm{resize}, \mathrm{cleanup}\}$$

The contract counts frame writes as outputs and event writes as `onEvent`. -/
inductive Phase | frame | event | hover | mount | resize | cleanup
deriving Repr, DecidableEq

/-- Callback tags that run on hover or focus.
$$H = [\texttt{jsx:onPointerEnter}, \dots, \texttt{listener:focusout}]$$
React handler and DOM listener spellings. -/
def hoverCtx : List String :=
  ["jsx:onPointerEnter", "jsx:onPointerLeave", "jsx:onMouseEnter", "jsx:onMouseLeave", "jsx:onFocus", "jsx:onBlur",
   "listener:pointerenter", "listener:pointerleave", "listener:mouseenter", "listener:mouseleave", "listener:focus",
   "listener:blur", "listener:focusin", "listener:focusout"]

/-- Callback tags that run once per mount. $$M = [\texttt{effect}, \texttt{module}, \texttt{props}, \texttt{ref},
\texttt{listener:pageshow}]$$ `props`: a JSX value computed only from props, imports and module constants. -/
def mountCtx : List String := ["effect", "module", "props", "ref", "listener:pageshow"]

/-- DOM listeners that fire at frame time.
$$F = [\texttt{listener:scroll}, \texttt{listener:scrollend}, \texttt{listener:wheel}, \texttt{listener:touchstart},
\texttt{listener:touchmove}, \texttt{listener:touchend}, \texttt{listener:pointerdown}, \texttt{listener:pointermove},
\texttt{listener:pointerup}, \texttt{listener:pointercancel}]$$
Any other `listener:` tag is an event, hover or mount tag. -/
def frameListeners : List String :=
  ["listener:scroll", "listener:scrollend", "listener:wheel", "listener:touchstart", "listener:touchmove",
   "listener:touchend", "listener:pointerdown", "listener:pointermove", "listener:pointerup", "listener:pointercancel"]

/-- Phase of a callback tag, first match.

$$\phi(c) = \begin{cases} \mathrm{cleanup} & c = \texttt{cleanup} \\ \mathrm{mount} & c \in M \\
\mathrm{resize} & c = \texttt{listener:resize} \lor \texttt{listener:media-} \sqsubseteq c \\
\mathrm{hover} & c \in H \\
\mathrm{event} & \texttt{jsx:} \sqsubseteq c \lor (\texttt{listener:} \sqsubseteq c \land c \notin F) \\
\mathrm{frame} & \text{otherwise} \end{cases}$$

$\sqsubseteq$ is "is a prefix of"; an unknown tag counts as frame. -/
def phase (ctx : String) : Phase :=
  if ctx == "cleanup" then .cleanup
  else if mountCtx.contains ctx then .mount
  else if ctx == "listener:resize" || ctx.startsWith "listener:media-" then .resize
  else if hoverCtx.contains ctx then .hover
  else if ctx.startsWith "jsx:" || (ctx.startsWith "listener:" && !frameListeners.contains ctx) then .event
  else .frame

/-- Listener types that carry pointer, wheel or touch input.
$$\Pi = [\texttt{pointerdown}, \texttt{pointermove}, \texttt{pointerup}, \texttt{pointercancel}, \texttt{wheel},
\texttt{touchstart}, \texttt{touchmove}, \texttt{touchend}, \texttt{mousedown}, \texttt{mousemove}]$$
Contract signal `pointer`. -/
def pointerTypes : List String :=
  ["pointerdown", "pointermove", "pointerup", "pointercancel", "wheel", "touchstart", "touchmove", "touchend",
   "mousedown", "mousemove"]

/-- Text after the last `#` (the local class of `file#local`).
$$\operatorname{local}(s) = \begin{cases} s_{k+1..} & k \text{ the last position of } \texttt{\#} \text{ in } s \\ s &
\texttt{\#} \notin s \end{cases}$$
The whole string when it has no `#`. -/
def localName (s : String) : String := (s.splitOn "#").getLastD s

/-- Wires a read access feeds, as `Signal.wire` strings; owner `*` is a CSS read of any element.

$$\operatorname{reads}(a) = \begin{cases}
[\texttt{rect:}w] & \mathrm{op} = \mathrm{rect},\ w = \mathrm{owner} \text{ or } \texttt{?} \text{ if owner} = \texttt{""} \\
[\mathrm{op}] & \mathrm{op} \in \{\mathrm{vw}, \mathrm{vh}, \mathrm{scrollY}, \mathrm{clock}\} \\
[\,] & \mathrm{op} = \mathrm{media},\ \texttt{mq.rm-} \sqsubseteq n \\
[\texttt{vh}] & \mathrm{op} = \mathrm{media},\ \texttt{mq.h-} \sqsubseteq n \\
[\texttt{vw}, \texttt{vh}] & \mathrm{op} = \mathrm{media},\ n = \texttt{?} \\
[\texttt{vw}] & \mathrm{op} = \mathrm{media} \text{ otherwise} \\
[\texttt{pointer}] & \mathrm{op} = \mathrm{listen},\ n \in \Pi \\
[\texttt{scrollY}] & \mathrm{op} = \mathrm{listen},\ n \in \{\texttt{scroll}, \texttt{scrollend}\} \\
[\texttt{vw}, \texttt{vh}] & \mathrm{op} = \mathrm{listen},\ n = \texttt{resize} \\
[\texttt{className:}n/w] & \mathrm{op} \in \{\mathrm{attrRead}, \mathrm{classRead}, \mathrm{cssAttr},
  \mathrm{cssClass}, \mathrm{cssHas}\},\ w = \mathrm{owner} \text{ or } \texttt{*} \text{ if owner} = \texttt{""} \\
[\texttt{cssVar:}n/\texttt{*}] & \mathrm{op} = \mathrm{cssVar} \\
[\,] & \text{otherwise (other listeners, register, hitTest, styleRead, cssAlias, writes)}
\end{cases}$$

$n$ is the access name; cleanup accesses read nothing. -/
def reads (a : Access) : List String :=
  if phase a.ctx == .cleanup then [] else
  let w := if a.owner == "" then "*" else a.owner
  match a.op with
  | .rect => ["rect:" ++ (if a.owner == "" then "?" else a.owner)]
  | .vw => ["vw"] | .vh => ["vh"] | .scrollY => ["scrollY"] | .clock => ["clock"]
  | .media =>
    if a.name.startsWith "mq.rm-" then []
    else if a.name.startsWith "mq.h-" then ["vh"]
    else if a.name == "?" then ["vw", "vh"]
    else ["vw"]
  | .listen =>
    if pointerTypes.contains a.name then ["pointer"]
    else if a.name == "scroll" || a.name == "scrollend" then ["scrollY"]
    else if a.name == "resize" then ["vw", "vh"]
    else []
  | .attrRead | .classRead | .cssAttr | .cssClass | .cssHas => ["className:" ++ a.name ++ "/" ++ w]
  | .cssVar => ["cssVar:" ++ a.name ++ "/*"]
  | _ => []

/-- Wire a write access sets, as a `Signal.wire` string.

$$\operatorname{writes}(a) = \begin{cases}
[\texttt{cssVar:}n/\mathrm{owner}] & \mathrm{op} \in \{\mathrm{setVar}, \mathrm{setStyle}\} \\
[\texttt{className:}n/\mathrm{owner}] & \mathrm{op} \in \{\mathrm{setClass}, \mathrm{setAttr}\} \\
[\texttt{className:}\operatorname{local}(n)/\mathrm{owner}] & \mathrm{op} = \mathrm{setModuleClass} \\
[\texttt{scrollY}] & \mathrm{op} = \mathrm{scroll},\ \mathrm{owner} = \texttt{document} \\
[\,] & \text{otherwise}
\end{cases}$$

Inline style properties share the `cssVar` wire with custom properties, as the contract rows do; an element's own
scroll offset is not the page scroll position. -/
def writes (a : Access) : List String :=
  match a.op with
  | .setVar | .setStyle => ["cssVar:" ++ a.name ++ "/" ++ a.owner]
  | .setClass | .setAttr => ["className:" ++ a.name ++ "/" ++ a.owner]
  | .setModuleClass => ["className:" ++ localName a.name ++ "/" ++ a.owner]
  | .scroll => if a.owner == "document" then ["scrollY"] else []
  | _ => []

/-- A read access sets no wire.
$$\forall a,\ \neg \operatorname{isWrite}(a.\mathrm{op}) \to \operatorname{writes}(a) = [\,]$$
Only the six write ops produce outputs. -/
theorem writes_nil_of_read (a : Access) (h : a.op.isWrite = false) : writes a = [] := by
  cases a with
  | mk part file line op name owner ctx => cases op <;> simp_all [writes, Op.isWrite]

/-- A write access feeds no read wire.
$$\forall a,\ \operatorname{isWrite}(a.\mathrm{op}) \to \operatorname{reads}(a) = [\,]$$
An access is an input or an output, never both. -/
theorem reads_nil_of_write (a : Access) (h : a.op.isWrite = true) : reads a = [] := by
  cases a with
  | mk part file line op name owner ctx => cases op <;> simp_all [reads, Op.isWrite]

/-- Teardown reads nothing.
$$\forall a,\ \phi(a.\mathrm{ctx}) = \mathrm{cleanup} \to \operatorname{reads}(a) = [\,]$$
An effect cleanup runs off the frame path. -/
theorem reads_cleanup (a : Access) (h : phase a.ctx = .cleanup) : reads a = [] := by
  simp [reads, h]

/-- Name and owner of a wire: the text before and after its last `/`; owner `""` when it has none.
$$\operatorname{split}(s) = \begin{cases} (p, o) & s = p\texttt{/}o,\ \texttt{/} \notin o \\ (s, \texttt{""}) &
\texttt{/} \notin s \end{cases}$$
A trailing `/` gives owner `""`. -/
def splitOwner (w : String) : String × String :=
  match (w.splitOn "/").reverse with
  | o :: rest@(_ :: _) => ("/".intercalate rest.reverse, o)
  | _ => (w, "")

/-- Do two wires name the same signal, up to an owner the extractor left open (`*` any element, `?` unresolved)?

$$\operatorname{same}(u, v) \iff u = v \lor (p_u = p_v \land o_u \ne \texttt{""} \land o_v \ne \texttt{""} \land
(o_u \in \{\texttt{*}, \texttt{?}\} \lor o_v \in \{\texttt{*}, \texttt{?}\})),\quad (p_u, o_u) =
\operatorname{split}(u),\ (p_v, o_v) = \operatorname{split}(v)$$

A wire with an empty owner (no `/` or a trailing one) matches only itself. -/
def same (u v : String) : Bool :=
  u == v ||
    let (pu, ou) := splitOwner u
    let (pv, ov) := splitOwner v
    pu == pv && ou != "" && ov != "" && (ou == "*" || ou == "?" || ov == "*" || ov == "?")

/-- Kind and name of a wire: the text before and after its first `:`; name `""` when it has none.
$$\operatorname{kind}(s) = \begin{cases} (k, n) & s = k\texttt{:}n,\ \texttt{:} \notin k \\ (s, \texttt{""}) &
\texttt{:} \notin s \end{cases}$$
The name keeps any later `:`. -/
def splitKind (w : String) : String × String :=
  match w.splitOn ":" with
  | k :: n :: rest => (k, ":".intercalate (n :: rest))
  | _ => (w, "")

/-- A wire pair back as text. $$\operatorname{join}(k, \texttt{""}) = k,\quad \operatorname{join}(k, n) = k\texttt{:}n
\ (n \ne \texttt{""})$$ The inverse of `splitKind` on the wires `reads` and `writes` produce. -/
def joinKind (w : String × String) : String := if w.2 == "" then w.1 else w.1 ++ ":" ++ w.2

/-- One part's contract fields as the code shows them, signals as (kind, name) wire pairs.
$$r = (\mathrm{id}, \mathrm{in}, \mathrm{out}, \mathrm{ev}, T, O)$$
`in`, `out` and `ev` are the code inputs and the frame and event cross-part writes; `T` the frame write owners; `O`
the scroll-list orders. -/
structure Row where
  id : String
  inputs : List (String × String)
  outputs : List (String × String)
  onEvent : List (String × String)
  targets : List String
  order : List Nat
deriving Repr

/-- JSON string literal. $$\operatorname{jstr}(s) = \texttt{"} \mathbin{+\!\!+} \operatorname{esc}(s) \mathbin{+\!\!+} \texttt{"}$$
`esc` escapes only backslash and double quote; the extractor writes no control characters. -/
def jstr (s : String) : String := "\"" ++ ((s.replace "\\" "\\\\").replace "\"" "\\\"") ++ "\""

/-- One access as its golden line. $$\{\mathrm{part}, \mathrm{file}, \mathrm{line}, \mathrm{op}, \mathrm{name},
\mathrm{owner}, \mathrm{ctx}\}$$ Keys in this order, no spaces. -/
def Access.json (a : Access) : String :=
  "{\"part\":" ++ jstr a.part ++ ",\"file\":" ++ jstr a.file ++ ",\"line\":" ++ toString a.line ++
    ",\"op\":" ++ jstr a.op.name ++ ",\"name\":" ++ jstr a.name ++ ",\"owner\":" ++ jstr a.owner ++
    ",\"ctx\":" ++ jstr a.ctx ++ "}"

/-- One finding as its golden line. $$\{\mathrm{part}, \mathrm{file}, \mathrm{line}, \mathrm{kind}, \mathrm{detail}\}$$
Keys in this order, no spaces. -/
def Finding.json (f : Finding) : String :=
  "{\"part\":" ++ jstr f.part ++ ",\"file\":" ++ jstr f.file ++ ",\"line\":" ++ toString f.line ++
    ",\"kind\":" ++ jstr f.kind ++ ",\"detail\":" ++ jstr f.detail ++ "}"

/-- Text of `packages/contracts/golden/parts/footprint.gen.json`.

$$\operatorname{golden}(I, A, F) = \{\mathrm{parts}: I,\ \mathrm{accesses}: [a.\mathrm{json} \mid a \in A],\
\mathrm{findings}: [f.\mathrm{json} \mid f \in F]\}$$

One record per line, newline-terminated; an empty list renders as `[` newline newline `]`, as the extractor writes it. -/
def golden (ids : List String) (as : List Access) (fs : List Finding) : String :=
  "{\"parts\":[" ++ ",".intercalate (ids.map jstr) ++ "],\n\"accesses\":[\n" ++
    ",\n".intercalate (as.map Access.json) ++ "\n],\n\"findings\":[\n" ++
    ",\n".intercalate (fs.map Finding.json) ++ "\n]}\n"

private def ex (op : Op) (name owner ctx : String) : Access := ⟨"p", "p/a.ts", 1, op, name, owner, ctx⟩

#guard phase "cleanup" == .cleanup && phase "effect" == .mount && phase "props" == .mount
#guard phase "listener:media-change" == .resize && phase "listener:resize" == .resize
#guard phase "jsx:onPointerEnter" == .hover && phase "jsx:onBlur" == .hover
#guard phase "jsx:onClick" == .event && phase "listener:keydown" == .event && phase "listener:click" == .event
#guard phase "listener:wheel" == .frame && phase "scroll" == .frame && phase "render" == .frame
#guard phase "observer:ResizeObserver" == .frame && phase "style" == .frame && phase "fn" == .frame
#guard reads (ex .rect "" "people.card" "scroll") == ["rect:people.card"]
#guard reads (ex .rect "" "" "scroll") == ["rect:?"]
#guard reads (ex .media "mq.rm-reduce" "" "effect") == [] && reads (ex .media "mq.c1000" "" "effect") == ["vw"]
#guard reads (ex .media "?" "" "effect") == ["vw", "vh"] && reads (ex .media "mq.h-le-700" "" "effect") == ["vh"]
#guard reads (ex .listen "touchmove" "document" "effect") == ["pointer"]
#guard reads (ex .listen "scrollend" "document" "effect") == ["scrollY"]
#guard reads (ex .cssAttr "data-o-stack" "" "style") == ["className:data-o-stack/*"]
#guard reads (ex .cssAttr "data-scene" "commission" "style") == ["className:data-scene/commission"]
#guard reads (ex .cssVar "--morph" "" "style") == ["cssVar:--morph/*"]
#guard reads (ex .rect "" "pain" "cleanup") == []
#guard writes (ex .setModuleClass "people.o/o.module.css#isStack" "people.o" "render") == ["className:isStack/people.o"]
#guard writes (ex .setStyle "height" "commission" "scroll") == ["cssVar:height/commission"]
#guard writes (ex .scroll "" "document" "listener:wheel") == ["scrollY"] && writes (ex .scroll "" "p" "timer") == []
#guard writes (ex .rect "" "pain" "scroll") == []
#guard same "className:data-o-stack/*" "className:data-o-stack/people.o" && same "cssVar:--x/?" "cssVar:--x/nav"
#guard !same "className:data-o/*" "className:data-o-stack/people.o" && !same "cssVar:--x/" "cssVar:--x/*"
#guard same "rect:pain" "rect:pain" && !same "rect:pain" "rect:pain.notes" && splitOwner "a/b/c" == ("a/b", "c")
#guard splitKind "cssVar:--x/nav" == ("cssVar", "--x/nav") && splitKind "vw" == ("vw", "")
#guard splitKind "className:a:b/c" == ("className", "a:b/c") && joinKind ("vw", "") == "vw"
#guard ["vw", "rect:?", "cssVar:--x/nav", "className:a:b/c"].all fun w => joinKind (splitKind w) == w
#guard golden ["a"] [] [] == "{\"parts\":[\"a\"],\n\"accesses\":[\n\n],\n\"findings\":[\n\n]}\n"

end Fw.Parts.Footprint
