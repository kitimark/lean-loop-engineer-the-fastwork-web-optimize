import { useEffect, useRef, type ReactNode } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { getScrollEngine } from '../../engine/scroll';
import { watchActive } from '../people/shared';
import { HEADING } from './content';
import { bindScene, createSceneWriter, type SceneWriter } from './scene';
import { createFadedPause, fadedBus, type FadedPause } from './fade.driver';
import { FADED_PAUSE } from './fade.logic';
import { createPause } from '../platform.glint/pause';
import { createShrink } from './driver';
import { matchList } from './media';
import css from './platform.module.css';
import sw from './sweep.module.css';
import st from './stage.module.css';
import { Ask, Invoice, Profile, Secure, type Subs } from './Visuals';
import { VARIANT as SWEEP_PAUSE, watchSweepPause } from '../platform.sweep/pause';
import { VARIANT as SWEEP_LAYER } from '../platform.sweep/layer';

export interface PlatformSubVariants {
  sweep?: string;
  glint?: string;
  entries?: string;
  stageBg?: string;
  marquee?: string;
}

export interface PlatformProps {
  variant: string;
  impl?: 'mui' | 'plain';
  sub?: PlatformSubVariants;
}

/** Where the shrink sits on the scroll engine: before nav.hitTest (order 100), which reads the section's state. */
export const SHRINK_ORDER = 95;

const cx = (...c: Array<string | false | undefined>) => c.filter(Boolean).join(' ');

function Row({ id, flip, stage, children }: { id: string; flip?: boolean; stage: ReactNode; children: ReactNode }) {
  return (
    <article className={cx(css.row, flip && css.rowFlip)} data-fw-row={id}>
      {stage}
      <div className={css.rowCopy}>
        <div className={css.rowIntro}>{children}</div>
      </div>
    </article>
  );
}

function Stage({ kind, flip, invoice, children }: { kind: 'secureMesh' | 'mesh' | 'photo' | 'quote'; flip?: boolean; invoice?: boolean; children: ReactNode }) {
  const mesh = kind === 'secureMesh' || kind === 'mesh';
  return (
    <div className={cx(st.stage, css.stageSlot, mesh && st.meshBg, kind === 'secureMesh' && st.secureMesh, invoice && st.invoice)} data-fw-flip={flip ? '' : undefined}>
      {mesh ? <div className={st.grain} aria-hidden="true" /> : null}
      {kind === 'photo' ? (
        <picture className={st.picture}>
          <source srcSet="/selling/optimized/platform/service-bg.avif" type="image/avif" />
          <img className={st.bg} loading="lazy" decoding="async" src="/selling/platform/service-bg.jpg" alt="" />
        </picture>
      ) : null}
      {kind === 'quote' ? (
        <picture className={st.picture}>
          <img className={cx(st.bg, st.bgQuote)} loading="lazy" decoding="async" src="/selling/platform/service-quote/bg.png" alt="" />
        </picture>
      ) : null}
      <div className={st.visual}>
        <div className={st.artboard}>{children}</div>
      </div>
    </div>
  );
}

function Check() {
  return (
    <span className={css.rowCheckIcon} aria-hidden="true">
      <GenSvg art={art('platform.check')} />
    </span>
  );
}

/**
 * platform (P5, `faithful`): the dark card with the mission line and four rows (copy beside a scaled 640 x 512 stage).
 * Sub-parts: platform.sweep (CSS class on the four title words), platform.stageBg (stage.module.css), platform.glint,
 * platform.entries and platform.marquee (Visuals.tsx drivers). The card shrinks with scroll through one engine callback that
 * writes `--platform-shrink` and a class on the section (driver.ts; decisions are Lean `PlatformSection`). `--morph-fade`
 * is written on the section by morph.tween. Placeholder-free: copy, geometry and colours are the original's.
 */
