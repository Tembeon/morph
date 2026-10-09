// Experimental coarse optical grid. The CPU owner still traces the contour.
// This ports liquid_field.dart's angular merge, not sdf.glsl's different law.
// RGBA32F nodes retain logical distance, rotated gradient and half thickness.
precision highp float;

layout(std140) uniform AnalyticFieldUniforms {
    vec4 uGrid; // columns, rows, logical step, box count
    vec4 uMerge; // spacing, minimum merge width, optical corner scale, unused
    vec4 uBoxes[8]; // center + half extent, then radius, per box
} field;

out vec4 fragColor;

vec3 boxSample(vec2 p, int i) {
    vec4 box = field.uBoxes[i * 2];
    float r = field.uBoxes[i * 2 + 1].x;
    vec2 local = p - box.xy;
    vec2 q = abs(local) - box.zw + r;
    vec2 outside = max(q, vec2(0.0));
    float len = length(outside);
    float d = len + min(max(q.x, q.y), 0.0) - r;
    vec2 normal = len > 0.0 ? outside / len
        : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    normal *= vec2(local.x < 0.0 ? -1.0 : 1.0,
                   local.y < 0.0 ? -1.0 : 1.0);
    return vec3(d, normal);
}

float distanceAt(vec2 p) {
    vec3 carried = boxSample(p, 0);
    float k = field.uMerge.x;
    for (int i = 1; i < 4; i++) {
        if (float(i) >= field.uGrid.w) break;
        vec3 next = boxSample(p, i);
        if (next.x - carried.x >= k) continue;
        if (carried.x - next.x >= k) {
            carried = next;
            continue;
        }
        float width = k * (1.0 - dot(carried.yz, next.yz)) * 0.5;
        if (width < field.uMerge.y) {
            if (next.x < carried.x) carried = next;
            continue;
        }
        float h = clamp(0.5 + 0.5 * (next.x - carried.x) / width, 0.0, 1.0);
        float d = mix(next.x, carried.x, h) - width * h * (1.0 - h);
        vec2 n = mix(next.yz, carried.yz, h);
        float len = length(n);
        carried = vec3(d, len > 1e-12 ? n / len : vec2(0.0));
    }
    return carried.x;
}

vec2 opticalTurn(vec2 p, int i) {
    vec4 box = field.uBoxes[i * 2];
    float exact = field.uBoxes[i * 2 + 1].x;
    float optical = min(exact * field.uMerge.z, min(box.z, box.w));
    vec2 local = p - box.xy;
    vec2 a = abs(local) - box.zw;
    vec2 o = a + optical;
    if (optical <= exact || o.x <= 0.0 || o.y <= 0.0) return vec2(1.0, 0.0);
    vec2 e = a + exact;
    vec2 en = e.x > 0.0 && e.y > 0.0 ? normalize(e)
        : (e.x > e.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    vec2 on = normalize(o);
    float mirror = (local.x < 0.0) != (local.y < 0.0) ? -1.0 : 1.0;
    return vec2(dot(en, on), (en.x * on.y - en.y * on.x) * mirror);
}

// Optical turn and thickness use the owner's plain polynomial fold, while
// distanceAt uses its angular fold. Keeping these separate is intentional.
vec3 opticalAt(vec2 p) {
    vec4 first = field.uBoxes[0];
    float d = boxSample(p, 0).x;
    float halfMinor = min(first.z, first.w);
    vec2 turn = opticalTurn(p, 0);
    float k = field.uMerge.x;
    for (int i = 1; i < 4; i++) {
        if (float(i) >= field.uGrid.w) break;
        vec4 box = field.uBoxes[i * 2];
        float di = boxSample(p, i).x;
        float w = clamp(0.5 + (di - d) / (2.0 * k), 0.0, 1.0);
        halfMinor = mix(min(box.z, box.w), halfMinor, w);
        turn = mix(opticalTurn(p, i), turn, w);
        float e = max(k - abs(d - di), 0.0);
        d = min(d, di) - e * e / (4.0 * k);
    }
    float len = length(turn);
    return vec3(halfMinor, len < 1e-9 ? vec2(1.0, 0.0) : turn / len);
}

void main() {
    vec2 node = floor(gl_FragCoord.xy);
    float step = field.uGrid.z;
    vec2 p = node * step;
    vec2 back = vec2(max(node.x - 1.0, 0.0), node.y) * step;
    vec2 ahead = vec2(min(node.x + 1.0, field.uGrid.x - 1.0), node.y) * step;
    vec2 up = vec2(node.x, max(node.y - 1.0, 0.0)) * step;
    vec2 down = vec2(node.x, min(node.y + 1.0, field.uGrid.y - 1.0)) * step;
    vec2 gradient = vec2((distanceAt(ahead) - distanceAt(back)) / (ahead.x - back.x),
                         (distanceAt(down) - distanceAt(up)) / (down.y - up.y));
    vec3 optical = opticalAt(p);
    vec2 turned = vec2(gradient.x * optical.y - gradient.y * optical.z,
                       gradient.x * optical.z + gradient.y * optical.y);
    fragColor = vec4(distanceAt(p), turned, optical.x);
}
