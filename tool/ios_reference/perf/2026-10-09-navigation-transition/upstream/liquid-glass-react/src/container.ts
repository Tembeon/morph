// GlassEffectContainer, glassEffectUnion and GlassEffectTransition, ported.
//
// The semantics here are Apple's, from "Applying Liquid Glass to custom views":
//
//   * "The larger the spacing value on the container, the sooner the Liquid
//     Glass effects behind views blend together and merge the shapes during a
//     transition."  -> spacing IS the smooth-union k. It is not a layout gap.
//   * Shapes merge "when the nearest edge is less than or equal to the
//     container's spacing".  -> the test is edge distance, not centre distance.
//   * glassEffectUnion(id:namespace:) merges shapes with the same id "even when
//     your content is at rest", independent of distance.
//   * matchedGeometry is the default for effects "positioned within the
//     container's assigned spacing"; materialize is for effects "farther from
//     each other than the container's assigned spacing".
//
// One draw per group, so a merged group is shaded ONCE — which is the whole
// reason a merge looks like one body of glass instead of two overlapping ones.

export const GlassEffectTransition = {
  matchedGeometry: 'matchedGeometry',
  materialize: 'materialize',
};

/** Edge-to-edge distance between two rects; 0 when they touch or overlap. */
export interface Rect { x: number; y: number; w: number; h: number; }

export function edgeGap(a: Rect, b: Rect): number {
  const dx = Math.max(0, Math.max(a.x - (b.x + b.w), b.x - (a.x + a.w)));
  const dy = Math.max(0, Math.max(a.y - (b.y + b.h), b.y - (a.y + a.h)));
  return Math.hypot(dx, dy);
}

/** "Sufficiently similar": same variant, same tint, same corner treatment. */
function similar(a: any, b: any): boolean {
  const ga = a.glass || {}, gb = b.glass || {};
  if ((ga.variant ?? 'regular') !== (gb.variant ?? 'regular')) return false;
  if ((ga.tintAmount ?? 0) !== (gb.tintAmount ?? 0)) return false;
  if ((ga.tintAmount ?? 0) > 0) {
    const ta = ga.tintColor || [1,1,1], tb = gb.tintColor || [1,1,1];
    if (ta.some((v: number, i: number) => Math.abs(v - tb[i]) > 0.01)) return false;
  }
  return (a.exponent ?? 2) === (b.exponent ?? 2);
}

// Element sizes, in CSS px, between which the material gains opacity.
// 44 is a standard control; 260 is sidebar territory.
const SIZE_OPACITY_MIN = 44, SIZE_OPACITY_MAX = 260, SIZE_OPACITY_GAIN = 1.35;

// The shader carries a primary shape plus uShape2..4.
const MAX_PER_DRAW = 4;

export class GlassEffectContainer {
  /**
   * @param renderer  something with .render(params, backdropRect)
   * @param spacing   merge distance in CSS px
   */
  [k: string]: any;
  constructor(renderer: any, { spacing = 0, onOverflow = null, transitionMs = 300 }: { spacing?: number; onOverflow?: ((n: number, max: number) => void) | null; transitionMs?: number } = {}) {
    this.renderer = renderer;
    this.spacing = spacing;
    this.onOverflow = onOverflow;
    this.transitionMs = transitionMs;
    this.effects = new Map();
    // Effects that have been removed from the view hierarchy but are still
    // dissolving. The container keeps drawing them until diffusion reaches 0 --
    // otherwise the element's DOM is gone the instant React unmounts it and the
    // material would simply blink out, which is the one thing Liquid Glass
    // never does.
    this.leaving = new Map();
  }

  /**
   * @param id  the glassEffectID
   * @param e   {rect:{x,y,w,h}, glass, unionId?, diffusion?, exponent?, press?}
   *            rect is in container-canvas CSS px, origin top-left.
   */
  set(id: string, e: Record<string, any>) {
    // Re-entering while still dissolving: resume from where it got to rather
    // than snapping back to 0.
    const out = this.leaving.get(id);
    const prev = this.effects.get(id);
    const born = out ? out.diffusion : (prev?.born ?? 0);
    // bornAt must survive: set() runs every frame, and dropping it reset the
    // ramp's origin each time so `born` never climbed off zero.
    const bornAt = out ? null : (prev?.bornAt ?? null);
    this.leaving.delete(id);
    // px/py/vel must survive the per-frame set() for the same reason bornAt
    // does: replacing the entry wholesale resets the motion history and the
    // measured velocity is always zero.
    this.effects.set(id, { diffusion: 1, unionId: null, ...e, born, bornAt,
                           px: prev?.px, py: prev?.py, vel: prev?.vel });
    return this;
  }

