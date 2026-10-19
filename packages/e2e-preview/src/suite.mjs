// The assertions of the preview e2e suite, one engine at a time. `runEngine` drives one Playwright browser through the rig
// (rig.mjs) over every host (loopback, plain HTTP host, LAN address when the machine has one) and every preview path
// (/r/, /o/, /compare) and returns a flat list of named checks. It decides nothing about the product: each check is an
// observation of the page (status codes, fonts, images, module evaluations) compared with a stated expectation.
import { PLAIN_HOST, PREVIEW_ID } from "./rig.mjs";

export const IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
export const VIEWPORT = { width: 390, height: 844 };
/** The one same-origin request that may fail: Cloudflare's analytics beacon posts here and the preview servers have no such route. */
export const ACCEPTED_FAILURES = ["/cdn-cgi/rum"];

export const PATHS = [
  { id: "r", path: `/preview/${PREVIEW_ID}/r/`, arm: "r", frames: [{ name: "r", path: `/preview/${PREVIEW_ID}/r/`, kind: "fixture" }] },
  { id: "o", path: `/preview/${PREVIEW_ID}/o/`, arm: "o", frames: [{ name: "o", path: `/preview/${PREVIEW_ID}/o/`, kind: "original" }] },
  { id: "compare", path: `/preview/${PREVIEW_ID}/compare`, arm: "o", frames: [
    { name: "o", path: `/preview/${PREVIEW_ID}/o/`, kind: "original" }, { name: "r", path: `/preview/${PREVIEW_ID}/r/`, kind: "fixture" }] },
];

/** Fonts the page must have loaded: [family substring ...] per kind of page. */
const FONTS = { original: ["Google Sans", "Playpen Sans"], fixture: ["Fixture Playpen"] };

/** The page may not reach the real internet (analytics, ads): those requests are aborted and listed. */
const blockExternal = (origin, log) => async (route) => {
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
      scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 40));
    }
    scrollTo(0, 0);
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

/** What the preview port answered for the first failed request paths (diagnosis of a cancelled load). */
function seenFor(rig, failed) {
  const paths = [...new Set(failed.slice(0, 3).map((f) => f.split(" ")[1]))];
  return paths.map((pth) => {
    const base = pth.replace(/^\/preview\/[^/]+\/[ro]/, "");
    return `${base}: ` + rig.seen.filter((r) => r.path.endsWith(base)).map((r) => `${r.path.startsWith("/preview/") ? "pfx" : "root"} ${r.status} dest=${r.dest || "-"}`).join(", ");
  }).join(" ## ");
}

/** The accepted WebKit-on-Linux signature of one original-arm load: exactly 3 unhandled rejections (two failed module imports
 *  and one CSS preload failure of an /_app/ asset) and, when Playwright reports the cancelled requests, exactly 13 of them.
 *  Measured on CI (runs in docs/team/tools/preview-e2e.md): Playwright WebKit on Linux reports those cancels in only some
 *  loads (13 or none, same page, same engine), so "none reported" is accepted only together with the exact rejection shape. */
export const CANCEL_SIGNATURE = { rejections: 3, cancelled: 13 };

/** Is this load's noise exactly the signature? `failed` are "METHOD /path text" lines of the failed same-origin requests;
 *  `seen` is what the preview port saw. Every reported cancel must be an /_app/ request (with or without the preview prefix)
 *  whose root URL was answered at this host's preview port: a script by the 302 below the prefix, a stylesheet in place. The
 *  CSS preload named by the rejection must be such an /_app/ asset too. */
