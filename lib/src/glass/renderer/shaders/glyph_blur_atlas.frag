#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uOrigin;
uniform vec2 uAtlasSize;
uniform vec4 uRowA;
uniform vec4 uRowB;
uniform vec2 uRatios;
uniform float uMix;
uniform float uOpacity;
uniform sampler2D uAtlas;

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy - uOrigin;
    vec2 pa = clamp(p * uRatios.x + vec2(uRowA.y), vec2(0.5), uRowA.zw - vec2(0.5));
    vec2 pb = clamp(p * uRatios.y + vec2(uRowB.y), vec2(0.5), uRowB.zw - vec2(0.5));
    vec4 a = texture(uAtlas, (pa + vec2(0.0, uRowA.x)) / uAtlasSize);
    vec4 b = texture(uAtlas, (pb + vec2(0.0, uRowB.x)) / uAtlasSize);
    fragColor = mix(a, b, uMix) * uOpacity;
}
