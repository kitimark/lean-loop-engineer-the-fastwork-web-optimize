import Lean.Data.Json

/-!
# `head.gen.json`: the document head, the html attributes and the locale links

`genJson` is the whole document the site build reads: the `<html>` attributes, the head entries in document order
(title, description, `og:*`, `twitter:*`, canonical, hreflang alternates, icon and manifest links), the locale links
of the nav and the `aria-label` of the hero countdown. Declared differences from the original: its content-security
policy, `analytics.js`, the tag manager, the Cloudflare beacon and the preload hints stay out.

`lake env lean --run HeadgenMain.lean [--check <file>]` (from `lean/`) prints the generated JSON, or with `--check`
fails when the file differs byte for byte.
-/

namespace Fw.Site.Head

open Lean

/-- One head element: tag, attributes in order, text content (`title` only). -/
structure Entry where
  tag : String
  attrs : List (String × String)
  text : String := ""
  deriving Repr, DecidableEq

/-- A locale page of the site. -/
structure Alt where
  code : String
  url : String
  label : String
  deriving Repr, DecidableEq

def origin : String := "https://fastwork.com"

/-- The three locale pages. -/
def locales : List Alt :=
  [⟨"en", origin ++ "/", "English"⟩, ⟨"th", origin ++ "/th/", "ไทย"⟩, ⟨"id", origin ++ "/id/", "Indonesia"⟩]

/-- The page `x-default` points at. -/
def defaultAlt : Alt := ⟨"x-default", origin ++ "/", ""⟩

/-- Every hreflang alternate, the default included. -/
def alternates : List Alt := locales ++ [defaultAlt]

def canonicalUrl : String := origin

def titleText : String := "Fastwork · Show the world what you can do"
def descText : String := "Build a portfolio, get discovered, manage your work, and get paid with Fastwork."
def cardImage : String := origin ++ "/og-cover.png"

def mt (k v c : String) : Entry := ⟨"meta", [(k, v), ("content", c)], ""⟩
def link (attrs : List (String × String)) : Entry := ⟨"link", attrs, ""⟩

/-- The hreflang link of one alternate. -/
def hreflangEntry (a : Alt) : Entry := link [("rel", "alternate"), ("hreflang", a.code), ("href", a.url)]

def hreflangEntries : List Entry := alternates.map hreflangEntry

def canonicalEntry : Entry := link [("rel", "canonical"), ("href", canonicalUrl)]

/-- The head of the page in locale `a`: the same for every locale page. -/
def headFor (_ : Alt) : List Entry :=
  [⟨"meta", [("charset", "utf-8")], ""⟩,
   mt "name" "viewport" "width=device-width, initial-scale=1",
   link [("rel", "icon"), ("type", "image/png"), ("sizes", "192x192"), ("href", "/icon-192.png")],
   link [("rel", "icon"), ("href", "/favicon.ico"), ("sizes", "48x48")],
   link [("rel", "icon"), ("href", "/favicon.svg"), ("type", "image/svg+xml")],
   link [("rel", "apple-touch-icon"), ("href", "/apple-touch-icon.png")],
   link [("rel", "manifest"), ("href", "/site.webmanifest")],
   mt "name" "description" descText,
   ⟨"title", [], titleText⟩,
   mt "property" "og:type" "website",
   mt "property" "og:site_name" "Fastwork",
   mt "property" "og:url" (origin ++ "/"),
   mt "property" "og:title" titleText,
   mt "property" "og:description" descText,
   mt "property" "og:image" cardImage,
   mt "property" "og:image:secure_url" cardImage,
   mt "property" "og:image:type" "image/png",
   mt "property" "og:image:width" "1200",
   mt "property" "og:image:height" "630",
   mt "property" "og:image:alt" titleText,
   mt "property" "og:locale" "en_US",
   mt "property" "og:locale:alternate" "th_TH",
   mt "property" "og:locale:alternate" "id_ID",
   mt "name" "twitter:card" "summary_large_image",
   mt "name" "twitter:site" "@fastworkco",
   mt "name" "twitter:title" titleText,
   mt "name" "twitter:description" descText,
   mt "name" "twitter:image" cardImage,
   mt "name" "twitter:image:alt" titleText,
   canonicalEntry] ++ hreflangEntries

