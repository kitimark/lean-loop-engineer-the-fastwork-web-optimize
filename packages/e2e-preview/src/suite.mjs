// The assertions of the preview e2e suite, one engine at a time. `runEngine` drives one Playwright browser through the rig
// (rig.mjs) over every host (loopback, plain HTTP host, LAN address when the machine has one) and every preview page (the task
// arm, the original arm, the side-by-side page). Each arm is its own origin (its own port), so a page's root-absolute module
// paths reach the same arm directly: no redirect, no rewrite. The suite requires 0 unhandled rejections and 0 cancelled
// same-origin requests in every load, in both engines. It decides nothing about the product: each check is an observation of the
// page (status codes, fonts, images, module evaluations, navigations) compared with a stated expectation.
import { PLAIN_HOST, PREVIEW_ID } from "./rig.mjs";

export const IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
export const VIEWPORT = { width: 390, height: 844 };
/** The one same-origin request that may fail: Cloudflare's analytics beacon posts here and the preview servers have no such route. */
export const ACCEPTED_FAILURES = ["/cdn-cgi/rum"];

/** The search of a review card's flag button (Lean `Fw.Console.ReviewPreview.searchOf`): `?fw=` and the flag key, colon included. */
export const REVIEW_SEARCH = "?fw=nav:earn-no-transition";

/** `arm`: the arm whose grant link opens the page; `frames`: the pages whose facts are read (`arm` = which arm origin they live on). */
export const PATHS = [
  { id: "r", arm: "r", frames: [{ name: "r", arm: "r", kind: "fixture" }] },
  { id: "o", arm: "o", frames: [{ name: "o", arm: "o", kind: "original" }] },
  { id: "compare", arm: "o", frames: [{ name: "o", arm: "o", kind: "original" }, { name: "r", arm: "r", kind: "fixture" }] },
  // the entry path as the Builds page links it (`/preview/<id>/r|o/<search>` on the preview port): a page-level hop to the arm origin
  { id: "entry-r", arm: "r", entry: "r", frames: [{ name: "r", arm: "r", kind: "fixture" }] },
  { id: "entry-o", arm: "o", entry: "o", frames: [{ name: "o", arm: "o", kind: "original" }] },
  // the Preview button of a look-change review card (review-preview-devices): the flag arm, `?fw=<flag key>`, through the same entry path
  { id: "entry-review-flag", arm: "r", entry: "r", search: REVIEW_SEARCH, frames: [{ name: "r", arm: "r", kind: "fixture" }] },
];

/** A search string like the ones Lean `console.builds` gives a row (`?only=<part>`); the arms ignore it, the hop must keep it. */
export const ENTRY_SEARCH = "?only=hero&flags=a";
/** The search an entry target opens. */
export const searchOf = (target) => target.search ?? ENTRY_SEARCH;

/** Where a target's document is: an arm's own origin, or the preview port's side-by-side page. */
export const documentUrl = (host, target) => (target.id === "compare" ? `${host.origin}/preview/${PREVIEW_ID}/compare`
  : target.entry ? `${host.origin}/preview/${PREVIEW_ID}/${target.entry}/${searchOf(target)}` : `${host.arm[target.arm]}/`);

/** Fonts the page must have loaded: [family substring ...] per kind of page. */
const FONTS = { original: ["Google Sans", "Playpen Sans"], fixture: ["Fixture Playpen"] };

/** The origins of a host that belong to the preview: its preview port and its two arms. */
export const ownOrigins = (host) => new Set([host.origin, host.arm.r, host.arm.o]);

/** The page may not reach the real internet (analytics, ads): those requests are aborted and listed. */
const blockExternal = (log) => async (route) => {
  log.external.push(route.request().url());
  await route.abort("blockedbyclient");
};

