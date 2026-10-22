/-! Code footprint of the parts: the access records `apps/site/scripts/part-footprint.mjs` extracts from each part
folder's TS and CSS, the rule that sorts an access into a phase, and the signal wires a read or write carries.
`Fw.Parts.Contract` diffs these wires against its rows; the extractor's data is `Fw.Parts.FootprintData`. -/

namespace Fw.Parts.Footprint

/-- Kind of an extracted access. Reads: box (`rect`), viewport, scroll offset, clock, media query, event listener,
scroll-list registration, hit test, computed style, attribute, class, and the CSS reads `var()`, `[attr]`,
`:global(.c)`, `:has()` and a custom property defined from another. Writes: custom property, inline style, class,
CSS-module class, attribute, scroll offset, element content (text or child nodes).

The constructor names are the `op` strings of the footprint golden. -/
inductive Op
  | rect | vw | vh | scrollY | clock | media | listen | register | hitTest | styleRead | attrRead | classRead
  | cssVar | cssAttr | cssClass | cssHas | cssAlias
  | setVar | setStyle | setClass | setModuleClass | setAttr | scroll | setContent
deriving Repr, DecidableEq, Inhabited

/-- Every op, in constructor order.
Each constructor once. -/
def Op.all : List Op :=
  [.rect, .vw, .vh, .scrollY, .clock, .media, .listen, .register, .hitTest, .styleRead, .attrRead, .classRead,
   .cssVar, .cssAttr, .cssClass, .cssHas, .cssAlias, .setVar, .setStyle, .setClass, .setModuleClass, .setAttr, .scroll,
   .setContent]

/-- Golden name of an op.
The `op` field of a footprint record. -/
def Op.name : Op → String
  | .rect => "rect" | .vw => "vw" | .vh => "vh" | .scrollY => "scrollY" | .clock => "clock" | .media => "media"
  | .listen => "listen" | .register => "register" | .hitTest => "hitTest" | .styleRead => "styleRead"
  | .attrRead => "attrRead" | .classRead => "classRead" | .cssVar => "cssVar" | .cssAttr => "cssAttr"
  | .cssClass => "cssClass" | .cssHas => "cssHas" | .cssAlias => "cssAlias" | .setVar => "setVar"
  | .setStyle => "setStyle" | .setClass => "setClass" | .setModuleClass => "setModuleClass" | .setAttr => "setAttr"
  | .scroll => "scroll" | .setContent => "setContent"

/-- Op of a golden name, the first op in `Op.all` carrying it.
Inverse of `Op.name`. -/
def Op.ofName (s : String) : Option Op := Op.all.find? (·.name == s)

/-- Reading back a golden name gives the op.
So distinct ops have distinct names. -/
theorem Op.ofName_name : ∀ o : Op, Op.ofName o.name = some o := by
  intro o; cases o <;> decide

/-- The golden names tell the ops apart.
So the golden's `op` field determines the op. -/
theorem Op.name_injective (a b : Op) (h : a.name = b.name) : a = b := by
  have hb := Op.ofName_name b
  rw [← h, Op.ofName_name] at hb
  exact Option.some.inj hb

/-- `Op.all` lists every op.
The enumeration is complete. -/
theorem Op.mem_all : ∀ o : Op, o ∈ Op.all := by
  intro o; cases o <;> decide

/-- A write op: it changes a property, class, attribute, the scroll offset or an element's content.
Every other op reads. -/
def Op.isWrite : Op → Bool
  | .setVar | .setStyle | .setClass | .setModuleClass | .setAttr | .scroll | .setContent => true
  | _ => false

