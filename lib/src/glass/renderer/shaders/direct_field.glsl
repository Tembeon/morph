// Read the same RGBA32F nodes as the geometry field pass, without its target.
uniform vec3 uDirectOptics;
uniform vec4 uDirectFieldFrame;
uniform vec4 uDirectFieldSize;

vec4 directFieldData(vec2 matteCoord) {
    vec2 p = floor(matteCoord - uGeometryOffset) + 0.5 + uGeometryOffset;
    vec2 grid = clamp((p - uDirectFieldFrame.xy) / uDirectFieldFrame.z,
        vec2(0.0), uDirectFieldSize.xy - 1.0);
    vec2 cell = min(floor(grid), uDirectFieldSize.xy - 2.0);
    vec2 f = grid - cell;
    vec2 texel = uDirectFieldSize.zw;
    vec4 a = texture(uGeometryTexture, (cell + vec2(0.5, 0.5)) * texel);
    vec4 b = texture(uGeometryTexture, (cell + vec2(1.5, 0.5)) * texel);
    vec4 c = texture(uGeometryTexture, (cell + vec2(0.5, 1.5)) * texel);
    vec4 d = texture(uGeometryTexture, (cell + vec2(1.5, 1.5)) * texel);
    vec4 field = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    float sd = field.r * uDirectFieldFrame.w;
    float extent = contourExtent();
    float fade = 0.5 * max(length(field.gb), 1e-4);
    float materialAlpha = 1.0 - smoothstep(-fade, fade, sd);
    float contourSupport = 1.0 - smoothstep(max(extent - fade, 0.0), extent, sd);
    if (max(materialAlpha, contourSupport) < 0.01) return vec4(0.0);
    float normalLength = length(field.gb);
    vec2 normal = normalLength > 0.0001
        ? field.gb / normalLength : vec2(0.0);
    float bevel;
    float amount;
    if (uDirectOptics.z > 0.5) {
        bevel = min(uDirectOptics.x, 0.5 * field.a * uDirectFieldFrame.w);
        amount = min(uDirectOptics.y, field.a * uDirectFieldFrame.w);
    } else {
        float lensScale = min(1.0, field.a * uDirectFieldFrame.w / max(uDirectOptics.x, 0.001));
        bevel = uDirectOptics.x * lensScale;
        amount = uDirectOptics.y * lensScale;
    }
    float x = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacement = bevel > 0.001
        ? -amount * (1.0 - sqrt(1.0 - x * x)) : 0.0;
    vec4 data = encodeDisplacementData(
        normal, displacement, max(uDirectOptics.y, 0.001), -sd,
        4.0 * uThickness, extent
    );
    return floor(data * 255.0 + 0.5) / 255.0;
}
