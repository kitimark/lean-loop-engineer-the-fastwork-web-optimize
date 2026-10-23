namespace Fw.Parts.Footprint

inductive Op
  | rect | vw | vh | scrollY | clock | media | listen | register | hitTest | styleRead | attrRead | classRead
  | cssVar | cssAttr | cssClass | cssHas | cssAlias
  | setVar | setStyle | setClass | setModuleClass | setAttr | scroll | setContent
deriving Repr, DecidableEq, Inhabited

def Op.all : List Op :=
  [.rect, .vw, .vh, .scrollY, .clock, .media, .listen, .register, .hitTest, .styleRead, .attrRead, .classRead,
   .cssVar, .cssAttr, .cssClass, .cssHas, .cssAlias, .setVar, .setStyle, .setClass, .setModuleClass, .setAttr, .scroll,
   .setContent]

def Op.name : Op → String
  | .rect => "rect" | .vw => "vw" | .vh => "vh" | .scrollY => "scrollY" | .clock => "clock" | .media => "media"
  | .listen => "listen" | .register => "register" | .hitTest => "hitTest" | .styleRead => "styleRead"
  | .attrRead => "attrRead" | .classRead => "classRead" | .cssVar => "cssVar" | .cssAttr => "cssAttr"
  | .cssClass => "cssClass" | .cssHas => "cssHas" | .cssAlias => "cssAlias" | .setVar => "setVar"
  | .setStyle => "setStyle" | .setClass => "setClass" | .setModuleClass => "setModuleClass" | .setAttr => "setAttr"
  | .scroll => "scroll" | .setContent => "setContent"

def Op.ofName (s : String) : Option Op := Op.all.find? (·.name == s)

theorem Op.ofName_name : ∀ o : Op, Op.ofName o.name = some o := by
  intro o; cases o <;> decide

theorem Op.name_injective (a b : Op) (h : a.name = b.name) : a = b := by
  have hb := Op.ofName_name b
  rw [← h, Op.ofName_name] at hb
  exact Option.some.inj hb

theorem Op.mem_all : ∀ o : Op, o ∈ Op.all := by
  intro o; cases o <;> decide

def Op.isWrite : Op → Bool
  | .setVar | .setStyle | .setClass | .setModuleClass | .setAttr | .scroll | .setContent => true
  | _ => false

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

structure Finding where
  part : String
  file : String
  line : Nat
  kind : String
  detail : String
deriving Repr, DecidableEq, Inhabited

inductive Phase | frame | event | hover | mount | resize | cleanup
deriving Repr, DecidableEq

def hoverCtx : List String :=
  ["jsx:onPointerEnter", "jsx:onPointerLeave", "jsx:onMouseEnter", "jsx:onMouseLeave", "jsx:onFocus", "jsx:onBlur",
   "listener:pointerenter", "listener:pointerleave", "listener:mouseenter", "listener:mouseleave", "listener:focus",
   "listener:blur", "listener:focusin", "listener:focusout"]

def mountCtx : List String := ["effect", "module", "props", "ref", "listener:pageshow"]

def frameListeners : List String :=
  ["listener:scroll", "listener:scrollend", "listener:wheel", "listener:touchstart", "listener:touchmove",
   "listener:touchend", "listener:pointerdown", "listener:pointermove", "listener:pointerup", "listener:pointercancel"]

def phase (ctx : String) : Phase :=
  if ctx == "cleanup" then .cleanup
  else if mountCtx.contains ctx then .mount
  else if ctx == "listener:resize" || ctx.startsWith "listener:media-" then .resize
  else if hoverCtx.contains ctx then .hover
  else if ctx.startsWith "jsx:" || (ctx.startsWith "listener:" && !frameListeners.contains ctx) then .event
  else .frame

def pointerTypes : List String :=
  ["pointerdown", "pointermove", "pointerup", "pointercancel", "wheel", "touchstart", "touchmove", "touchend",
   "mousedown", "mousemove"]

def localName (s : String) : String := (s.splitOn "#").getLastD s

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

def writes (a : Access) : List String :=
  match a.op with
  | .setVar | .setStyle => ["cssVar:" ++ a.name ++ "/" ++ a.owner]
  | .setClass | .setAttr => ["className:" ++ a.name ++ "/" ++ a.owner]
  | .setModuleClass => ["className:" ++ localName a.name ++ "/" ++ a.owner]
  | .scroll => if a.owner == "document" then ["scrollY"] else []
  | .setContent => if a.owner == "" || a.owner == "?" then [] else ["rect:" ++ a.owner]
  | _ => []

theorem writes_nil_of_read (a : Access) (h : a.op.isWrite = false) : writes a = [] := by
  cases a with
  | mk part file line op name owner ctx vs => cases op <;> simp_all [writes, Op.isWrite]

theorem reads_nil_of_write (a : Access) (h : a.op.isWrite = true) : reads a = [] := by
  cases a with
  | mk part file line op name owner ctx vs => cases op <;> simp_all [reads, Op.isWrite]

theorem reads_cleanup (a : Access) (h : phase a.ctx = .cleanup) : reads a = [] := by
  simp [reads, h]

def splitOwner (w : String) : String × String :=
  match (w.splitOn "/").reverse with
  | o :: rest@(_ :: _) => ("/".intercalate rest.reverse, o)
  | _ => (w, "")

