// Geometry pass for a body whose outline the caller has already fused (a
// morph local patch, see VENDORED): the same matte as geometry_fragment.glsl,
// but the signed distance, its gradient and the local half thickness come
// from a sampled field instead of the analytic shapes. The field is a
// float texture of nodes on a square grid, one RGBA texel per node:
// R = signed distance (negative inside), G and B = its gradient, A = the
// half minor extent of the shape the point belongs to, all in logical
// pixels; the shader interpolates the four nodes around a pixel
// bilinearly (the texture is sampled nearest, so no float filtering is
// needed), which keeps the distance and the normal continuous.

// The matte packs 12-bit integer codes; fp16 cannot represent them exactly.
precision highp float;

layout(std140) uniform FieldUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uFieldFrame;
    vec4 uFieldSize;
} fieldUniforms;

uniform sampler2D uField;

#define uOffset fieldUniforms.uOffset
#define uTextureSize fieldUniforms.uTextureSize
#define uOpticalProps fieldUniforms.uOpticalProps
#define uContourProps fieldUniforms.uContourProps
#define uFieldFrame fieldUniforms.uFieldFrame
#define uFieldSize fieldUniforms.uFieldSize

#include "displacement_encoding.glsl"

out vec4 fragColor;

// The field at p, in matte pixels: uFieldFrame.xy is node (0, 0), .z the
// node step, both in matte pixels.
vec4 fieldAt(vec2 p) {
    vec2 grid = clamp(
        (p - uFieldFrame.xy) / uFieldFrame.z,
        vec2(0.0),
        uFieldSize.xy - 1.0
    );
    vec2 cell = min(floor(grid), uFieldSize.xy - 2.0);
    vec2 f = grid - cell;
    vec2 texel = uFieldSize.zw;
    vec4 a = texture(uField, (cell + vec2(0.5, 0.5)) * texel);
    vec4 b = texture(uField, (cell + vec2(1.5, 0.5)) * texel);
    vec4 c = texture(uField, (cell + vec2(0.5, 1.5)) * texel);
    vec4 d = texture(uField, (cell + vec2(1.5, 1.5)) * texel);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy + uOffset;
    vec4 field = fieldAt(fragCoord);
    // uFieldFrame.w turns logical pixels into matte pixels.
    float sd = field.r * uFieldFrame.w;
    vec2 gradient = field.gb;
    float halfMinor = field.a * uFieldFrame.w;

    float uRefractionHeight = uOpticalProps.x;
    float uEdgeDistanceRange = uOpticalProps.z;
    float uRefractionAmount = uTextureSize.y;
    float uRefractionFitsShape = uTextureSize.x;
    float uContourExtent = uContourProps.x;

    float pixelSize = length(gradient);
    float fade = clamp(uOpticalProps.y, 0.0, 1.0) * max(pixelSize, 1e-4);
    float materialAlpha = 1.0 - smoothstep(-fade, fade, sd);
    float contourSupport = 1.0 - smoothstep(
        max(uContourExtent - fade, 0.0),
        uContourExtent,
        sd
    );
    float effectSupport = max(materialAlpha, contourSupport);
    if (effectSupport < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 surfaceNormal = pixelSize > 0.0001 ? gradient / pixelSize : vec2(0.0);

    float bevel;
    float amount;
    if (uRefractionFitsShape > 0.5) {
        bevel = min(uRefractionHeight, 0.5 * halfMinor);
        amount = min(uRefractionAmount, halfMinor);
    } else {
        float lensScale = min(
            1.0,
            halfMinor / max(uRefractionHeight, 0.001)
        );
        bevel = uRefractionHeight * lensScale;
        amount = uRefractionAmount * lensScale;
    }
    float bevelX = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacementMagnitude = bevel > 0.001
        ? -amount * (1.0 - sqrt(1.0 - bevelX * bevelX))
        : 0.0;

    fragColor = encodeDisplacementData(
        surfaceNormal,
        displacementMagnitude,
        max(uRefractionAmount, 0.001),
        -sd,
        4.0 * uEdgeDistanceRange,
        uContourExtent
    );
}