export function Platform({ variant, sub = {} }: PlatformProps) {
  const section = useRef<HTMLElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const faithful = (v: string | undefined) => (v ?? 'faithful') === 'faithful';
  const sweepPause = sub.sweep === SWEEP_PAUSE;
  const sweepLayer = sub.sweep === SWEEP_LAYER;
  const sweep = faithful(sub.sweep) || sweepPause ? sw.sweep : sub.sweep === 'probe-off' ? cx(sw.sweep, sw.still) : sweepLayer ? cx(sw.sweep, sw.layer) : undefined;
  const layerBg = sweepLayer ? <i className={sw.layerBg} aria-hidden="true" /> : null;
  const subs: Subs = { entries: faithful(sub.entries), glint: faithful(sub.glint) || sub.glint === 'offscreen-pause', glintPause: sub.glint === 'offscreen-pause', marquee: faithful(sub.marquee) };

  useEffect(() => {
    const sec = section.current;
    const c = card.current;
    if (!sec || !c) return;
    const reduce = matchList('mq.rm-reduce');
    const c860 = variant === 'mq' ? matchList('mq.c860') : null;
    const frame = createShrink(
      {
        cardBottom: () => c.getBoundingClientRect().bottom,
        setShrink: (x) => sec.style.setProperty('--platform-shrink', String(x)),
        setShrinking: (on) => sec.classList.toggle(css.isShrinking!, on),
      },
      { reduced: () => reduce?.matches ?? false, vh: () => window.innerHeight },
      { gate: () => c860?.matches === true },
    );
    frame();
    // leaving the band (rotation, resize): write the current value now, before the next paint (Lean PlatformShrinkOpt P1)
    const onBand = () => frame();
    c860?.addEventListener('change', onBand);
    const off = getScrollEngine().register('platform.shrink', SHRINK_ORDER, () => frame());
    let faded: FadedPause | null = null;
    const writer: SceneWriter = createSceneWriter(sec, (v) => faded?.onScene(v));
    const stopScene = bindScene(sec, watchActive, writer);
    let unsubFaded: (() => void) | null = null;
    if (variant === FADED_PAUSE) {
      const dashes = createPause(() => Array.from(sec.querySelectorAll<SVGSVGElement>('[data-fw-dash] svg')), () => performance.now());
      faded = createFadedPause({ animations: () => sec.getAnimations({ subtree: true }).filter((a) => a instanceof CSSAnimation), svg: { away: dashes.away, back: dashes.back } }, writer.setFaded);
      unsubFaded = fadedBus.subscribe(faded.set);
    }
    return () => {
      unsubFaded?.();
      faded?.dispose();
      stopScene();
      c860?.removeEventListener('change', onBand);
      off();
    };
  }, []);

  useEffect(() => {
    const sec = section.current;
    if (!sweepPause || !sec) return;
    return watchSweepPause([...sec.querySelectorAll(`.${sw.sweep}`)]);
  }, [sweepPause]);

  return (
    <section ref={section} id="platform" className={css.section} data-fw="platform" data-fw-variant={variant} aria-labelledby="built-heading">
      <div ref={card} className={css.card}>
        <div className={css.layout}>
          <div className={css.mission}>
            <div className={css.missionHeader}>
              <div className={css.missionCopy}>
                <p id="built-heading" className={css.missionTitle}>
                  {HEADING}
                </p>
              </div>
            </div>
            <div className={css.rows}>
              <Row
                id="document"
                stage={
                  <Stage kind="secureMesh">
                    <Profile subs={subs} />
                  </Stage>
                }
              >
                <h3 className={css.rowTitle}>
                  <span className={cx(css.word, sweep)} data-fw-sweep="">Document{layerBg}</span> <span className={css.rest}>your portfolio and reviews</span>
                </h3>
              </Row>
              <Row
                id="discovered"
                flip
                stage={
                  <Stage kind="photo" flip>
                    <Ask subs={subs} />
                  </Stage>
                }
              >
                <h3 className={css.rowTitle}>
                  <span className={cx(css.rest, css.restBlock)}>Get discovered.</span> <span className={cx(css.word, sweep)} data-fw-sweep="">Earn{layerBg}</span> <span className={css.rest}>more</span>
                </h3>
              </Row>
              <Row
                id="payment"
                stage={
                  <Stage kind="mesh">
                    <Secure subs={subs} />
                  </Stage>
                }
              >
                <h3 className={css.rowTitle}>
                  <span className={cx(css.word, sweep)} data-fw-sweep="">Secure{layerBg}</span> <span className={css.rest}>payment worldwide</span>
                </h3>
                <ul className={css.rowChecks}>
                  <li className={css.rowCheck}>
                    <Check /> Payment Protection
                  </li>
                  <li className={css.rowCheck}>
                    <Check /> Daily Withdrawal
                  </li>
                </ul>
              </Row>
              <Row
                id="relationship"
                flip
                stage={
                  <Stage kind="quote" flip invoice>
                    <Invoice subs={subs} />
                  </Stage>
                }
              >
                <h3 className={css.rowTitle}>
                  <span className={css.titleF}>
                    <span className={cx(css.word, sweep)}>Maintain{layerBg}</span> <span className={css.rest}>relationship with your clients</span>
                  </span>{' '}
                  <span className={css.titleI}>
                    <span className={cx(css.rest, css.restBlock)}>Keep every order</span> <span className={cx(css.word, css.wordFree, sweep)} data-fw-sweep="">Organized{layerBg}</span>
                  </span>
                </h3>
              </Row>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
