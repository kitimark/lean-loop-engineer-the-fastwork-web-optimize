import createEmotionServer from '@emotion/server/create-instance';
import { renderToString } from 'react-dom/server';
import { App } from './App';
import { Census } from './Census';
import { createServerCache } from './emotion';
import { resolveSearch } from './registry';
import { Root } from './Root';
import { themeVariablesCss } from './theme';

export interface PrerenderResult {
  configHash: string;
  /** HTML of the home page for the default (all `faithful`) config. */
  homeHtml: string;
  /** `aot`: every Emotion rule found in home + census, as plain CSS text (not yet layered). */
  css: string;
  /** `aot`: every Emotion cache id that css contains; the client marks these inserted before hydration. */
  ids: string[];
  /** `aot`: the theme's CSS variable sheet. */
  themeCss: string;
  /** `runtime`: inline `<style data-emotion>` tags for the home page (plain Emotion SSR). */
  styleTags: string;
  /** `aot`: census page html (inspection only, written to dist/.census-aot.html, never linked). */
  censusHtml: string;
  stats: { homeBytes: number; censusBytes: number; ruleChunks: number };
}

/** Runs once at build time, in Node. */
export function prerender(): PrerenderResult {
  const resolved = resolveSearch('');
  if (!resolved.ok) throw new Error(resolved.errors.join('; '));

  const cache = createServerCache();
  // Sets `cache.compat = true`: Emotion then collects rules instead of rendering inline `<style>` tags.
  const { extractCriticalToChunks, constructStyleTagsFromChunks } = createEmotionServer(cache);

  const homeHtml = renderToString(
    <Root cache={cache}>
      <App config={resolved.config} />
    </Root>,
  );
  const aot = __FW_ENGINE__ === 'aot';
  const censusHtml = aot
    ? renderToString(
        <Root cache={cache}>
          <Census />
        </Root>,
      )
    : '';

  // The extractor keeps the regular rules whose class names occur in the given html, so hand it both pages.
  const chunks = extractCriticalToChunks(homeHtml + censusHtml);
  return {
    configHash: resolved.configHash,
    homeHtml,
    css: aot ? chunks.styles.map((s) => s.css).join('') : '',
    // Every id Emotion inserted, not only those whose class is in the HTML: a styled(Wrapper) also inserts its own
    // intermediate rule (its class is merged into the child's, never put on the DOM). Those rules are dead CSS,
    // so they are not emitted, but the client must still know they are "inserted" or it would insert them.
    ids: aot ? Object.keys(cache.inserted) : [],
    themeCss: aot ? themeVariablesCss() : '',
    censusHtml,
    styleTags: aot ? '' : constructStyleTagsFromChunks(chunks),
    stats: { homeBytes: homeHtml.length, censusBytes: censusHtml.length, ruleChunks: chunks.styles.length },
  };
}
