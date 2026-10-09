uniform MipUniforms {
  vec4 uMip; // source width, source height, tent enabled, unused
};
uniform sampler2D uInput;
in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  if (uMip.z < 0.5) {
    fragColor = texture(uInput, vTexCoord);
  } else {
  // Four bilinear taps realize separable [1,3,3,1]/8 at exact 2:1 sizes.
  vec2 d = vec2(0.75) / uMip.xy;
  fragColor = 0.25 * (
      texture(uInput, vTexCoord + vec2(-d.x, -d.y))
    + texture(uInput, vTexCoord + vec2( d.x, -d.y))
    + texture(uInput, vTexCoord + vec2(-d.x,  d.y))
    + texture(uInput, vTexCoord + vec2( d.x,  d.y)));
  }
}
