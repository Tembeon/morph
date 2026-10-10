// The blurred rounded superellipse math (blurAlpha and the rounded
// rectangle helpers below it) is adapted from Flutter's Impeller shaders
// (impeller/entity/shaders/rsuperellipse_blur.frag and
// impeller/compiler/shader_lib/impeller/rrect.glsl, Flutter 3.49.0-0.2.pre):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.
//
// One glass shadow in one draw (MorphGlassShadowShader in
// glass_shadow_shader.dart): the Gaussian-blurred rounded superellipse
// Impeller draws for drawRSuperellipse under MaskFilter.blur, times the
// coverage of the region outside the glass shape, so the shadow needs
// neither a clip path nor a mask filter. The blur's parameters are
// Impeller's own pass context (SolidRRectLikeBlurContents and
// SolidRSuperellipseBlurContents), computed on the CPU; the glass shape is
// gpu/sdf.glsl's exact rounded superellipse, covered over one device pixel.
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// The shadow color, premultiplied.
uniform vec4 uColor;
// The blurred shape's center, then Impeller's adjusted half extents less
// r1 (the corner of its power-distance rounded rectangle).
uniform vec4 uCenterAdjust;
// r1, the power-distance exponent, its inverse, and 1 / sigma.
uniform vec4 uRRect;
// The shortest side, the erf scale, then the half extents of the blurred
// shape.
uniform vec4 uFadeHalfAxes;
// Per octant (top, right): split angle, retraction at the split,
// superellipse degree n and -1 / n.
uniform vec4 uInfoTop;
uniform vec4 uInfoRight;
// Per octant: the cubic of the retraction past the split.
uniform vec4 uPolyTop;
uniform vec4 uPolyRight;
// The depth over which the retraction fades out, 0, 0, 0.
uniform vec4 uDepth;
// The glass shape's center and half extents.
uniform vec4 uGlass;
// The glass shape's corner radius, the device pixels per local unit, 0, 0.
uniform vec4 uGlassCorner;

// The glass shape's rounded superellipse parameters (see sdf.glsl), then
// the uniforms sdf.glsl's scene helpers read, which this shader never
// calls; declared last so they leave the layout above alone.
#define MAX_SHAPES 1
uniform vec4 uRseData[MAX_SHAPES * 3];
uniform vec4 uShapeData[MAX_SHAPES * 3];
uniform vec4 uShapeBounds[MAX_SHAPES];

#include "gpu/sdf.glsl"

out vec4 fragColor;

const float kTwoOverSqrtPi = 2.0 / sqrt(3.1415926);
const float kPiOverFour = 3.1415926 / 4.0;

float computeErf7(float x) {
    x *= kTwoOverSqrtPi;
    float xx = x * x;
    x = x + (0.24295 + (0.03395 + 0.0104 * xx) * xx) * (x * xx);
    return x / sqrt(1.0 + x * x);
}

// The length formula with an exponent other than 2.
float powerDistance(vec2 p, float exponent, float exponentInv) {
    float xp = pow(p.x, exponent);
    float yp = pow(p.y, exponent);
    return pow(xp + yp, exponentInv);
}

float computeRRectDistance(vec2 position, vec2 adjust) {
    vec2 adjusted = position - adjust;
    float dPos = powerDistance(max(adjusted, 0.0), uRRect.y, uRRect.z);
    float dNeg = min(max(adjusted.x, adjusted.y), 0.0);
    return dPos + dNeg - uRRect.x;
}

float computeRRectFade(float d) {
    float sInv = uRRect.w;
    return uFadeHalfAxes.y *
        (computeErf7(sInv * (uFadeHalfAxes.x + d)) - computeErf7(sInv * d));
}

// The blurred shape's alpha at p: Impeller's rounded rectangle blur with
// the rounded superellipse's retraction.
float blurAlpha(vec2 p) {
    vec2 centered = abs(p - uCenterAdjust.xy);
    float d = computeRRectDistance(centered, uCenterAdjust.zw);

    vec2 halfAxes = uFadeHalfAxes.zw;
    float retractionDepth = uDepth.x;
    float octantOffset = halfAxes.y - halfAxes.x;

    bool useTop = (centered.y - octantOffset) > centered.x;
    vec4 angularInfo = useTop ? uInfoTop : uInfoRight;
    // The denominators are only zero at the very center, where Impeller
    // divides 0 by 0; any angle reads the same there.
    float theta = atan(useTop
        ? centered.x / max(centered.y - octantOffset, 1e-6)
        : centered.y / max(centered.x + octantOffset, 1e-6));

    float splitRadian = angularInfo.x;
    float splitGap = angularInfo.y;
    float n = angularInfo.z;
    float nInvNeg = angularInfo.w;

    float baseRetraction;
    if (theta < splitRadian) {
        float a = useTop ? halfAxes.x : halfAxes.y;
        baseRetraction = (1.0 - pow(1.0 + pow(tan(theta), n), nInvNeg)) * a;
    } else {
        float t = (theta - splitRadian) / (kPiOverFour - splitRadian);
        float tt = t * t;
        float ttt = tt * t;
        float retProg = dot(
            vec4(ttt, tt, t, 1.0),
            useTop ? uPolyTop : uPolyRight
        );
        baseRetraction = retProg * retProg * splitGap;
    }
    float depthProg = smoothstep(-retractionDepth, 0.0, -abs(d));
    d += baseRetraction * depthProg;

    return computeRRectFade(d);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    // Outside the glass shape by its signed distance, over one device pixel.
    float outside = sdfSquircle(
        p - uGlass.xy,
        uGlass.zw,
        uGlassCorner.x,
        uRseData[0],
        uRseData[1],
        uRseData[2]
    );
    float coverage = clamp(0.5 + outside * uGlassCorner.y, 0.0, 1.0);
    vec4 color = vec4(0.0);
    if (coverage > 0.0) {
        color = uColor * (blurAlpha(p) * coverage);
    }
    fragColor = color;
}