  /** Removed from the hierarchy: hand it to the dissolve, keeping its last rect. */
  delete(id: string) {
    const e = this.effects.get(id);
    if (e && !this.leaving.has(id)) {
      this.leaving.set(id, { ...e, diffusion: e.born ?? 1,
                             leftFrom: e.born ?? 1, leftAt: this._now });
    }
    this.effects.delete(id);
  }
  get(id: string) { return this.effects.get(id); }

  /**
   * Explicit unions first, then transitive proximity merging. Apple's rule is
   * pairwise, so A-B and B-C merging implies A-B-C; union-find gets that right
   * where a single pass would not.
   */
  /**
   * Advance both ramps. GlassEffectTransition.materialize: the material animates
   * in and out and the content fades with it. Called once per frame by render().
   */
  tick(dtMs: number, nowMs?: number) {
    // Absolute time, not accumulated per-frame steps: accumulating drifts with
    // frame timing and made the dissolve finish in ~55ms instead of 300.
    const now = nowMs ?? 0;
    const D = Math.max(this.transitionMs, 1);
    for (const [, e] of this.effects) {
      if (e.transition === 'identity') { e.born = 1; continue; }
      if (e.bornAt == null || e.bornAt === undefined) e.bornAt = now;
      // Materialize-in, decoded: smooth ease with a brief ~3% overshoot before
      // settling, which the shader turns into the >1.0 scale blip Apple shows.
      const bt = Math.min(1, (now - e.bornAt) / D);
      const es = bt * bt * (3 - 2 * bt);
      e.born = bt >= 1 ? 1 : es * (1 + 0.06 * Math.sin(bt * Math.PI));
    }
    for (const [id, e] of this.leaving) {
      if (e.transition === 'identity') { this.leaving.delete(id); continue; }
      const t = Math.min(1, (now - e.leftAt) / D);
      const es = t * t * (3 - 2 * t);           // dissolve-out: plain ease
      e.diffusion = e.leftFrom * (1 - es);
      if (t >= 1) this.leaving.delete(id);
    }
  }

  /** Content alpha for an effect, so callers can fade the label with the glass. */
  contentAlpha(id: string): number {
    const e = this.effects.get(id);
    if (e) return Math.min(1, (e.born ?? 1) * 1.4);
    const o = this.leaving.get(id);
    return o ? Math.min(1, o.diffusion * 1.4) : 0;
  }

  groups() {
    const live = [...this.effects.entries()].map(([id, e]) =>
      [id, { ...e, diffusion: e.diffusion * (e.born ?? 1) }]);
    const items = [...live, ...this.leaving.entries()]
      .filter(([, e]) => e.diffusion > 0.001);
    const parent: number[] = items.map((_, i) => i);
    const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    const join = (i: number, j: number) => { const a = find(i), b = find(j); if (a !== b) parent[a] = b; };

    for (let i = 0; i < items.length; i++) {
      for (let j = i + 1; j < items.length; j++) {
        const [, A] = items[i], [, B] = items[j];
        const sameUnion = A.unionId != null && A.unionId === B.unionId;
        // ToolbarSpacer(.flexible/.fixed) decides whether toolbar items share one
        // glass capsule or split into separate ones. Modelled as a section: a
        // spacer starts a new section, and effects in different sections never
        // merge however close they sit. An explicit union id still wins, which
        // matches glassEffectUnion overriding layout proximity.
        if (!sameUnion && A.section != null && B.section != null
            && A.section !== B.section) continue;
        // NSGlassEffectContainerView merges descendants "if the views are
        // sufficiently similar AND within the proximity specified in spacing".
        // Proximity alone would fuse a tinted panel into an untinted one.
        if (sameUnion || (similar(A, B) && edgeGap(A.rect, B.rect) <= this.spacing)) join(i, j);
      }
    }
    const byRoot = new Map<number, any[]>();
    items.forEach((it, i) => {
      const r = find(i);
      if (!byRoot.has(r)) byRoot.set(r, []);
      byRoot.get(r)!.push(it);
    });
    return [...byRoot.values()];
  }

  /**
   * The transition Apple would pick for an effect: matchedGeometry if it has a
   * neighbour within spacing (so there is a shape to flow into), otherwise
   * materialize.
   */
  transitionFor(id: string): string {
    const e = this.effects.get(id);
    if (!e) return GlassEffectTransition.materialize;
    for (const [oid, o] of this.effects) {
      if (oid === id) continue;
      if (edgeGap(e.rect, o.rect) <= this.spacing) return GlassEffectTransition.matchedGeometry;
    }
    return GlassEffectTransition.materialize;
  }

