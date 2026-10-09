// Analytic geometry for the final pass: up to ANALYTIC_MAX_SHAPES separate
// shapes evaluated per fragment with the geometry pass's own SDF functions
// (gpu/sdf.glsl), instead of a Flutter GPU matte. Every quantity is the one
// the geometry pass encodes and the final pass decodes - the signed edge
// distance with its encode and decode ranges, the optical normal, the bevel
// displacement and the nearest shape's tint - evaluated continuously, so
// only the matte's 12-bit and companded quantization and its pixel sampling
// are gone.
//
// Shapes never blend here (the layer sends only frames whose every shape
// is its own group), so sceneSample is the plain minimum of its shapes.
//
// A fused body (uAnalyticRanges.y boxes, at most ANALYTIC_MAX_BOXES) is
// instead the glass container's merge law over its rounded boxes, the law
// the package samples into a field on the CPU (lib/src/liquid_field.dart
// LiquidField.eval and lib/src/widgets/glass_outline.dart): the distance
// is the angular fold, whose blend width is k sin^2 of half the angle
// between the carried and the next normal (not sdf.glsl's
// angularBlendRadius); the half thickness and the optical turn of the
// corners are folded separately by the plain polynomial smooth minimum
// over the full spacing. The gradient is the distance's central
// difference over one device pixel, turned like the field's.
//
// Included by liquid_glass_final_render_core.glsl after its uniforms, so
// these uniforms follow its float uniforms (from float index 65).

#define ANALYTIC_MAX_SHAPES 8
#define ANALYTIC_MAX_BOXES 4
#define MAX_SHAPES ANALYTIC_MAX_SHAPES

// x: refraction height, y: edge displacement (the encode scale), z: 1 when
// the refraction fits the shape, w: the number of shapes. Device px.
uniform vec4 uAnalyticOptics;
// x: the exterior range the matte encodes (the contour extent the geometry
// pass receives), y: the fused body's box count (0 for separate shapes),
// z: the merge spacing, w: the narrowest merge width that blends. Device
// px.
uniform vec4 uAnalyticRanges;
uniform vec4 uShapeData[MAX_SHAPES * 3];
uniform vec4 uRseData[MAX_SHAPES * 3];
uniform vec4 uShapeBounds[MAX_SHAPES];
// Per fused box: (center, half extents), then (corner radius, 0, 0, 0),
// the radius already clamped to the half extents.
uniform vec4 uFusedBoxes[ANALYTIC_MAX_BOXES * 2];
#if SHAPE_TINT
uniform vec4 uShapeTints[MAX_SHAPES];
#endif

#define SCENE_SAMPLE_INDEX 1
#include "gpu/sdf.glsl"

struct AnalyticGeometry {
    // Inward positive, as decodeSignedEdgeDistance returns it.
    float signedEdgeDistance;
    // Unit optical normal, as decodeSurfaceNormal returns it.
    vec2 surfaceNormal;
    // Displacement before the appearance's visibility, as
    // decodeDisplacement returns it.
    vec2 displacement;
    // The nearest shape's tint, unpremultiplied, as the material map holds
    // it.
    vec4 tint;
};

// The signed distance of fused box [i] at p and its unit normal: the
// normal of the corner circle outside the inner rectangle, else the
// dominant axis, mirrored into p's quadrant.
vec3 fusedBox(vec2 p, int i) {
    vec4 box = uFusedBoxes[i * 2];
    float r = uFusedBoxes[i * 2 + 1].x;
    vec2 local = p - box.xy;
    vec2 q = abs(local) - box.zw + r;
    vec2 outside = max(q, vec2(0.0));
    float len = length(outside);
    float d = len - r + min(max(q.x, q.y), 0.0);
    vec2 normal = len > 0.0
        ? outside / len
        : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    normal *= vec2(
        local.x < 0.0 ? -1.0 : 1.0,
        local.y < 0.0 ? -1.0 : 1.0
    );
    return vec3(d, normal);
}