def splitKind (w : String) : String × String :=
  match w.splitOn ":" with
  | k :: n :: rest => (k, ":".intercalate (n :: rest))
  | _ => (w, "")

def same (u v : String) : Bool :=
  u == v ||
    let (pu, ou) := splitOwner u
    let (pv, ov) := splitOwner v
    let (ku, nu) := splitKind pu
    let (kv, nv) := splitKind pv
    ou != "" && ov != "" && (ou == ov || ou == "*" || ou == "?" || ov == "*" || ov == "?") &&
      (pu == pv || (ku == kv && (nu == "?" || nv == "?")))

def joinKind (w : String × String) : String := if w.2 == "" then w.1 else w.1 ++ ":" ++ w.2

def Access.isOpen (a : Access) : Bool := a.name == "?" || a.owner == "?"

def flagged (fs : List Finding) (a : Access) : Bool :=
  fs.any fun f => f.part == a.part && f.file == a.file && f.line == a.line

structure Row where
  id : String
  inputs : List (String × String)
  outputs : List (String × String)
  onEvent : List (String × String)
  targets : List String
  order : List Nat
deriving Repr

def jstr (s : String) : String := "\"" ++ ((s.replace "\\" "\\\\").replace "\"" "\\\"") ++ "\""

def Access.json (a : Access) : String :=
  "{\"part\":" ++ jstr a.part ++ ",\"file\":" ++ jstr a.file ++ ",\"line\":" ++ toString a.line ++
    ",\"op\":" ++ jstr a.op.name ++ ",\"name\":" ++ jstr a.name ++ ",\"owner\":" ++ jstr a.owner ++
    ",\"ctx\":" ++ jstr a.ctx ++ ",\"variants\":[" ++ ",".intercalate (a.variants.map jstr) ++ "]}"

def Finding.json (f : Finding) : String :=
  "{\"part\":" ++ jstr f.part ++ ",\"file\":" ++ jstr f.file ++ ",\"line\":" ++ toString f.line ++
    ",\"kind\":" ++ jstr f.kind ++ ",\"detail\":" ++ jstr f.detail ++ "}"

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

/-- The nav-clip cell grade of the open/close frames. -/
inductive LookCell where
  | e
  | q
  | l
deriving DecidableEq, Repr

/-- What was seen for one flag: the rest-state gate, the open/close cell, the changed pixels mid-morph against the
later-load floor of the same lane, and whether the morph trajectory is red. -/
structure LookSeen where
  restGate : Bool
  cell : LookCell
  midChanged : Nat
  midFloor : Nat
  morphRed : Bool
deriving Repr

/-- Whether the mid-morph pixel count is above the lane's own later-load floor. -/
def pxOver (s : LookSeen) : Bool := decide (s.midFloor < s.midChanged)

/-- The look class `l` (user look review) when the pixels, the morph trajectory or the cell see a change; else `q`. -/
def isLookChange (s : LookSeen) : Bool := pxOver s || s.morphRed || s.cell == .l

theorem look_of_px {s : LookSeen} (h : s.midFloor < s.midChanged) : isLookChange s = true := by
  simp [isLookChange, pxOver, h]

theorem look_of_traj {s : LookSeen} (h : s.morphRed = true) : isLookChange s = true := by
  simp [isLookChange, h]

theorem look_of_cell {s : LookSeen} (h : s.cell = .l) : isLookChange s = true := by
  simp [isLookChange, h]

theorem q_only_if_clean {s : LookSeen} (h : isLookChange s = false) :
    s.midChanged ≤ s.midFloor ∧ s.morphRed = false ∧ s.cell ≠ .l := by
  simp [isLookChange, pxOver] at h
  exact ⟨h.1.1, h.1.2, h.2⟩

/-- **The rest-state gate cannot see it**: the class does not depend on the rest gate. -/
theorem rest_blind (s : LookSeen) (b : Bool) : isLookChange { s with restGate := b } = isLookChange s := rfl

/-- **An exact open/close cell cannot see it**: with pixels above the floor the class is `l` for every cell grade. -/
theorem cell_blind {s : LookSeen} (c : LookCell) (h : s.midFloor < s.midChanged) :
    isLookChange { s with cell := c } = true := look_of_px (s := { s with cell := c }) h

/-- nav:clip-box, Simulator run gpu-safari-sim-2026-10-23T00-46-14-744Z at m0.5; CI morph trajectory run 39887328839. -/
def clipBoxSeen : LookSeen :=
  { restGate := true, cell := .e, midChanged := 1020729, midFloor := 0, morphRed := true }
/-- nav:bar-fixed at m0.5; CI morph trajectory run 39887331854. -/
def barFixedSeen : LookSeen :=
  { restGate := true, cell := .e, midChanged := 1021369, midFloor := 0, morphRed := true }
/-- nav:logo-3d at m0.5; CI morph trajectory run 39887335005. -/
def logo3dSeen : LookSeen :=
  { restGate := true, cell := .e, midChanged := 1021646, midFloor := 0, morphRed := true }

theorem clipBox_look : isLookChange clipBoxSeen = true := look_of_px (by decide)
theorem barFixed_look : isLookChange barFixedSeen = true := look_of_px (by decide)
theorem logo3d_look : isLookChange logo3dSeen = true := look_of_px (by decide)

end Fw.Parts.Footprint
