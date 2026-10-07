uniform BlurUniforms {
  vec4 uvRect;
  vec2 halfOffset;
} uniforms;
uniform sampler2D sourceTexture;
in vec2 vTexCoord;
out vec4 fragColor;
void main() {
  vec2 uv = uniforms.uvRect.xy + vTexCoord * uniforms.uvRect.zw;
  vec2 h = uniforms.halfOffset;
  vec4 sum = texture(sourceTexture, uv) * 4.0;
  sum += texture(sourceTexture, uv - h);
  sum += texture(sourceTexture, uv + vec2(h.x, -h.y));
  sum += texture(sourceTexture, uv + vec2(-h.x, h.y));
  sum += texture(sourceTexture, uv + h);
  fragColor = sum * 0.125;
}
