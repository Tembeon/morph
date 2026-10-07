in vec2 position;
in vec2 texCoord;
out vec2 vTexCoord;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  vTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);
}
