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
  fragColor = texture(sourceTexture, uv);
}