export function cancelSignature(pageErrors, failed, seen, host) {
  const hostPart = new URL(host.origin).host;
  const root = (p) => p.replace(/^\/preview\/[^/]+\/[ro]/, "");
  const answered = (p) => seen.filter((r) => r.host === hostPart && r.path === root(p));
  const ok302 = (p) => (/\.m?js$/.test(p) ? answered(p).some((r) => r.status === 302) : answered(p).some((r) => r.status >= 200 && r.status < 400));
  const modules = pageErrors.filter((e) => /Importing a module script failed/.test(e));
  const css = pageErrors.filter((e) => /Unable to preload CSS for /.test(e));
  const cssPath = css.length === 1 ? ((/Unable to preload CSS for \S+?(\/_app\/\S+\.css)\s*$/.exec(css[0]) ?? [])[1] ?? null) : null;
  const rejectionsOk = pageErrors.length === CANCEL_SIGNATURE.rejections && modules.length === 2 && css.length === 1 && cssPath !== null && ok302(cssPath);
  const paths = failed.map((f) => (/^\S+ (\S+) Load request cancelled$/.exec(f) ?? [])[1]);
  const shapeOk = paths.every((p) => typeof p === "string" && /^(\/preview\/[^/]+\/[ro])?\/_app\//.test(p));
  const noRedirect = shapeOk ? paths.filter((p) => !ok302(p)) : [];
  const countOk = failed.length === 0 || failed.length === CANCEL_SIGNATURE.cancelled;
  return {
    ok: rejectionsOk && shapeOk && countOk && noRedirect.length === 0,
    rejections: pageErrors.length, cancelled: failed.length,
    detail: `${pageErrors.length} rejections (expect ${CANCEL_SIGNATURE.rejections}: 2 module imports + 1 /_app/ CSS preload${rejectionsOk ? "" : ", NOT matched"}), ${failed.length} cancels reported by Playwright (expect 0 or ${CANCEL_SIGNATURE.cancelled}${shapeOk && countOk ? "" : ", NOT matched"}), ${noRedirect.length} without an answered root request${noRedirect.length ? ` (${noRedirect.map((p) => `${p} ${answered(p).map((r) => r.status).join("/") || "unseen"}`).join(" , ")})` : ""}`,
  };
}

async function runTarget(browser, rig, engine, host, target, opts) {
  process.stderr.write(`# ${engine} ${host.name} ${target.id}\n`);
  const ctx = await browser.newContext({
    userAgent: IPHONE_UA, viewport: VIEWPORT, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
    ...(host.name === "plain-http" ? { proxy: { server: `http://127.0.0.1:${rig.ports.proxy}` } } : {}),
  });
  const log = { external: [], responses: [], requests: [], pageErrors: [], consoleErrors: [], failed: [], navs: [] };
  const checks = [];
  const check = (id, ok, detail = "") => checks.push({ id: `${engine}/${host.name}/${target.id}/${id}`, ok: Boolean(ok), detail: String(detail) });
  try {
    if (opts.route !== false) await ctx.route((u) => u.origin !== host.origin, blockExternal(host.origin, log));
    ctx.on("request", (r) => { log.requests.push(r); });
    ctx.on("response", (r) => { log.responses.push({ url: r.url(), status: r.status(), method: r.request().method(), type: r.request().resourceType(), redirected: r.request().redirectedFrom() !== null }); });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => log.pageErrors.push(String(e)));
    page.on("framenavigated", (f) => log.navs.push(`${f === page.mainFrame() ? "main" : "frame"} ${new URL(f.url()).pathname}`));
    page.on("requestfailed", (r) => log.failed.push(`${r.method()} ${new URL(r.url()).pathname} ${r.failure()?.errorText ?? ""}`));
    page.on("console", (m) => { if (m.type() === "error") log.consoleErrors.push(m.text()); });

    // access: the grant link is redeemed on this very host (cookie scoped to it), as the phone's browser would
    const link = await rig.grantUrl(host.origin, target.arm);
    const g = await page.goto(link, { waitUntil: "load" });
    check("grant-redeemed", g && g.status() === 200 && new URL(page.url()).pathname === `/preview/${PREVIEW_ID}/${target.arm}/`, `${g?.status()} ${page.url()}`);
    rig.seen.length = 0; log.responses.length = 0; log.requests.length = 0; log.pageErrors.length = 0; log.consoleErrors.length = 0; log.failed.length = 0; log.navs.length = 0;

    const doc = await page.goto(`${host.origin}${target.path}`, { waitUntil: "load" });
    check("document-200", doc && doc.status() === 200 && /text\/html/.test(doc.headers()["content-type"] ?? ""), `${doc?.status()} ${doc?.headers()["content-type"]}`);
    for (const f of target.frames) {
      const fr = target.id === "compare" ? await frameBy(page, f.path) : page.mainFrame();
      if (!fr) { check(`frame-${f.name}-present`, false, f.path); continue; }
      await fr.waitForLoadState("load").catch(() => undefined);
      await settle(fr);
    }
    await page.waitForTimeout(500);

    // every same-origin response is 2xx or 3xx, but the accepted analytics post
    const sameOrigin = log.responses.filter((r) => new URL(r.url).origin === host.origin);
    const bad = sameOrigin.filter((r) => r.status >= 400 && !ACCEPTED_FAILURES.some((a) => new URL(r.url).pathname === a));
    check("same-origin-2xx-3xx", sameOrigin.length > 0 && bad.length === 0, bad.length ? bad.slice(0, 5).map((r) => `${r.status} ${r.method} ${new URL(r.url).pathname}`).join("; ") : `${sameOrigin.length} responses`);
    // Playwright WebKit on Linux (libsoup) cancels preloads that the proxy redirected (root URL -> prefixed URL) while the same
    // file is imported by its prefixed URL; the page then logs unhandled rejections for those preloads of other routes. The
    // signature is asserted exactly, for the original arm on WebKit only: CANCEL_SIGNATURE rejections, each a module/CSS preload
    // failure, and CANCEL_SIGNATURE.cancelled same-origin /_app/ requests "Load request cancelled", each of which had a root-URL
    // 302 at the preview port (rig.seen). Anything else (another count, another message, a cancelled request without that
    // redirect, a page error with no cancelled request) fails page-errors. The attribution check below says where it comes from.
    const sameFailed = log.failed.filter((f) => !/Blocked by Web Inspector|beacon|cdn-cgi/.test(f));
    const sig = engine === "webkit" && target.frames.some((f) => f.kind === "original") ? cancelSignature(log.pageErrors, sameFailed, rig.seen, host) : null;
    const cancelNoise = sig !== null && sig.ok;
    check("page-errors", (cancelNoise || (log.pageErrors.length === 0 && sameFailed.length === 0)) && !log.consoleErrors.some((t) => /dynamically imported module|Failed to load module/i.test(t)),
      [...log.pageErrors, ...log.consoleErrors].slice(0, 3).join(" | ") + (sig ? ` || signature: ${sig.detail}` : "") + (log.failed.length ? ` || failed: ${log.failed.slice(0, 6).join("; ")} || navs: ${log.navs.join(", ")} || server saw: ${seenFor(rig, log.failed)}` : ""));
    if (cancelNoise) check("webkit-linux-preload-cancel-noise-observed", true, `${sig.detail} (accepted limit, see docs/team/tools/preview-e2e.md)`);

    // the phone case, read at the preview port: a plain-HTTP host that is not potentially trustworthy gets no Sec-Fetch-Dest
    const hostPart = new URL(host.origin).host;
    const scripts = rig.seen.filter((r) => r.host === hostPart && /\.m?js$/.test(r.path));
    const withDest = scripts.filter((r) => r.dest);
    check("sec-fetch-dest-matches-host", scripts.length > 0 && (host.trustworthy ? withDest.length === scripts.length : withDest.length === 0),
      `${withDest.length}/${scripts.length} script requests carried Sec-Fetch-Dest on a ${host.trustworthy ? "trustworthy" : "non-trustworthy"} host`);
    // the root-absolute module imports are moved below the preview by a redirect; none is served in place
    const rootScripts = scripts.filter((r) => !r.path.startsWith("/preview/"));
    check("root-module-requests-redirected", rootScripts.every((r) => r.status === 302), `${rootScripts.length} root script requests: ${[...new Set(rootScripts.map((r) => r.status))].join(",") || "none"}`);

    for (const f of target.frames) {
      const fr = target.id === "compare" ? await frameBy(page, f.path) : page.mainFrame();
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

async function frameBy(page, path) {
  for (let i = 0; i < 40; i++) {
    const f = page.frames().find((x) => x !== page.mainFrame() && new URL(x.url()).pathname === path);
    if (f) return f;
    await page.waitForTimeout(100);
  }
  return null;
}

/** LAN mode: the passphrase login (no keychain, a test value) gives the preview cookie on the LAN address; then the same pages. */
async function lanLogin(browser, rig, engine, host, passphrase) {
  const checks = [];
  const ctx = await browser.newContext({ userAgent: IPHONE_UA, viewport: VIEWPORT, isMobile: true, hasTouch: true });
  try {
    await ctx.route((u) => u.origin !== host.origin && u.origin !== host.consoleOrigin, blockExternal(host.origin, { external: [] }));
    const page = await ctx.newPage();
    const wrong = await page.request.post(`${host.consoleOrigin}/owner/login`, { headers: { origin: host.consoleOrigin }, data: { passphrase: "not-the-passphrase" } });
    checks.push({ id: `${engine}/lan/login-wrong-refused`, ok: wrong.status() === 401, detail: String(wrong.status()) });
    const good = await page.request.post(`${host.consoleOrigin}/owner/login`, { headers: { origin: host.consoleOrigin }, data: { passphrase } });
    checks.push({ id: `${engine}/lan/login-ok`, ok: good.status() === 200, detail: String(good.status()) });
    const noCookie = await (await browser.newContext()).request.get(`${host.origin}/preview/${PREVIEW_ID}/o/`, { headers: { accept: "text/html" } });
    checks.push({ id: `${engine}/lan/preview-refused-without-cookie`, ok: noCookie.status() === 401, detail: String(noCookie.status()) });
    const withCookie = await page.request.get(`${host.origin}/preview/${PREVIEW_ID}/o/`);
    checks.push({ id: `${engine}/lan/preview-open-with-session-cookie`, ok: withCookie.status() === 200, detail: String(withCookie.status()) });
    // the login cookie carries the whole page through the LAN address: the real phone path (no Sec-Fetch, non-loopback socket)
    const doc = await page.goto(`${host.origin}/preview/${PREVIEW_ID}/o/`, { waitUntil: "load" });
    await settle(page.mainFrame());
    const facts = await frameFacts(page.mainFrame());
    const rep = evalReport(facts.evals);
    checks.push({ id: `${engine}/lan/o/page`, ok: doc?.status() === 200 && rep.total >= 2 && rep.duplicates.length === 0 && facts.broken.length === 0 && facts.fonts.some((x) => x.includes("Google Sans")),
      detail: `${doc?.status()}, ${rep.total} modules once, ${facts.images} images ${facts.broken.length} broken, fonts ${facts.fonts.join("/")}` });
  } catch (e) {
    checks.push({ id: `${engine}/lan/run`, ok: false, detail: String(e?.message ?? e).split("\n")[0] });
  } finally { await ctx.close().catch(() => undefined); }
  return checks;
}

/** One control load of the original arm, to attribute the WebKit signature: how many unhandled rejections and cancelled
 *  /_app/ requests the page shows. `how` names the arm. The load is asserted only to complete; the numbers are read by
 *  `attribution`. */
async function controlLoad(browser, rig, engine, arm, url, prepare) {
  const ctx = await browser.newContext({ userAgent: IPHONE_UA, viewport: VIEWPORT, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const errors = []; const failed = [];
  try {
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("requestfailed", (r) => failed.push(`${r.method()} ${new URL(r.url()).pathname} ${r.failure()?.errorText ?? ""}`));
    const target = await prepare(page, ctx);
    await page.goto(target ?? url, { waitUntil: "load" });
    await settle(page.mainFrame());
    await page.waitForTimeout(500);
    const cancelled = failed.filter((f) => /Load request cancelled$/.test(f)).length;
    return { arm, ok: true, rejections: errors.length, cancelled, detail: `${errors.length} rejections, ${cancelled} cancelled, ${failed.length} failed: ${[...errors.map((e) => e.slice(0, 80)), ...failed].slice(0, 3).join(" | ")}` };
  } catch (e) {
    return { arm, ok: false, rejections: -1, cancelled: -1, detail: String(e?.message ?? e).split("\n")[0] };
  } finally { await ctx.close().catch(() => undefined); }
}

/** Controls of the original arm (3 loads each), none of them a pass/fail check on the page itself:
 *   raw        the raw preview server port: no proxy, no tap, no redirect;
 *   tap-only   the same server behind the evaluation tap: no proxy;
 *   proxy-only the console's preview proxy (grant, redirects, prefix) in front of the raw server: no tap.
 *  The arms of the suite itself are proxy + tap. */
async function controls(browser, rig, engine) {
  const out = [];
  const noop = async () => null;
  for (let i = 1; i <= 3; i++) {
    out.push(await controlLoad(browser, rig, engine, "raw", `http://127.0.0.1:${rig.ports.op}/`, noop));
    out.push(await controlLoad(browser, rig, engine, "tap-only", `http://127.0.0.1:${rig.ports.tapOp}/`, noop));
    rig.useTap(false);
    try {
      out.push(await controlLoad(browser, rig, engine, "proxy-only", null, async (page) => {
        const link = await rig.grantUrl(rig.hosts.loopback.origin, "o");
        await page.goto(link, { waitUntil: "load" });
        return `${rig.hosts.loopback.origin}/preview/${PREVIEW_ID}/o/`;
      }));
    } finally { rig.useTap(true); }
  }
  return out;
}

/** Which arm shows the signature: a control arm shows it when one of its loads has rejections > 0 and cancelled > 0. */
export function attribution(ctl, suiteSig) {
  const arms = ["raw", "tap-only", "proxy-only"];
  const shows = (a) => { const xs = ctl.filter((c) => c.arm === a); return xs.some((c) => c.rejections > 0 && c.cancelled > 0); };
  const clean = (a) => { const xs = ctl.filter((c) => c.arm === a); return xs.length > 0 && xs.every((c) => c.ok && c.rejections === 0 && c.cancelled === 0); };
  const shown = arms.filter(shows);
  let cause;
  if (!suiteSig) cause = "the suite's own arms (proxy + tap) show no signature on this engine";
  else if (shown.length === 0) cause = clean("raw") && clean("tap-only") && clean("proxy-only")
    ? "only the combination proxy + tap shows it (each control is clean)" : "controls inconclusive";
  else if (shown.includes("raw")) cause = "the engine (raw server shows it)";
  else if (shown.includes("tap-only")) cause = "the tap (tap-only shows it; the fix is to keep the original cache headers in the tap)";
  else cause = "the proxy path (proxy-only shows it, tap-only and raw do not)";
  return { shown, cause };
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
  }
  const ctl = await controls(browser, rig, engine);
  ctl.forEach((c, i) => out.push({ id: `${engine}/control/${c.arm}/o-load#${i + 1}`, ok: c.ok, detail: c.detail }));
  const suiteSig = out.some((c) => /webkit-linux-preload-cancel-noise-observed$/.test(c.id));
  const at = attribution(ctl, suiteSig);
  out.push({ id: `${engine}/control/attribution`, ok: true, detail: `arms showing the signature: ${at.shown.join(", ") || "none"}; attributed to ${at.cause}` });
  for (const c of out.filter((x) => x.id.includes("/control/"))) process.stderr.write(`  ctl  ${c.id}  (${c.detail})\n`);
  return out;
}

export { PLAIN_HOST };
