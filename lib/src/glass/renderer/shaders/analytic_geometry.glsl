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
// is its own group), so the scene is the plain minimum of its shapes.
//
// Included by liquid_glass_final_render_core.glsl after its uniforms, so
// these uniforms follow its float uniforms (from float index 65).

#define ANALYTIC_MAX_SHAPES 8
#define MAX_SHAPES ANALYTIC_MAX_SHAPES

// x: refraction height, y: edge displacement (the encode scale), z: 1 when
// the refraction fits the shape, w: the number of shapes. Device px.
uniform vec4 uAnalyticOptics;
// x: the exterior range the matte encodes (the contour extent the geometry
// pass receives). Device px.
uniform vec4 uAnalyticRanges;
uniform vec4 uShapeData[MAX_SHAPES * 3];
uniform vec4 uRseData[MAX_SHAPES * 3];
uniform vec4 uShapeBounds[MAX_SHAPES];
#if SHAPE_TINT
uniform vec4 uShapeTints[MAX_SHAPES];
#endif

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

AnalyticGeometry analyticGeometry(vec2 p, float inwardRange, float exteriorRange) {
    AnalyticGeometry result;
    // An empty matte pixel decodes to the full exterior range, the normal
    // (1, 0) and no displacement.
    result.signedEdgeDistance = -exteriorRange;
    result.surfaceNormal = vec2(1.0, 0.0);
    result.displacement = vec2(0.0);
    result.tint = vec4(0.0);

    int count = int(uAnalyticOptics.w);
    // The geometry pass's empty-pixel rejection: farther from every shape's
    // matte-space box than the contour extent plus two pixels.
    vec2 outside = sceneBoundsOutsideSquared(p, count);
    float emptyThreshold = uAnalyticRanges.x + 2.0 + outside.y;
    if (outside.x > emptyThreshold * emptyThreshold) {
        return result;
    }

    SceneSample scene;
    scene.distance = 1e9;
    scene.halfMinor = 0.0;
    scene.curvatureFactor = 0.0;
    scene.normal = vec2(0.0);
    scene.opticalNormal = vec2(0.0);
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= count) break;
        SceneSample shape = getShapeSampleFromArray(i, p, false);
        if (shape.distance < scene.distance) {
            scene = shape;
            #if SHAPE_TINT
            result.tint = uShapeTints[i];
            #endif
        }
    }
    #if SHAPE_TINT
    if (result.tint.a <= 0.0001) {
        result.tint.rgb = vec3(0.0);
    }
    #endif

    float sd = scene.distance;
    float gradientLength = length(scene.opticalNormal);
    vec2 normal = gradientLength > 0.0001
        ? scene.opticalNormal / gradientLength
        : vec2(1.0, 0.0);

    float refractionHeight = uAnalyticOptics.x;
    float refractionAmount = uAnalyticOptics.y;
    float bevel;
    float amount;
    if (uAnalyticOptics.z > 0.5) {
        bevel = min(refractionHeight, 0.5 * scene.halfMinor);
        amount = min(refractionAmount, scene.halfMinor);
    } else {
        float lensScale = min(
            1.0,
            scene.halfMinor / max(refractionHeight, 0.001)
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
