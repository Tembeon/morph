// Four tent4 levels collapsed into a separable 46-texel kernel.
// Paired linear taps use the exact convolution coefficients.
uniform WideUniforms {
  vec4 uWide; // input width/height, horizontal enabled, unused
};
uniform sampler2D uInput;
in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  vec2 axis = uWide.z > 0.5 ? vec2(1.0 / uWide.x, 0.0)
                             : vec2(0.0, 1.0 / uWide.y);
  vec4 result = vec4(0.0);
  result += 0.0009765625 * texture(uInput, vTexCoord + axis * (-21.75));
  result += 0.00390625 * texture(uInput, vTexCoord + axis * (-19.875));
  result += 0.0087890625 * texture(uInput, vTexCoord + axis * (-17.9166666667));
  result += 0.015625 * texture(uInput, vTexCoord + axis * (-15.9375));
  result += 0.0244140625 * texture(uInput, vTexCoord + axis * (-13.95));
  result += 0.03515625 * texture(uInput, vTexCoord + axis * (-11.9583333333));
  result += 0.0478515625 * texture(uInput, vTexCoord + axis * (-9.96428571429));
  result += 0.0625 * texture(uInput, vTexCoord + axis * (-7.96875));
  result += 0.076171875 * texture(uInput, vTexCoord + axis * (-5.98076923077));
  result += 0.0859375 * texture(uInput, vTexCoord + axis * (-3.98863636364));
  result += 0.091796875 * texture(uInput, vTexCoord + axis * (-1.99468085106));
  result += 0.09375 * texture(uInput, vTexCoord + axis * (0));
  result += 0.091796875 * texture(uInput, vTexCoord + axis * (1.99468085106));
  result += 0.0859375 * texture(uInput, vTexCoord + axis * (3.98863636364));
  result += 0.076171875 * texture(uInput, vTexCoord + axis * (5.98076923077));
  result += 0.0625 * texture(uInput, vTexCoord + axis * (7.96875));
  result += 0.0478515625 * texture(uInput, vTexCoord + axis * (9.96428571429));
  result += 0.03515625 * texture(uInput, vTexCoord + axis * (11.9583333333));
  result += 0.0244140625 * texture(uInput, vTexCoord + axis * (13.95));
  result += 0.015625 * texture(uInput, vTexCoord + axis * (15.9375));
  result += 0.0087890625 * texture(uInput, vTexCoord + axis * (17.9166666667));
  result += 0.00390625 * texture(uInput, vTexCoord + axis * (19.875));
  result += 0.0009765625 * texture(uInput, vTexCoord + axis * (21.75));
  fragColor = result;
}
