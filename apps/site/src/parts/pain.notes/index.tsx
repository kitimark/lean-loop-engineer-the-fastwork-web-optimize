import { useEffect, useRef, useState, type CSSProperties } from "react";
import { getClock } from "../../engine/clock";
import { registerScroll } from "../../engine/scroll";
import { dragNoteLabel, NOTE_TEXT } from "./data";
import { createNotesDriver } from "./driver";
import type { Note } from "./logic";
import { SCENE_MARGIN } from "./logic";
import { matchList } from "./media";
import { createScene } from "./scene";
import css from "./notes.module.css";

/** The seed of the notes' random stream (PLAN section 4.3: a fixed seed so two captures match). */
export const NOTES_SEED = 0x2f6e2b1;
/** Where the per-scroll-frame card check sits on the engine (the original registers it with `dE`, JS 4736). */
export const NOTES_SCROLL_ORDER = 120;

interface View {
  base: Note[];
  extras: Note[];
  dragging: string | null;
}
const EMPTY: View = { base: [], extras: [], dragging: null };

export interface PainNotesProps {
  variant: string;
  /** The commission card whose top clears the extras. The original: `.commission-card`. */
  cardSelector?: string;
}

/**
 * pain.notes (`faithful`, seeded): the sticky-note board of the Pain section. The canvas (the notes' stage, `.pain-canvas`) is empty in the prerendered
 * HTML (as in the original); on the first engine frame after mount the base notes appear (five on desktop, eleven at <= 860 px), and while the board
 * shows (IntersectionObserver, 12 %) a note is added every 3 s up to 12. Notes can be dragged (pointer) or moved with
 * the arrow keys; those moves write the element style directly, React state changes only when the set of notes does.
 * Decisions: logic.ts / driver.ts (Lean `Fw.Parts.PainNotes`). The `animation` of an added note is CSS.
 */
export function PainNotes({
  variant,
  cardSelector = '[data-fw="commission-card"], .commission-card',
}: PainNotesProps) {
  const [view, setView] = useState<View>(EMPTY);
  const stageRef = useRef<HTMLDivElement>(null);
  const driverRef = useRef<ReturnType<typeof createNotesDriver> | null>(null);

  useEffect(() => {
    const stage = stageRef.current;
    const board = stage?.parentElement;
    if (!stage || !board) return;
    const clock = getClock();
    const narrow = matchList("mq.w-le-860");
    const reduce = matchList("mq.rm-reduce");
    const c860 = matchList("mq.c860");
    const frame = (cb: () => void) => {
      let done = false;
      let off: () => void = () => {};
      off = clock.subscribe(
        () => {
          if (done) return;
          done = true;
          off();
          cb();
        },
        { own: true },
      );
      return () => {
        done = true;
        off();
      };
    };
    const section = stage.closest<HTMLElement>('[data-fw="pain"]');
    const card = () => document.querySelector<HTMLElement>(cardSelector);
    const driver = createNotesDriver(
      {
        stageRect: () => stage.getBoundingClientRect(),
        copyRect: () =>
          stage
            .closest('[data-fw="pain"]')
            ?.querySelector('[data-fw="pain-copy"]')
            ?.getBoundingClientRect() ?? null,
        cardTop: () => card()?.getBoundingClientRect().top ?? null,
        innerHeight: () => window.innerHeight,
        narrow: () => narrow?.matches ?? false,
        reduced: () => reduce?.matches ?? false,
        c860: () => c860?.matches ?? false,
        interval: (ms, cb) => clock.interval(ms, cb),
        frame,
        commit: setView,
        writeNote: (id, left, top, z) => {
          const el = stage.querySelector<HTMLElement>(`[data-fw-note="${id}"]`);
          if (!el) return;
          el.style.left = `${left}%`;
          el.style.top = `${top}%`;
          el.style.zIndex = String(z);
        },
      },
      NOTES_SEED,
    );
    driverRef.current = driver;
    driver.start();
    const scene = createScene({
      sectionRect: () => section?.getBoundingClientRect() ?? null,
      innerHeight: () => window.innerHeight,
      frame,
      setScene: (st) => section?.setAttribute("data-scene", st),
      getRender: () => section?.getAttribute("data-render") as "active" | "deferred" | null,
      setRender: (st) => section?.setAttribute("data-render", st),
      setIntrinsic: (px) => section?.style.setProperty("--start-selling-intrinsic-block-size", `${px}px`),
      onActivate: () => {},
    });
    scene.start();
    const sceneIo = section
      ? new IntersectionObserver(
          (entries) => {
            for (const e of entries) scene.intersect(e.isIntersecting);
          },
          { rootMargin: SCENE_MARGIN },
        )
      : null;
    if (section) sceneIo?.observe(section);

    const io = new IntersectionObserver(
      ([e]) => driver.intersect(!!e?.isIntersecting, e?.intersectionRatio ?? 0),
      { threshold: [0, 0.12, 0.25, 0.5] },
    );
    io.observe(board);
    const ro = new ResizeObserver(() => driver.relayout());
    ro.observe(stage);
    const onNarrow = () => driver.relayout();
    narrow?.addEventListener("change", onNarrow);
    const move = (e: PointerEvent) => driver.pointerMove(e);
    const end = () => driver.pointerEnd();
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
    const offScroll = registerScroll("pain.notes", NOTES_SCROLL_ORDER, () => {
      if (scene.active()) driver.onScroll();
    });
    return () => {
      offScroll();
      io.disconnect();
      sceneIo?.disconnect();
      scene.dispose();
      section?.removeAttribute("data-scene");
      section?.removeAttribute("data-render");
      section?.style.removeProperty("--start-selling-intrinsic-block-size");
      ro.disconnect();
      narrow?.removeEventListener("change", onNarrow);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
      driver.dispose();
      driverRef.current = null;
    };
  }, [cardSelector]);

  const notes = [...view.base, ...view.extras];
  return (
    <div
      ref={stageRef}
      className={css.canvas}
      data-fw="pain-notes"
      data-fw-variant={variant}
    >
      {notes.map((n) => {
        const text = NOTE_TEXT[n.text] ?? "";
        const cls = [
          css.note,
          n.extra ? css.extra : "",
          view.dragging === n.id ? css.dragging : "",
        ]
          .filter(Boolean)
          .join(" ");
        const style = {
          "--note-bg": n.bg,
          "--note-rotate": `${n.rotate}deg`,
          left: `${n.left}%`,
          top: `${n.top}%`,
          width: "240px",
          height: "240px",
          zIndex: view.dragging === n.id ? 40 : n.z,
        } as CSSProperties;
        return (
          <div
            key={n.id}
            role="button"
            tabIndex={0}
            className={cls}
            style={style}
            aria-label={dragNoteLabel(text)}
            data-selenium={`start-selling.pain.button.note.${n.id}`}
            data-fw-note={n.id}
            onPointerDown={(e) => {
              const taken = driverRef.current?.pointerDown(n.id, {
                pointerId: e.pointerId,
                clientX: e.clientX,
                clientY: e.clientY,
                button: e.button,
                mouse: e.pointerType === "mouse",
              });
              if (!taken) return;
              e.preventDefault();
              e.stopPropagation();
              e.currentTarget.setPointerCapture(e.pointerId);
            }}
            onKeyDown={(e) => {
              if (driverRef.current?.key(n.id, e.key)) e.preventDefault();
            }}
          >
            <p>{text}</p>
          </div>
        );
      })}
    </div>
  );
}
