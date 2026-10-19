// The optics of a glass container's fused body, shared by the liquid tier's
// analytic final pass (analytic_geometry.glsl) and the geometry pass that
// encodes the same body into a matte (gpu/geometry_fused_fragment.glsl), so
// a resting matte holds what a moving frame shades: the half thickness and
// the optical turn of the corners, folded by the plain polynomial smooth
// minimum over the full spacing, and the optical gradient, the angular
// fold's central difference over one device pixel turned like the field's.
//
// The includer includes fused_law.glsl first, with uFusedBoxes, and
// defines kOpticalCornerRadiusScale (gpu/sdf.glsl).

// The signed distance of fused box [i] at p and its unit normal.
vec3 fusedBox(vec2 p, int i) {
    return fusedBoxAt(p, uFusedBoxes[i * 2], uFusedBoxes[i * 2 + 1].x);
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
// plain polynomial fold over the full spacing [k].
vec3 fusedOptics(vec2 p, int count, float k) {
    vec4 first = uFusedBoxes[0];
    float d = fusedBox(p, 0).x;
    float halfMinor = min(first.z, first.w);
    vec2 turn = fusedTurn(p, 0);
    for (int i = 1; i < FUSED_MAX_BOXES; i++) {
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

// The angular fold's central difference over one device pixel at p
// (spacing [k], narrowest blending width [minWidth]).
vec2 fusedGradient(vec2 p, int count, float k, float minWidth) {
    return vec2(
        fusedFold(p + vec2(0.5, 0.0), count, k, minWidth) -
            fusedFold(p - vec2(0.5, 0.0), count, k, minWidth),
        fusedFold(p + vec2(0.0, 0.5), count, k, minWidth) -
            fusedFold(p - vec2(0.0, 0.5), count, k, minWidth)
    );
}

// [gradient] rotated by [turn] (cos, sin): the optical gradient.
vec2 fusedTurned(vec2 gradient, vec2 turn) {
    return vec2(
        gradient.x * turn.x - gradient.y * turn.y,
        gradient.x * turn.y + gradient.y * turn.x
    );
}