// The angular fold of the fused boxes at p, in list order.
float fusedDistance(vec2 p, int count) {
    float k = uAnalyticRanges.z;
    vec3 carried = fusedBox(p, 0);
    for (int i = 1; i < ANALYTIC_MAX_BOXES; i++) {
        if (i >= count) break;
        vec3 next = fusedBox(p, i);
        if (next.x - carried.x >= k) continue;
        if (carried.x - next.x >= k) {
            carried = next;
            continue;
        }
        float width = k * (1.0 - dot(carried.yz, next.yz)) * 0.5;
        if (width < uAnalyticRanges.w) {
            if (next.x < carried.x) carried = next;
            continue;
        }
        float h = clamp(0.5 + 0.5 * (next.x - carried.x) / width, 0.0, 1.0);
        float d = next.x * (1.0 - h) + carried.x * h -
            width * h * (1.0 - h);
        vec2 n = next.yz * (1.0 - h) + carried.yz * h;
        float len = length(n);
        carried = vec3(d, len > 1e-12 ? n / len : vec2(0.0));
    }
    return carried.x;
}

// The rotation (cos, sin) from fused box [i]'s exact normal at p to the
// normal of a corner kOpticalCornerRadiusScale times rounder; none outside
// the optical corner squares or for a box whose corners cannot get
// rounder.
vec2 fusedTurn(vec2 p, int i) {
    vec4 box = uFusedBoxes[i * 2];
    float exact = uFusedBoxes[i * 2 + 1].x;
    float optical = min(
        exact * kOpticalCornerRadiusScale,
        min(box.z, box.w)
    );
    vec2 local = p - box.xy;
    vec2 a = abs(local) - box.zw;
    vec2 o = a + optical;
    if (optical <= exact || o.x <= 0.0 || o.y <= 0.0) return vec2(1.0, 0.0);
    vec2 e = a + exact;
    vec2 en = e.x > 0.0 && e.y > 0.0
        ? normalize(e)
        : (e.x > e.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    vec2 on = normalize(o);
    float mirror = (local.x < 0.0) != (local.y < 0.0) ? -1.0 : 1.0;
    return vec2(dot(en, on), (en.x * on.y - en.y * on.x) * mirror);
}

// The fused body's half thickness (x) and optical turn (yz) at p: the
// plain polynomial fold over the full spacing.
vec3 fusedOptics(vec2 p, int count) {
    float k = uAnalyticRanges.z;
    vec4 first = uFusedBoxes[0];
    float d = fusedBox(p, 0).x;
    float halfMinor = min(first.z, first.w);
    vec2 turn = fusedTurn(p, 0);
    for (int i = 1; i < ANALYTIC_MAX_BOXES; i++) {
        if (i >= count) break;
        vec4 box = uFusedBoxes[i * 2];
        float di = fusedBox(p, i).x;
        float w = clamp(0.5 + (di - d) / (2.0 * k), 0.0, 1.0);
        float boxHalfMinor = min(box.z, box.w);
        halfMinor = boxHalfMinor + (halfMinor - boxHalfMinor) * w;
        vec2 boxTurn = fusedTurn(p, i);
        turn = boxTurn + (turn - boxTurn) * w;
        float e = max(k - abs(d - di), 0.0);
        d = e > 0.0 ? min(d, di) - e * e / (4.0 * k) : min(d, di);
    }
    float len = length(turn);
    return vec3(halfMinor, len < 1e-9 ? vec2(1.0, 0.0) : turn / len);
}

// How deep inside a body the final pass stops reading its normal and its
// half thickness: past the deepest refraction bevel (no displacement),
// the glint and its bleed, the inner border and the bevel shadow band at
// its largest offset (applySpecularHighlights returns the face unlit), plus
// a pixel.
float analyticFlatDepth() {
    float glintWidth = max(
        uHighlightWidth > 0.0 ? uHighlightWidth : uEdgeWidth,
        0.001
    );
    return max(
        max(uAnalyticOptics.x, glintWidth * kGlintBleedReach),
        max(
            abs(uContourOffset) + uEdgeWidth + 0.5,
            max(uBevelShadowDepth, 0.001) * 1.0001 +
                max(uBevelShadowOffset, 0.0)
        )
    ) + 1.0;
}

AnalyticGeometry analyticGeometry(vec2 p, float inwardRange, float exteriorRange) {
    AnalyticGeometry result;
    // An empty matte pixel decodes to the full exterior range, the normal
    // (1, 0) and no displacement.
    result.signedEdgeDistance = -exteriorRange;
    result.surfaceNormal = vec2(1.0, 0.0);
    result.displacement = vec2(0.0);
    result.tint = vec4(0.0);

    int count = int(uAnalyticOptics.w);
    int boxes = int(uAnalyticRanges.y);
    float sd;
    vec2 opticalGradient;
    float halfMinor;
    if (boxes > 0) {
        sd = fusedDistance(p, boxes);
        // Past the encoded exterior range a matte pixel is empty.
        if (sd >= uAnalyticRanges.x) {
            return result;
        }
        if (-sd > analyticFlatDepth()) {
            // The flat face: no displacement whatever the bevel, and no
            // lighting term reads the normal.
            halfMinor = uAnalyticOptics.x;
            opticalGradient = vec2(1.0, 0.0);
        } else {
            vec2 gradient = vec2(
                fusedDistance(p + vec2(0.5, 0.0), boxes) -
                    fusedDistance(p - vec2(0.5, 0.0), boxes),
                fusedDistance(p + vec2(0.0, 0.5), boxes) -
                    fusedDistance(p - vec2(0.0, 0.5), boxes)
            );
            vec3 optics = fusedOptics(p, boxes);
            halfMinor = optics.x;
            opticalGradient = vec2(
                gradient.x * optics.y - gradient.y * optics.z,
                gradient.x * optics.z + gradient.y * optics.y
            );
        }
        #if SHAPE_TINT
        // The material map's tint: the nearest of the layer's shapes.
        SceneSample tinted = sceneSample(p, count);
        for (int i = 0; i < MAX_SHAPES; i++) {
            if (float(i) == tinted.index) result.tint = uShapeTints[i];
        }
        #endif
    } else {
        // The geometry pass's empty-pixel rejection: farther from every
        // shape's matte-space box than the contour extent plus two pixels.
        vec2 outside = sceneBoundsOutsideSquared(p, count);
        float emptyThreshold = uAnalyticRanges.x + 2.0 + outside.y;
        if (outside.x > emptyThreshold * emptyThreshold) {
            return result;
        }

        // The geometry pass's own scene: with no blends every shape starts
        // a group and the nearest wins, in its order and with its culling.
        SceneSample scene = sceneSample(p, count);
        #if SHAPE_TINT
        // A constant-index chain: the index selects a uniform array
        // element.
        for (int i = 0; i < MAX_SHAPES; i++) {
            if (float(i) == scene.index) result.tint = uShapeTints[i];
        }
        #endif
        sd = scene.distance;
        opticalGradient = scene.opticalNormal;
        halfMinor = scene.halfMinor;
    }
    #if SHAPE_TINT
    if (result.tint.a <= 0.0001) {
        result.tint.rgb = vec3(0.0);
    }
    #endif

    float gradientLength = length(opticalGradient);
    vec2 normal = gradientLength > 0.0001
        ? opticalGradient / gradientLength
        : vec2(1.0, 0.0);

    float refractionHeight = uAnalyticOptics.x;
    float refractionAmount = uAnalyticOptics.y;
    float bevel;
    float amount;
    if (uAnalyticOptics.z > 0.5) {
        bevel = min(refractionHeight, 0.5 * halfMinor);
        amount = min(refractionAmount, halfMinor);
    } else {
        float lensScale = min(
            1.0,
            halfMinor / max(refractionHeight, 0.001)
        );
        bevel = refractionHeight * lensScale;
        amount = refractionAmount * lensScale;
    }
    float bevelX = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacementMagnitude = bevel > 0.001
        ? amount * (1.0 - sqrt(1.0 - bevelX * bevelX))
        : 0.0;
    // The matte stores the magnitude over the encode scale and the final
    // pass multiplies it by the displacement scale.
    float maxDisplacement = max(uDisplacementScale, 0.001);
    result.displacement = -normal * clamp(
        displacementMagnitude / max(refractionAmount, 0.001),
        0.0,
        1.0
    ) * maxDisplacement;
    result.surfaceNormal = normal;

    float inward = -sd;
    result.signedEdgeDistance = inward >= 0.0
        ? min(inward, inwardRange)
        : -min(-inward / max(uAnalyticRanges.x, 0.001), 1.0) * exteriorRange;
    return result;
}
