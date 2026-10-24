import createEmotionServer from '@emotion/server/create-instance';
import { renderToString } from 'react-dom/server';
import { canonSearch, keyOf } from '../../../packages/contracts/src/flag-key.mjs';
import { App } from './App';
import { Census } from './Census';
import { createServerCache } from './emotion';
import { parts, presets, resolveSearch } from './registry';
import { Root } from './Root';

export interface PrerenderedPage {
  /** the `?fw=...` / `?preset=...` search string this page answers ('' = default). */
  search: string;
  configHash: string;
  homeHtml: string;
}

/** Every config a measured run can request without hand-listing: the default, each preset, each single-part variant swap. */
export function enumerateSearches(kinds: ('presets' | 'single')[]): string[] {
  const out = [''];
  if (kinds.includes('presets')) for (const n of Object.keys(presets)) out.push(`?preset=${n}`);
  if (kinds.includes('single'))
    for (const p of parts)
      for (const v of Object.keys(p.variants)) {
        const key = `${p.id}:${v}`;
        out.push(`?fw=${keyOf([key, ...(p.requires[key] ?? [])])}`); // a variant is requested with what it requires, under the canonical key
      }
  return out;
}

export interface PrerenderResult {
  configHash: string;
  /** HTML of the home page for the default (all `faithful`) config. */
  homeHtml: string;
  /** one page per distinct config hash (first search wins), default first. */
  pages: PrerenderedPage[];
  /** every requested search -> config hash. */
  bySearch: Record<string, string>;
  /** `aot`: every Emotion rule found in home + census, as plain CSS text (not yet layered). */
  css: string;
  /** `aot`: every Emotion cache id that css contains; the client marks these inserted before hydration. */
  ids: string[];
  /** `runtime`: inline `<style data-emotion>` tags for the home page (plain Emotion SSR). */
  styleTags: string;
  /** `aot`: census page html (inspection only, written to dist/.census-aot.html, never linked). */
  censusHtml: string;
  stats: { homeBytes: number; censusBytes: number; ruleChunks: number };
}

/** Runs once at build time, in Node. */
export function prerender(searches: string[] = ['']): PrerenderResult {
  // Every page is stored under the canonical key of its flag set (lean/Fw/Wire/FlagKey.lean), whatever order the caller typed.
  const list = [...new Set((searches.includes('') ? searches : ['', ...searches]).map(canonSearch))];

  const cache = createServerCache();
  // Sets `cache.compat = true`: Emotion then collects rules instead of rendering inline `<style>` tags.
  const { extractCriticalToChunks, constructStyleTagsFromChunks } = createEmotionServer(cache);

  const pages: PrerenderedPage[] = [];
  const bySearch: Record<string, string> = {};
  for (const search of list) {
    const resolved = resolveSearch(search);
    if (!resolved.ok) throw new Error(`config "${search}": ${resolved.errors.join('; ')}`);
    bySearch[search] = resolved.configHash;
    if (pages.some((p) => p.configHash === resolved.configHash)) continue;
    const html = renderToString(
      <Root cache={cache}>
        <App config={resolved.config} />
      </Root>,
    );
    pages.push({ search, configHash: resolved.configHash, homeHtml: html });
  }
  const homeHtml = pages[0]!.homeHtml;
  const aot = __FW_ENGINE__ === 'aot';
  const censusHtml = aot
    ? renderToString(
        <Root cache={cache}>
          <Census />
        </Root>,
      )
    : '';

  // The extractor keeps the regular rules whose class names occur in the given html, so hand it both pages.
  const chunks = extractCriticalToChunks(pages.map((p) => p.homeHtml).join('') + censusHtml);
  return {
    configHash: pages[0]!.configHash,
    homeHtml,
    pages,
    bySearch,
    css: aot ? chunks.styles.map((s) => s.css).join('') : '',
    // Every id Emotion inserted, not only those whose class is in the HTML: a styled(Wrapper) also inserts its own
    // intermediate rule (its class is merged into the child's, never put on the DOM). Those rules are dead CSS,
    // so they are not emitted, but the client must still know they are "inserted" or it would insert them.
    ids: aot ? Object.keys(cache.inserted) : [],
    censusHtml,
    styleTags: aot ? '' : constructStyleTagsFromChunks(chunks),
    stats: { homeBytes: homeHtml.length, censusBytes: censusHtml.length, ruleChunks: chunks.styles.length },
  };
}