/** Everything the checks read from a loaded frame, in one evaluate. */
async function frameFacts(frame) {
  return await frame.evaluate(async () => {
    await document.fonts.ready;
    const fonts = [...document.fonts].filter((f) => f.status === "loaded").map((f) => f.family.replace(/["']/g, ""));
    const imgs = [...document.images];
    return {
      title: document.title,
      fonts: [...new Set(fonts)],
      images: imgs.length,
      broken: imgs.filter((i) => i.complete && i.naturalWidth === 0).map((i) => i.currentSrc || i.src),
      pending: imgs.filter((i) => !i.complete).length,
      evals: globalThis.__fwEvals ?? [],
      fixtureHydrations: globalThis.__fixtureHydrations ?? null,
      starts: globalThis.__fwStarts ?? null,
      hydratedAttr: document.documentElement.getAttribute("data-hydrated"),
      bodyText: (document.body?.innerText ?? "").length,
    };
  });
}

/** Scroll the page to the bottom in steps so lazy images load, then let the network go quiet. */
async function settle(frame) {
  await frame.evaluate(async () => {
    const step = Math.max(200, innerHeight / 2);
    for (let y = 0; y < document.documentElement.scrollHeight && y < 40000; y += step) {
      scrollTo({ top: y, left: 0, behavior: 'instant' });
      await new Promise((r) => setTimeout(r, 40));
    }
    scrollTo({ top: 0, left: 0, behavior: 'instant' });
  });
  await frame.page().waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => undefined);
}

const lastSeg = (u) => new URL(u).pathname.split("/").pop();

/** Module URLs that were evaluated, grouped by file name: the same file under two URLs is two module instances. */
export function evalReport(evals) {
  const byFile = new Map();
  for (const u of evals) { const k = lastSeg(u); byFile.set(k, [...(byFile.get(k) ?? []), new URL(u).pathname]); }
  const duplicates = [...byFile].filter(([, urls]) => urls.length > 1).map(([f, urls]) => `${f} x${urls.length}: ${urls.join(" , ")}`);
  return { total: evals.length, files: byFile.size, duplicates };
}

/** The failed same-origin requests of a load as "METHOD /path text" lines, but the beacon and the inspector's own blocks. */
const noise = /Blocked by Web Inspector|beacon|cdn-cgi/;

/** Wire one page's observers into `log`. `own` = the host's preview origins. */
function observe(page, log, own) {
  page.on("pageerror", (e) => log.pageErrors.push(String(e)));
  page.on("framenavigated", (f) => log.navs.push(`${f === page.mainFrame() ? "main" : "frame"} ${new URL(f.url()).pathname}`));
  page.on("requestfailed", (r) => {
    const o = new URL(r.url()).origin;
    log.failed.push({ own: own.has(o), line: `${r.method()} ${new URL(r.url()).pathname} ${r.failure()?.errorText ?? ""}` });
  });
  page.on("console", (m) => { if (m.type() === "error") log.consoleErrors.push(m.text()); });
  page.context().on("request", (r) => { log.requests.push(r); });
  page.context().on("response", (r) => { log.responses.push({ url: r.url(), status: r.status(), method: r.request().method(), type: r.request().resourceType(), redirected: r.request().redirectedFrom() !== null }); });
}
const newLog = () => ({ external: [], responses: [], requests: [], pageErrors: [], consoleErrors: [], failed: [], navs: [] });
const resetLog = (log) => { for (const k of Object.keys(log)) log[k].length = 0; };

/** 0 unhandled rejections, 0 cancelled (or otherwise failed) same-origin requests, no module-load error on the console. */
function noiseChecks(check, log, own, { requireResponses = true, documentHops = false } = {}) {
  const sameFailed = log.failed.filter((f) => f.own && !noise.test(f.line)).map((f) => f.line);
  const cancelled = sameFailed.filter((l) => /cancel/i.test(l));
  check("rejections-0", log.pageErrors.length === 0, log.pageErrors.slice(0, 3).join(" | ") || "none");
  check("cancelled-same-origin-0", cancelled.length === 0 && sameFailed.length === 0,
    sameFailed.length ? `${cancelled.length} cancelled of ${sameFailed.length} failed: ${sameFailed.slice(0, 6).join("; ")} || navs: ${log.navs.join(", ")}` : "none");
  check("console-no-module-load-error", !log.consoleErrors.some((t) => /dynamically imported module|Failed to load module/i.test(t)), log.consoleErrors.slice(0, 2).join(" | ") || "none");
  const sameOrigin = log.responses.filter((r) => own.has(new URL(r.url).origin));
  // `documentHops`: the page-level hops of the entry path (grant link, then `/preview/<id>/r|o/` to the arm origin) are the design
  // (a redirected navigation, never a redirected module or asset); every other request must be answered where it was sent
  const checked = documentHops ? sameOrigin.filter((r) => r.type !== "document") : sameOrigin;
  const hops = checked.filter((r) => r.status >= 300 && r.status < 400 && r.status !== 304);
  check("no-redirect-on-any-request", hops.length === 0 && checked.every((r) => !r.redirected), hops.length ? hops.slice(0, 4).map((r) => `${r.status} ${new URL(r.url).pathname}`).join("; ") : `${checked.length} responses`);
  const bad = sameOrigin.filter((r) => r.status >= 400 && !ACCEPTED_FAILURES.some((a) => new URL(r.url).pathname === a));
  check("same-origin-2xx", (!requireResponses || sameOrigin.length > 0) && bad.length === 0, bad.length ? bad.slice(0, 5).map((r) => `${r.status} ${r.method} ${new URL(r.url).pathname}`).join("; ") : `${sameOrigin.length} responses`);
}

async function runTarget(browser, rig, engine, host, target, opts) {
  process.stderr.write(`# ${engine} ${host.name} ${target.id}\n`);
  const ctx = await browser.newContext({
    userAgent: IPHONE_UA, viewport: VIEWPORT, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
    ...(host.name === "plain-http" ? { proxy: { server: `http://127.0.0.1:${rig.ports.proxy}` } } : {}),
  });
  const own = ownOrigins(host);
  const log = newLog();
  const checks = [];
  const check = (id, ok, detail = "") => checks.push({ id: `${engine}/${host.name}/${target.id}/${id}`, ok: Boolean(ok), detail: String(detail) });
  try {
    if (opts.route !== false) await ctx.route((u) => !own.has(u.origin), blockExternal(log));
    const page = await ctx.newPage();
    observe(page, log, own);

    // access: the grant link is redeemed on the preview port of this very host (cookie scoped to the host, not to a port), as the
    // phone's browser would; its page-level hop lands on the arm's own origin
    rig.seen.length = 0;
    const link = await rig.grantUrl(host.origin, target.arm);
    const g = await page.goto(link, { waitUntil: "load" });
    check("grant-redeemed", g && g.status() === 200 && page.url() === `${host.arm[target.arm]}/`, `${g?.status()} ${page.url()}`);
    // the landing page hydrates after its load event; leaving it mid-import would cancel that import (the browser's doing, not the server's)
    await page.waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => undefined);
    await page.waitForTimeout(300);
    // the real entry path, first half: the grant link and its landing page (the hop to the arm origin included) show no
    // rejection, no cancelled request and no failed one
    noiseChecks((id, ok, d) => check(`landing/${id}`, ok, d), log, own, { documentHops: true });
    resetLog(log); // rig.seen keeps the grant load: the arm requests of both loads are read below

    const doc = await page.goto(documentUrl(host, target), { waitUntil: "load" });
    if (target.entry) check("entry-landed-on-arm-origin-with-search", page.url() === `${host.arm[target.arm]}/${searchOf(target)}`, page.url());
    check("document-200", doc && doc.status() === 200 && /text\/html/.test(doc.headers()["content-type"] ?? ""), `${doc?.status()} ${doc?.headers()["content-type"]}`);
    for (const f of target.frames) {
      const fr = target.id === "compare" ? await frameOn(page, host.arm[f.arm]) : page.mainFrame();
      if (!fr) { check(`frame-${f.name}-present`, false, host.arm[f.arm]); continue; }
      await fr.waitForLoadState("load").catch(() => undefined);
      await settle(fr);
    }
    await page.waitForTimeout(500);

    noiseChecks(check, log, own, { documentHops: Boolean(target.entry) });

    // the phone case, read at the arm ports: a plain-HTTP host that is not potentially trustworthy gets no Sec-Fetch-Dest
    const armHosts = new Set(target.frames.map((f) => new URL(host.arm[f.arm]).host));
    const scripts = rig.seen.filter((r) => armHosts.has(r.host) && /\.m?js$/.test(r.path));
    const withDest = scripts.filter((r) => r.dest);
    check("sec-fetch-dest-matches-host", scripts.length > 0 && (host.trustworthy ? withDest.length === scripts.length : withDest.length === 0),
      `${withDest.length}/${scripts.length} script requests carried Sec-Fetch-Dest on a ${host.trustworthy ? "trustworthy" : "non-trustworthy"} host`);
    // every module and asset request of a page is answered by the arm itself (200/304), at its root-absolute path
    const armSeen = rig.seen.filter((r) => armHosts.has(r.host));
    check("arm-requests-answered-in-place", armSeen.length > 0 && armSeen.every((r) => r.status < 300 || r.status === 304 || ACCEPTED_FAILURES.includes(r.path)),
      `${armSeen.length} arm requests: ${[...new Set(armSeen.map((r) => r.status))].join(",") || "none"}`);

    for (const f of target.frames) {
      const fr = target.id === "compare" ? await frameOn(page, host.arm[f.arm]) : page.mainFrame();
      if (!fr) continue;
      const facts = await frameFacts(fr);
      const tag = target.id === "compare" ? `${f.name}-frame/` : "";
      check(`${tag}fonts-loaded`, FONTS[f.kind].every((n) => facts.fonts.some((x) => x.includes(n))), `loaded: ${facts.fonts.join(", ") || "none"}`);
      check(`${tag}images-0-broken`, facts.images > 0 && facts.broken.length === 0, `${facts.images} images, ${facts.broken.length} broken ${facts.broken.slice(0, 2).join(" ")}`);
      const rep = evalReport(facts.evals);
      check(`${tag}entry-modules-evaluated-once`, rep.total > 0 && rep.duplicates.length === 0, `${rep.total} evaluations of ${rep.files} files${rep.duplicates.length ? `; twice: ${rep.duplicates.join(" ; ")}` : ""}`);
      if (f.kind === "fixture") check(`${tag}hydrated-once`, facts.fixtureHydrations === 1 && facts.hydratedAttr === "1", `start() ran ${facts.fixtureHydrations} times`);
      else check(`${tag}hydrated-once`, rep.total >= 2 && facts.starts === 1, `start() ran ${facts.starts} times (tap counter), ${rep.total} modules evaluated`);
    }
    if (opts.keep) opts.keep({ engine, host: host.name, target: target.id, responses: log.responses });
  } catch (e) {
    check("run", false, String(e?.message ?? e).split("\n").slice(0, 4).join(" / "));
  } finally {
    await ctx.close().catch(() => undefined);
  }
  return checks;
}

/** The frame of the side-by-side page that lives on `origin` (the arm's own origin), once it has navigated there. */
async function frameOn(page, origin) {
  for (let i = 0; i < 40; i++) {
    const f = page.frames().find((x) => x !== page.mainFrame() && x.url().startsWith(`${origin}/`));
    if (f) return f;
    await page.waitForTimeout(100);
  }
  return null;
}

/** Client-side navigation inside an arm (no full reload): the page is marked, an internal link is clicked, the mark must survive,
 *  the URL must change (or stay) on the arm's own origin, the target route's node module must have been evaluated (once) and the
 *  load must stay free of rejections and cancelled requests.
 *   fixture arm   `a#to-about` imports `nodes/about.fix1.js` by a root-absolute dynamic import (a route the page had not loaded);
 *   original arm  the snapshot has one page route, so its internal link `a[href="/"]` goes to that route's node module, which
 *                 must stay evaluated exactly once. */
async function clientNavigation(browser, rig, engine, host, arm) {
  const checks = [];
  const check = (id, ok, detail = "") => checks.push({ id: `${engine}/${host.name}/client-nav-${arm}/${id}`, ok: Boolean(ok), detail: String(detail) });
  const own = ownOrigins(host);
  const ctx = await browser.newContext({
    userAgent: IPHONE_UA, viewport: VIEWPORT, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
    ...(host.name === "plain-http" ? { proxy: { server: `http://127.0.0.1:${rig.ports.proxy}` } } : {}),
  });
  const log = newLog();
  try {
    await ctx.route((u) => !own.has(u.origin), blockExternal(log));
    const page = await ctx.newPage();
    observe(page, log, own);
    await page.goto(await rig.grantUrl(host.origin, arm), { waitUntil: "load" });
    await page.waitForLoadState("load");
    await settle(page.mainFrame());
    resetLog(log);
    const before = await frameFacts(page.mainFrame());
    await page.evaluate(() => { globalThis.__fwNavMarker = Math.random(); });
    const marker = await page.evaluate(() => globalThis.__fwNavMarker);
    const sel = arm === "r" ? "a#to-about" : 'a[href="/"]';
    await page.locator(sel).first().click();
    if (arm === "r") await page.waitForSelector("html[data-route=about]", { timeout: 10_000 });
    else await page.waitForTimeout(1500);
    await page.waitForLoadState("networkidle", { timeout: 10_000 }).catch(() => undefined);
    const after = await frameFacts(page.mainFrame());
    const still = await page.evaluate(() => globalThis.__fwNavMarker);
    check("no-full-reload", still === marker && !log.navs.some((n) => n.startsWith("main ") && !n.endsWith(arm === "r" ? "/about" : "/")), `marker kept ${still === marker}; navs: ${log.navs.join(", ") || "none"}`);
    const u = new URL(page.url());
    check("stays-on-arm-origin", u.origin === host.arm[arm], page.url());
    const rep = evalReport(after.evals);
    if (arm === "r") {
      const about = after.evals.filter((e) => new URL(e).pathname.endsWith("/nodes/about.fix1.js"));
      check("target-node-module-evaluated-once", about.length === 1 && u.pathname === "/about" && rep.duplicates.length === 0, `${about.length} evaluations of the about node; path ${u.pathname}`);
      check("start-not-repeated", after.fixtureHydrations === 1, `start() ran ${after.fixtureHydrations} times`);
    } else {
      const page2 = after.evals.filter((e) => /\/nodes\/2\.[^/]+\.js$/.test(new URL(e).pathname));
      check("target-node-module-evaluated-once", page2.length === 1 && rep.duplicates.length === 0 && after.evals.length >= before.evals.length, `${page2.length} evaluations of the page node; ${before.evals.length} -> ${after.evals.length} evaluations in all`);
      check("start-not-repeated", after.starts === 1, `start() ran ${after.starts} times (tap counter)`);
    }
    // the click must have produced a same-document navigation the browser reported; an empty list would mean the click did nothing
    check("same-document-navigation-observed", log.navs.some((n) => n.startsWith("main ")), `navs: ${log.navs.join(", ") || "none"}`);
    noiseChecks(check, log, own, { requireResponses: arm === "r" }); // the original's home link needs no request at all
  } catch (e) {
    check("run", false, String(e?.message ?? e).split("\n").slice(0, 4).join(" / "));
  } finally { await ctx.close().catch(() => undefined); }
  return checks;
}

/** LAN mode: the passphrase login (no keychain, a test value) gives the preview cookie on the LAN address; then the same pages. */
async function lanLogin(browser, rig, engine, host, passphrase) {
  const checks = [];
  const ctx = await browser.newContext({ userAgent: IPHONE_UA, viewport: VIEWPORT, isMobile: true, hasTouch: true });
  try {
    await ctx.route((u) => !ownOrigins(host).has(u.origin) && u.origin !== host.consoleOrigin, blockExternal({ external: [] }));
    const page = await ctx.newPage();
    const log = newLog();
    observe(page, log, ownOrigins(host));
    const wrong = await page.request.post(`${host.consoleOrigin}/owner/login`, { headers: { origin: host.consoleOrigin }, data: { passphrase: "not-the-passphrase" } });
    checks.push({ id: `${engine}/lan/login-wrong-refused`, ok: wrong.status() === 401, detail: String(wrong.status()) });
    const good = await page.request.post(`${host.consoleOrigin}/owner/login`, { headers: { origin: host.consoleOrigin }, data: { passphrase } });
    checks.push({ id: `${engine}/lan/login-ok`, ok: good.status() === 200, detail: String(good.status()) });
    const fresh = await browser.newContext();
    const noCookie = await fresh.request.get(`${host.origin}/preview/${PREVIEW_ID}/o/`, { headers: { accept: "text/html" }, maxRedirects: 0 });
    checks.push({ id: `${engine}/lan/preview-refused-without-cookie`, ok: noCookie.status() === 401, detail: String(noCookie.status()) });
    const noCookieArm = await fresh.request.get(`${host.arm.o}/`, { headers: { accept: "text/html" }, maxRedirects: 0 });
    checks.push({ id: `${engine}/lan/arm-refused-without-cookie`, ok: noCookieArm.status() === 401, detail: String(noCookieArm.status()) });
    await fresh.close();
    const withCookie = await page.request.get(`${host.arm.o}/`);
    checks.push({ id: `${engine}/lan/arm-open-with-session-cookie`, ok: withCookie.status() === 200, detail: String(withCookie.status()) });
    // the login cookie carries the whole page through the LAN address: the real phone path (no Sec-Fetch, non-loopback socket)
    resetLog(log); // the checks below read this one load
    const doc = await page.goto(`${host.arm.o}/`, { waitUntil: "load" });
    await settle(page.mainFrame());
    await page.waitForTimeout(500);
    const facts = await frameFacts(page.mainFrame());
    const rep = evalReport(facts.evals);
    checks.push({ id: `${engine}/lan/o/page`, ok: doc?.status() === 200 && rep.total >= 2 && rep.duplicates.length === 0 && facts.broken.length === 0 && facts.fonts.some((x) => x.includes("Google Sans")),
      detail: `${doc?.status()}, ${rep.total} modules once, ${facts.images} images ${facts.broken.length} broken, fonts ${facts.fonts.join("/")}` });
    // the phone's path (non-loopback socket, no Sec-Fetch): 0 rejections, 0 cancelled or failed same-origin requests
    noiseChecks((id, ok, d) => checks.push({ id: `${engine}/lan/o/${id}`, ok: Boolean(ok), detail: String(d) }), log, ownOrigins(host));
  } catch (e) {
    checks.push({ id: `${engine}/lan/run`, ok: false, detail: String(e?.message ?? e).split("\n")[0] });
  } finally { await ctx.close().catch(() => undefined); }
  return checks;
}

/** One control load of the original arm: how many unhandled rejections and cancelled requests the page shows. */
async function controlLoad(browser, rig, engine, arm, url, prepare, opts = {}) {
  const ctx = await browser.newContext({ userAgent: IPHONE_UA, viewport: VIEWPORT, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const errors = []; const failed = [];
  try {
    // like runTarget: the page may not reach the real internet; every control URL is on loopback
    if (opts.route !== false) await ctx.route((u) => u.hostname !== "127.0.0.1", blockExternal({ external: [] }));
    const page = await ctx.newPage();
    const target = await prepare(page, ctx);
    // listen only from here: leaving the grant landing page mid-load would cancel its images and fonts (the browser's doing)
    page.on("pageerror", (e) => { if (!noise.test(String(e))) errors.push(String(e)); }); // the analytics beacon is no module error
    page.on("requestfailed", (r) => failed.push(`${r.method()} ${new URL(r.url()).pathname} ${r.failure()?.errorText ?? ""}`));
    await page.goto(target ?? url, { waitUntil: "load" });
    await settle(page.mainFrame());
    await page.waitForTimeout(500);
    const own = failed.filter((f) => !noise.test(f));
    const cancelled = own.filter((f) => /cancel/i.test(f)).length;
    return { arm, ok: true, rejections: errors.length, cancelled, detail: `${errors.length} rejections, ${cancelled} cancelled, ${failed.length} failed: ${[...errors.map((e) => e.slice(0, 80)), ...failed].slice(0, 3).join(" | ")}` };
  } catch (e) {
    return { arm, ok: false, rejections: -1, cancelled: -1, detail: String(e?.message ?? e).split("\n")[0] };
  } finally { await ctx.close().catch(() => undefined); }
}

/** Controls of the original arm (3 loads each), each required to show 0 rejections and 0 cancelled requests:
 *   raw        the preview server process on its own port: no arm app, no tap;
 *   tap-only   the same server behind the evaluation tap: no arm app;
 *   arm-only   the arm origin (grant, gate, routing through Lean) in front of the server, the tap a plain pass-through.
 *  The arms of the suite itself are arm origin + tap. If a suite arm ever fails, these say which layer carries it. */
async function controls(browser, rig, engine, opts = {}) {
  const out = [];
  const noop = async () => null;
  for (let i = 1; i <= 3; i++) {
    out.push(await controlLoad(browser, rig, engine, "raw", `http://127.0.0.1:${rig.ports.rawOp}/`, noop, opts));
    out.push(await controlLoad(browser, rig, engine, "tap-only", `http://127.0.0.1:${rig.ports.bop}/`, noop, opts));
    rig.useTap(false);
    try {
      out.push(await controlLoad(browser, rig, engine, "arm-only", null, async (page) => {
        await page.goto(await rig.grantUrl(rig.hosts.loopback.origin, "o"), { waitUntil: "load" });
        await page.waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => undefined);
        // every image the landing page started has finished (loaded or failed): none is left in flight to be cancelled by the next load
        await page.evaluate(() => Promise.all([...document.images].filter((i) => !i.complete).map((i) => new Promise((r) => { i.onload = i.onerror = r; setTimeout(r, 5000); })))).catch(() => undefined);
        await page.waitForTimeout(300); // as runTarget: the landing page is the same URL as the control load, leaving it mid-image cancels that image
        return `${rig.hosts.loopback.arm.o}/`;
      }, opts));
    } finally { rig.useTap(true); }
  }
  return out;
}

/** Strict attribution: a control arm that shows any rejection or cancelled request is named; the check fails when any does. */
export function attribution(ctl) {
  const arms = ["raw", "tap-only", "arm-only"];
  const shows = (a) => ctl.filter((c) => c.arm === a).some((c) => !c.ok || c.rejections > 0 || c.cancelled > 0);
  const shown = arms.filter(shows);
  return { shown, ok: shown.length === 0 && arms.every((a) => ctl.some((c) => c.arm === a)) };
}

export async function runEngine(browser, rig, engine, { passphrase, keep, route } = {}) {
  const out = [];
  for (const host of Object.values(rig.hosts)) {
    if (host.name === "lan") { out.push(...(await lanLogin(browser, rig, engine, host, passphrase))); continue; }
    for (const target of PATHS) {
      const t0 = Date.now();
      const cs = await runTarget(browser, rig, engine, host, target, { keep, route });
      for (const c of cs) process.stderr.write(`  ${c.ok ? "ok  " : "FAIL"} ${c.id}  (${c.detail})\n`);
      process.stderr.write(`  # ${Date.now() - t0} ms\n`);
      out.push(...cs);
    }
    for (const arm of ["r", "o"]) {
      const cs = await clientNavigation(browser, rig, engine, host, arm);
      for (const c of cs) process.stderr.write(`  ${c.ok ? "ok  " : "FAIL"} ${c.id}  (${c.detail})\n`);
      out.push(...cs);
    }
  }
  const ctl = await controls(browser, rig, engine, { route });
  ctl.forEach((c, i) => out.push({ id: `${engine}/control/${c.arm}/o-load#${i + 1}`, ok: c.ok && c.rejections === 0 && c.cancelled === 0, detail: c.detail }));
  const at = attribution(ctl);
  out.push({ id: `${engine}/control/attribution`, ok: at.ok, detail: `arms showing a rejection or a cancelled request: ${at.shown.join(", ") || "none"}` });
  for (const c of out.filter((x) => x.id.includes("/control/"))) process.stderr.write(`  ctl  ${c.id}  (${c.detail})\n`);
  return out;
}

export { PLAIN_HOST };
