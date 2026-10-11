// Copyright 2025, Tim Lehmann for whynotmake.it

// Deliberately low-resolution per-shape appearance map. The full-resolution
// geometry pass remains authoritative for optics and lighting; this pass only
// supplies a smooth, approximate tint transition between nearby shapes. It
// shares the geometry pass's analytic normals.

#define MAX_SHAPES 32

#ifndef MATERIAL_TINT_OUTPUT
#define MATERIAL_TINT_OUTPUT 0
#endif

layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 3];
    vec4 uShapeTints[MAX_SHAPES];
    vec4 uShapeResponses[MAX_SHAPES];
    vec4 uShapeBounds[MAX_SHAPES];
} geometryUniforms;

#define uOffset geometryUniforms.uOffset
#define uNumShapes (geometryUniforms.uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData
#define uShapeBounds geometryUniforms.uShapeBounds
#define uMaterialRasterScale (geometryUniforms.uContourProps.y)
#define uMaterialMapSize (geometryUniforms.uContourProps.zw)

#include "sdf.glsl"
#include "material_sdf.glsl"

out vec4 fragColor;

// Any index past the last shape, or negative, reads the last shape's tint.
vec4 materialShapeTint(int index) {
    return geometryUniforms.uShapeTints[
        min(uint(index), uint(MAX_SHAPES - 1))
    ];
}

void main() {
    #if !MATERIAL_TINT_OUTPUT
    if (gl_FragCoord.y > uMaterialMapSize.y) {
        int shapeIndex = int(floor(gl_FragCoord.x));
        if (shapeIndex >= MAX_SHAPES) {
            fragColor = vec4(0.0);
            return;
        }
        fragColor = gl_FragCoord.y < uMaterialMapSize.y + 1.0
            ? geometryUniforms.uShapeTints[shapeIndex]
            : geometryUniforms.uShapeResponses[shapeIndex];
        return;
    }
    #endif
    // A low-resolution texel represents the center of one full-resolution
    // block. Linear sampling in the final pass turns these coarse samples into
    // the intentionally simple gradient used during transient unions.
    vec2 fragCoord = gl_FragCoord.xy * uMaterialRasterScale + uOffset;
    MaterialSceneSample scene = materialSceneSample(
        fragCoord,
        int(uNumShapes)
    );
    #if MATERIAL_TINT_OUTPUT
    float primaryWeight = materialPrimaryWeight(scene);
    vec4 primaryTint = materialShapeTint(int(scene.primary));
    vec4 secondaryTint = materialShapeTint(int(scene.secondary));
    float alpha = mix(secondaryTint.a, primaryTint.a, primaryWeight);
    vec3 premultiplied = mix(
        secondaryTint.rgb * secondaryTint.a,
        primaryTint.rgb * primaryTint.a,
        primaryWeight
    );
    fragColor = vec4(
        alpha > 0.0001 ? premultiplied / alpha : vec3(0.0),
        alpha
    );
    #else
    // b is the nearest shape's weight. a is the same weight expressed for the
    // lower-indexed shape of the pair: where the nearest shape swaps, both
    // texels store the same pair in opposite order, and only a interpolates
    // through the midpoint.
    float primaryWeight = materialPrimaryWeight(scene);
    fragColor = vec4(
        (scene.primary + 0.5) / float(MAX_SHAPES),
        (scene.secondary + 0.5) / float(MAX_SHAPES),
        primaryWeight,
        scene.primary <= scene.secondary ? primaryWeight : 1.0 - primaryWeight
    );
    #endif
}