  /**
   * @param canvas  {w,h} of the container canvas in CSS px
   * @param base    baseParams() for this frame
   * @param toBackdropRect  (paddedRectInCanvasSpace) -> normalized backdrop rect
   */
  render(canvas: { w: number; h: number }, base: Record<string, any>, toBackdropRect: (r: Rect) => number[], dtMs = 16, nowMs = 0) {
    this._now = nowMs;
    this.measureVelocity();
    this.tick(dtMs, nowMs);
    let drawn = 0;
    for (const group of this.groups()) {
      for (let i = 0; i < group.length; i += MAX_PER_DRAW) {
        const chunk = group.slice(i, i + MAX_PER_DRAW);
        if (group.length > MAX_PER_DRAW && i === 0 && this.onOverflow) {
          // Never truncate silently: a dropped shape looks like a layout bug.
          this.onOverflow(group.length, MAX_PER_DRAW);
        }
        // Only the first draw clears; the rest accumulate into the same canvas.
        this.#draw(chunk, canvas, base, toBackdropRect, drawn++ > 0);
      }
    }
    if (drawn === 0) this.renderer.clear?.();
  }

  #draw(chunk: any[], canvas: { w: number; h: number }, base: Record<string, any>, toBackdropRect: (r: Rect) => number[], keep: boolean) {
    const [, primary] = chunk[0];
    const p = Object.assign({}, base, primary.glass.uniforms());

    // The primary defines the draw's own geometry; the shader centres it, so
    // extras are expressed as offsets from the CANVAS centre.
    p.halfSize = [primary.rect.w / 2, primary.rect.h / 2];
    p.exponent = primary.exponent ?? 2.0;
    p.diffusion = primary.diffusion;
    // k = spacing, NOT 2*spacing. The polynomial smin bridges once gap <= k/2,
    // so this puts the visible meniscus at gap <= spacing/2.
    //
    // That looks like it under-reads Apple's "effects blend when the nearest
    // edge is within spacing", and I briefly doubled it to make the two line
    // up. Apple's own Landmarks sample says otherwise: BadgesView uses
    // GlassEffectContainer(spacing: 16) with a VStack(spacing: 14), i.e. a 14pt
    // gap INSIDE the 16pt spacing, and the badges render as five cleanly
    // separate tiles with no bridge at all. k = 2*spacing would have fused
    // them. So spacing governs which effects are grouped and animated
    // together; the meniscus itself only appears much closer in.
    p.mergeK = this.spacing;

    // Drag: velocity from the rect delta between frames, in shape-local px with
    // Y up to match vUV. Smoothed so a single jumpy frame does not snap the
    // shape, and decayed so it relaxes when motion stops.
    p.dragVec = primary.vel || [0, 0];
    p.dragStretch = primary.glass?.dragStretch ?? 0.05;

    // HIG > Color: "Liquid Glass appears more opaque in larger elements like
    // sidebars to preserve legibility over complex backgrounds and accommodate
    // richer content on the material's surface." Opacity is size-dependent.
    // Ramp across the range between a toolbar control and a sidebar; FITTED,
    // since the HIG states the behaviour but no numbers.
    const minSide = Math.min(primary.rect.w, primary.rect.h);
    const t = Math.min(1, Math.max(0, (minSide - SIZE_OPACITY_MIN) /
                                      (SIZE_OPACITY_MAX - SIZE_OPACITY_MIN)));
    const sizeOpacity = 1 + (SIZE_OPACITY_GAIN - 1) * (t * t * (3 - 2 * t));
    p.faceOpacity = (p.faceOpacity ?? 1) * sizeOpacity;

    // vUV is pixel space with Y UP; rects are Y DOWN. Flipping the sign here is
    // the difference between a shape merging upward and merging into the wrong
    // side of the bar.
    const cx = (r: Rect) => (r.x + r.w / 2) - canvas.w / 2;
    const cy = (r: Rect) => -((r.y + r.h / 2) - canvas.h / 2);

    const px = cx(primary.rect), py = cy(primary.rect);
    p.extraCount = chunk.length - 1;
    for (let k = 1; k < MAX_PER_DRAW; k++) {
      const slot = ['shape2', 'shape3', 'shape4'][k - 1];
      const ent = chunk[k];
      p[slot] = ent
        ? [cx(ent[1].rect) - px, cy(ent[1].rect) - py, ent[1].rect.w / 2, ent[1].rect.h / 2]
        : [0, 0, 0, 0];
    }

    // The draw covers the whole canvas; the shader discards outside coverage.
    this.renderer.render(p, toBackdropRect({ x: 0, y: 0, w: canvas.w, h: canvas.h }), {
      centerOffset: [px, py], keep,
    });
  }
}
