import 'dart:ui' as ui;

/// Writes a fragment shader's float uniforms one after another.
class ShaderUniforms {
  ShaderUniforms._(this._shader, this._index);

  final ui.FragmentShader _shader;
  int _index;

  /// Writes [value] at the next index.
  void setFloat(double value) => _shader.setFloat(_index++, value);

  /// Writes [values] at the next indices.
  void setFloats(List<double> values) => values.forEach(setFloat);

  /// Writes the width and height of [size].
  void setSize(ui.Size size) {
    setFloat(size.width);
    setFloat(size.height);
  }

  /// Writes the two coordinates of [offset].
  void setOffset(ui.Offset offset) {
    setFloat(offset.dx);
    setFloat(offset.dy);
  }

  /// Writes [color] as straight red, green, blue and alpha.
  ///
  /// The channels are quantized to 8 bits, as the shaders were tuned with.
  void setColor(ui.Color color) {
    final argb = color.toARGB32();
    setFloat(((argb >> 16) & 0xff) / 255);
    setFloat(((argb >> 8) & 0xff) / 255);
    setFloat((argb & 0xff) / 255);
    setFloat(color.a);
  }
}

/// Sequential uniform writing for fragment shaders.
extension ShaderUniformsWriter on ui.FragmentShader {
  /// Hands [write] a writer that starts at [initialIndex] and returns the
  /// index past the last uniform written.
  int setFloatUniforms(
    void Function(ShaderUniforms uniforms) write, {
    int initialIndex = 0,
  }) {
    final uniforms = ShaderUniforms._(this, initialIndex);
    write(uniforms);
    return uniforms._index;
  }
}
