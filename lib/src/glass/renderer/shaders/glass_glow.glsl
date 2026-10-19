// The touch glow of one lit surface, applied to the glass color under the
// control's content: UIKit's flex-interaction wash and spot, two color
// matrices over what lies behind them (lib/src/widgets/glass_glow.dart
// MorphGlassGlow). The wash adds to every channel; the spot multiplies the
// channels by 1 + gain exp(-r^2 / (2 sigma^2)), as a color dodge by the
// white level 1 - 1 / factor would, and clamps at white as the dodge does.
// The plus blend's own clamp before the dodge changes nothing, since the
// factor is at least 1. Both stay inside the lit surface's circular
// rounded box, antialiased over one pixel as its clip was.
//
// LiquidGlassGlow.shade (lib/src/glass/renderer/liquid_glass_glow.dart) is
// the CPU reference of this function; change both or neither.
//
// spot: center (matte device px), the falloff log2(e) / (2 sigma^2) per
// squared device px, gain.
// box: the lit surface's center and half extents (matte device px).
// shape: x the corner radius (device px), y the wash.
vec3 applyGlassGlow(vec3 color, vec2 p, vec4 spot, vec4 box, vec4 shape) {
    vec2 q = abs(p - box.xy) - box.zw + shape.x;
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - shape.x;
    float cover = clamp(0.5 - d, 0.0, 1.0);
    vec2 r = p - spot.xy;
    float factor = 1.0 + spot.w * exp2(-spot.z * dot(r, r));
    vec3 lit = min((color + vec3(shape.y)) * factor, vec3(1.0));
    return mix(color, lit, cover);
}
