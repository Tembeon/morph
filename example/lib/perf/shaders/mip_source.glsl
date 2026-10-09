uniform SourceUniforms {
  vec4 uSource; // width, height, translation in source pixels, unused
};
in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  vec2 p = vTexCoord * uSource.xy + vec2(uSource.z, 0.0);
  vec2 cell = floor(p / 40.0);
  float tiles = mod(cell.x + cell.y, 2.0);
  float stripes = step(0.5, fract(p.x / 7.0));
  vec3 color = mix(vec3(0.08, 0.16, 0.34), vec3(0.85, 0.46, 0.12), tiles);
  color = mix(color, vec3(stripes), 0.3 * step(uSource.y * 0.5, p.y));
  // Distinct corners expose an accidental vertical flip between mip levels.
  if (p.x < uSource.x * 0.2 && p.y < uSource.y * 0.2) {
    color = vec3(0.9, 0.1, 0.1);
  } else if (p.x > uSource.x * 0.8 && p.y < uSource.y * 0.2) {
    color = vec3(0.1, 0.9, 0.1);
  } else if (p.x < uSource.x * 0.2 && p.y > uSource.y * 0.8) {
    color = vec3(0.1, 0.1, 0.9);
  } else if (p.x > uSource.x * 0.8 && p.y > uSource.y * 0.8) {
    color = vec3(0.9, 0.9, 0.1);
  }
  fragColor = vec4(color, 1.0);
}