/-- One extracted access. `part`: the part whose code runs it; `file`, `line`: its site under `apps/site/src/parts/`;
`name`: the property, class, attribute, query, event or order it names; `owner`: the part id rendering the element it
touches (`""` for a CSS read of any element, `"?"` unresolved, `"document"` the window or document, a trailing `^` an
element's parent); `ctx`: the callback it runs in; `variants`: the part.json variants whose files contain the site
(all of them when the part lists no files).

One golden record. -/
structure Access where
  part : String
  file : String
  line : Nat
  op : Op
  name : String
  owner : String
  ctx : String
  variants : List String
deriving Repr, DecidableEq, Inhabited

/-- One extractor finding: an unresolved target, a dead, dynamic or templated selector, a dynamic class.
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

The contract counts frame writes as outputs and event writes as `onEvent`. -/
inductive Phase | frame | event | hover | mount | resize | cleanup
deriving Repr, DecidableEq

/-- Callback tags that run on hover or focus.
React handler and DOM listener spellings. -/
def hoverCtx : List String :=
  ["jsx:onPointerEnter", "jsx:onPointerLeave", "jsx:onMouseEnter", "jsx:onMouseLeave", "jsx:onFocus", "jsx:onBlur",
   "listener:pointerenter", "listener:pointerleave", "listener:mouseenter", "listener:mouseleave", "listener:focus",
   "listener:blur", "listener:focusin", "listener:focusout"]

/-- Callback tags that run once per mount. `props`: a JSX value computed only from props, imports and module constants. -/
def mountCtx : List String := ["effect", "module", "props", "ref", "listener:pageshow"]

/-- DOM listeners that fire at frame time.
Any other `listener:` tag is an event, hover or mount tag. -/
def frameListeners : List String :=
  ["listener:scroll", "listener:scrollend", "listener:wheel", "listener:touchstart", "listener:touchmove",
   "listener:touchend", "listener:pointerdown", "listener:pointermove", "listener:pointerup", "listener:pointercancel"]

/-- Phase of a callback tag, first match.

`⊑` is "is a prefix of"; an unknown tag counts as frame. -/
def phase (ctx : String) : Phase :=
  if ctx == "cleanup" then .cleanup
  else if mountCtx.contains ctx then .mount
  else if ctx == "listener:resize" || ctx.startsWith "listener:media-" then .resize
  else if hoverCtx.contains ctx then .hover
  else if ctx.startsWith "jsx:" || (ctx.startsWith "listener:" && !frameListeners.contains ctx) then .event
  else .frame

/-- Listener types that carry pointer, wheel or touch input.
Contract signal `pointer`. -/
def pointerTypes : List String :=
  ["pointerdown", "pointermove", "pointerup", "pointercancel", "wheel", "touchstart", "touchmove", "touchend",
   "mousedown", "mousemove"]

/-- Text after the last `#` (the local class of `file#local`).
The whole string when it has no `#`. -/
def localName (s : String) : String := (s.splitOn "#").getLastD s

/-- Wires a read access feeds, as `Signal.wire` strings; owner `*` is a CSS read of any element.

`n` is the access name; the first matching case applies, so every case after the first assumes
`φ(a.ctx) ≠ cleanup`. -/
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

Inline style properties share the `cssVar` wire with custom properties, as the contract rows do; an element's own
scroll offset is not the page scroll position; new text or child nodes change the owner's box, and a content write
to an unresolved element feeds no wire (its `unresolved-target` finding records it). -/
def writes (a : Access) : List String :=
  match a.op with
  | .setVar | .setStyle => ["cssVar:" ++ a.name ++ "/" ++ a.owner]
  | .setClass | .setAttr => ["className:" ++ a.name ++ "/" ++ a.owner]
  | .setModuleClass => ["className:" ++ localName a.name ++ "/" ++ a.owner]
  | .scroll => if a.owner == "document" then ["scrollY"] else []
  | .setContent => if a.owner == "" || a.owner == "?" then [] else ["rect:" ++ a.owner]
  | _ => []

/-- A read access sets no wire.
Only the seven write ops produce outputs. -/
theorem writes_nil_of_read (a : Access) (h : a.op.isWrite = false) : writes a = [] := by
  cases a with
  | mk part file line op name owner ctx vs => cases op <;> simp_all [writes, Op.isWrite]

/-- A write access feeds no read wire.
An access is an input or an output, never both. -/
theorem reads_nil_of_write (a : Access) (h : a.op.isWrite = true) : reads a = [] := by
  cases a with
  | mk part file line op name owner ctx vs => cases op <;> simp_all [reads, Op.isWrite]

/-- Teardown reads nothing.
An effect cleanup runs off the frame path. -/
theorem reads_cleanup (a : Access) (h : phase a.ctx = .cleanup) : reads a = [] := by
  simp [reads, h]

/-- Name and owner of a wire: the text before and after its last `/`; owner `""` when it has none.
A trailing `/` gives owner `""`. -/
def splitOwner (w : String) : String × String :=
  match (w.splitOn "/").reverse with
  | o :: rest@(_ :: _) => ("/".intercalate rest.reverse, o)
  | _ => (w, "")

/-- Kind and name of a wire: the text before and after its first `:`; name `""` when it has none.
The name keeps any later `:`. -/
def splitKind (w : String) : String × String :=
  match w.splitOn ":" with
  | k :: n :: rest => (k, ":".intercalate (n :: rest))
  | _ => (w, "")

/-- Do two wires name the same signal, up to an owner the extractor left open (`*` any element, `?` unresolved) and a
name it could not read (`?`, a dynamic property, class or attribute)?

A wire with an empty owner (no `/` or a trailing one) matches only itself. -/
def same (u v : String) : Bool :=
  u == v ||
    let (pu, ou) := splitOwner u
    let (pv, ov) := splitOwner v
    let (ku, nu) := splitKind pu
    let (kv, nv) := splitKind pv
    ou != "" && ov != "" && (ou == ov || ou == "*" || ou == "?" || ov == "*" || ov == "?") &&
      (pu == pv || (ku == kv && (nu == "?" || nv == "?")))

/-- A wire pair back as text. The inverse of `splitKind` on the wires `reads` and `writes` produce. -/
def joinKind (w : String × String) : String := if w.2 == "" then w.1 else w.1 ++ ":" ++ w.2

/-- An access the extractor could not fully resolve: its name or its owner is `?`.
Such an access couples through the wildcard of `same`, or not at all for a box read. -/
def Access.isOpen (a : Access) : Bool := a.name == "?" || a.owner == "?"

/-- Some finding sits at the access's site.
False for an empty finding list. -/
def flagged (fs : List Finding) (a : Access) : Bool :=
  fs.any fun f => f.part == a.part && f.file == a.file && f.line == a.line

/-- One part's contract fields as the code shows them, signals as (kind, name) wire pairs.
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

/-- JSON string literal.
`esc` escapes only backslash and double quote; the extractor writes no control characters. -/
def jstr (s : String) : String := "\"" ++ ((s.replace "\\" "\\\\").replace "\"" "\\\"") ++ "\""

/-- One access as its golden line. Keys in this order, no spaces. -/
def Access.json (a : Access) : String :=
  "{\"part\":" ++ jstr a.part ++ ",\"file\":" ++ jstr a.file ++ ",\"line\":" ++ toString a.line ++
    ",\"op\":" ++ jstr a.op.name ++ ",\"name\":" ++ jstr a.name ++ ",\"owner\":" ++ jstr a.owner ++
    ",\"ctx\":" ++ jstr a.ctx ++ ",\"variants\":[" ++ ",".intercalate (a.variants.map jstr) ++ "]}"

/-- One finding as its golden line.
Keys in this order, no spaces. -/
def Finding.json (f : Finding) : String :=
  "{\"part\":" ++ jstr f.part ++ ",\"file\":" ++ jstr f.file ++ ",\"line\":" ++ toString f.line ++
    ",\"kind\":" ++ jstr f.kind ++ ",\"detail\":" ++ jstr f.detail ++ "}"

/-- Text of `packages/contracts/golden/parts/footprint.gen.json`.

One record per line, newline-terminated; an empty list renders as `[` newline newline `]`, as the extractor writes it. -/
def golden (ids : List String) (as : List Access) (fs : List Finding) : String :=
  "{\"parts\":[" ++ ",".intercalate (ids.map jstr) ++ "],\n\"accesses\":[\n" ++
    ",\n".intercalate (as.map Access.json) ++ "\n],\n\"findings\":[\n" ++
    ",\n".intercalate (fs.map Finding.json) ++ "\n]}\n"

private def ex (op : Op) (name owner ctx : String) : Access := ⟨"p", "p/a.ts", 1, op, name, owner, ctx, ["faithful"]⟩

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
#guard same "cssVar:?/nav" "cssVar:--x/*" && same "cssVar:?/nav" "cssVar:--x/nav" && same "className:a/nav" "className:?/?"
#guard !same "cssVar:?/nav" "cssVar:--x/platform" && !same "cssVar:?/nav" "className:x/nav" && !same "cssVar:?/" "cssVar:x/"
#guard (ex .setStyle "?" "nav" "scroll").isOpen && (ex .rect "" "?" "scroll").isOpen && !(ex .rect "" "" "scroll").isOpen
#guard flagged [⟨"p", "p/a.ts", 1, "dynamic-name", "setStyle"⟩] (ex .setStyle "?" "nav" "scroll")
#guard !flagged [⟨"p", "p/a.ts", 2, "dynamic-name", "setStyle"⟩] (ex .setStyle "?" "nav" "scroll") && !flagged [] (ex .vw "" "" "x")
#guard writes (ex .setContent "textContent" "platform" "clock") == ["rect:platform"]
#guard writes (ex .setContent "data" "?" "clock") == [] && writes (ex .setContent "append" "" "clock") == []
#guard same "rect:pain" "rect:pain" && !same "rect:pain" "rect:pain.notes" && splitOwner "a/b/c" == ("a/b", "c")
#guard splitKind "cssVar:--x/nav" == ("cssVar", "--x/nav") && splitKind "vw" == ("vw", "")
#guard splitKind "className:a:b/c" == ("className", "a:b/c") && joinKind ("vw", "") == "vw"
#guard ["vw", "rect:?", "cssVar:--x/nav", "className:a:b/c"].all fun w => joinKind (splitKind w) == w
#guard (ex .vw "" "" "x").json ==
  "{\"part\":\"p\",\"file\":\"p/a.ts\",\"line\":1,\"op\":\"vw\",\"name\":\"\",\"owner\":\"\",\"ctx\":\"x\",\"variants\":[\"faithful\"]}"
#guard golden ["a"] [] [] == "{\"parts\":[\"a\"],\n\"accesses\":[\n\n],\n\"findings\":[\n\n]}\n"

end Fw.Parts.Footprint