/-- Every alternate's hreflang link is in the head of every locale page (the pages reference each other, each its own).

$$ \forall a, b \in \mathrm{alternates}:\ \mathrm{hreflang}(a) \in \mathrm{head}(b) $$ -/
theorem hreflang_reciprocal : ∀ a ∈ alternates, ∀ b ∈ alternates, hreflangEntry a ∈ headFor b := by
  intro a ha b _
  unfold headFor
  exact List.mem_append_right _ (List.mem_map_of_mem ha)

/-- Each locale page links to itself.

$$ \forall a \in \mathrm{locales}:\ \mathrm{hreflang}(a) \in \mathrm{head}(a) $$ -/
theorem hreflang_self : ∀ a ∈ locales, hreflangEntry a ∈ headFor a := by
  intro a ha
  exact hreflang_reciprocal a (List.mem_append_left _ ha) a (List.mem_append_left _ ha)

/-- The canonical link is in the head.

$$ \mathrm{canonical} \in \mathrm{head}(a) $$ -/
theorem canonical_in_head (a : Alt) : canonicalEntry ∈ headFor a := by
  unfold headFor
  simp

/-- The canonical URL, up to the trailing slash, is the URL of an alternate.

$$ \exists a \in \mathrm{alternates}:\ \mathrm{canonical} \mathbin{+\!\!+} \texttt{"/"} = \mathrm{url}(a) $$ -/
theorem canonical_is_alternate : ∃ a ∈ alternates, canonicalUrl ++ "/" = a.url :=
  ⟨defaultAlt, by simp [alternates], rfl⟩

/-- No two alternates share a code.

$$ \mathrm{codes}(\mathrm{alternates})\ \text{has no duplicates} $$ -/
theorem codes_nodup : (alternates.map Alt.code).Nodup := by decide

/-- The head has exactly one title.

$$ \#\{e \in \mathrm{head} \mid \mathrm{tag}(e) = \texttt{title}\} = 1 $$ -/
theorem one_title (a : Alt) : ((headFor a).filter (·.tag == "title")).length = 1 := by
  simp [headFor, hreflangEntries, hreflangEntry, alternates, locales, defaultAlt, mt, link, canonicalEntry,
    List.filter]

def attrsJson (l : List (String × String)) : Json :=
  .arr (l.toArray.map fun (k, v) => .arr #[.str k, .str v])

def entryJson (e : Entry) : Json :=
  Json.mkObj [("tag", .str e.tag), ("attrs", attrsJson e.attrs), ("text", .str e.text)]

/-- The hero countdown's accessible name. -/
def countdownLabel : String := "Time until launch"

/-- The site-relative path of a locale page, for the nav links.

$$ \mathrm{path}(u) = u \text{ without } \texttt{origin} $$ -/
def pathOf (a : Alt) : String := (a.url.drop origin.length).toString

#guard locales.map pathOf == ["/", "/th/", "/id/"]

def genJson : Json :=
  Json.mkObj [
    ("html", Json.mkObj [("lang", "en"), ("dir", "ltr"), ("data-theme", "light")]),
    ("entries", .arr ((headFor defaultAlt).toArray.map entryJson)),
    ("locales", .arr (locales.toArray.map fun a =>
      Json.mkObj [("code", .str a.code), ("href", .str (pathOf a)), ("label", .str a.label)])),
    ("countdownAriaLabel", .str countdownLabel)]

def genText : String := genJson.pretty 120 ++ "\n"

/-- `[--check <file>]`: print the generated JSON, or fail (exit 1) when the file's bytes differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == genText.toUTF8.data then
      IO.eprintln s!"headgen: {path} is up to date"
      return 0
    IO.eprintln s!"headgen: {path} differs; regenerate with `lake env lean --run HeadgenMain.lean > {path}`"
    return 1
  | _ => IO.print genText; return 0

end Fw.Site.Head
