/**
 * Liquid Glass — WebGL2 renderer core (framework-agnostic).
 *
 * Runs the ESSL 300 shader derived from macOS 26/27's QuartzCore. See
 * ../../../portable/README.md for how the shader was obtained and verified.
 *
 * THE BACKDROP IS THE WHOLE PROBLEM ON WEB.
 * The shader needs the composited pixels behind the element, as a mipmapped
 * texture, and it displaces the sample position per fragment. CSS
 * `backdrop-filter` cannot do that — there is no hook to move where a fragment
 * samples from. So you must supply the backdrop yourself; see BackdropSource.
 */

import { FRAGMENT_SRC, VERTEX_SRC } from './shader';
import { GlassParams, packParams, defaultParams, PARAM_FLOATS } from './params';

export type BackdropSource =
  | { kind: 'image'; image: TexImageSource }
  | { kind: 'canvas'; canvas: HTMLCanvasElement | OffscreenCanvas }
  | { kind: 'video'; video: HTMLVideoElement };

export interface RendererOptions {
  /** Device pixel ratio to render at. Defaults to window.devicePixelRatio. */
  pixelRatio?: number;
  /** Fail loudly instead of silently degrading when WebGL2 is unavailable. */
  strict?: boolean;
}

export class LiquidGlassRenderer {
  readonly canvas: HTMLCanvasElement;
  private gl: WebGL2RenderingContext;
  private program: WebGLProgram;
  private vao: WebGLVertexArrayObject;
  private ubo: WebGLBuffer;
  private tex: WebGLTexture;
  private uboData = new Float32Array(PARAM_FLOATS);
  private pixelRatio: number;
  private disposed = false;

  constructor(canvas: HTMLCanvasElement, opts: RendererOptions = {}) {
    this.canvas = canvas;
    this.pixelRatio = opts.pixelRatio ?? (globalThis.devicePixelRatio || 1);

    const gl = canvas.getContext('webgl2', {
      alpha: true,
      premultipliedAlpha: false,
      antialias: false, // the shader does its own 1px analytic AA
      depth: false,
      stencil: false,
    });
    if (!gl) {
      throw new Error(
        'LiquidGlass: WebGL2 is required. There is no WebGL1 fallback — the ' +
          'shader needs textureLod() for the mip-based blur, which WebGL1 ' +
          'cannot express.'
      );
    }
    this.gl = gl;

    this.program = this.link(VERTEX_SRC, FRAGMENT_SRC);
    this.vao = this.makeQuad();
    this.ubo = this.makeUBO();
    this.tex = this.makeTexture();
  }

  private compile(type: number, src: string): WebGLShader {
    const gl = this.gl;
    const sh = gl.createShader(type)!;
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(sh);
      gl.deleteShader(sh);
      throw new Error(`LiquidGlass: shader compile failed\n${log}`);
    }
    return sh;
  }

  private link(vsSrc: string, fsSrc: string): WebGLProgram {
    const gl = this.gl;
    const vs = this.compile(gl.VERTEX_SHADER, vsSrc);
    const fs = this.compile(gl.FRAGMENT_SHADER, fsSrc);
    const p = gl.createProgram()!;
    gl.attachShader(p, vs);
    gl.attachShader(p, fs);
    gl.linkProgram(p);
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      throw new Error(`LiquidGlass: link failed\n${gl.getProgramInfoLog(p)}`);
    }
    const idx = gl.getUniformBlockIndex(p, 'GlassParams');
    if (idx !== gl.INVALID_INDEX) gl.uniformBlockBinding(p, idx, 0);
    return p;
  }

  private makeQuad(): WebGLVertexArrayObject {
    const gl = this.gl;
    const vao = gl.createVertexArray()!;
    gl.bindVertexArray(vao);
    const buf = gl.createBuffer()!;
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
      gl.STATIC_DRAW
    );
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);
    return vao;
  }

  private makeUBO(): WebGLBuffer {
    const gl = this.gl;
    const ubo = gl.createBuffer()!;
    gl.bindBuffer(gl.UNIFORM_BUFFER, ubo);
    gl.bufferData(gl.UNIFORM_BUFFER, this.uboData.byteLength, gl.DYNAMIC_DRAW);
    gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, ubo);
    return ubo;
  }

  private makeTexture(): WebGLTexture {
    const gl = this.gl;
    const t = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, t);
    // LINEAR_MIPMAP_LINEAR is mandatory: the blur IS mip selection. With
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }

  /** Upload a new backdrop and regenerate its mip chain. */
  setBackdrop(src: BackdropSource): void {
    if (this.disposed) return;
    const gl = this.gl;
    const source =
      src.kind === 'image' ? src.image : src.kind === 'canvas' ? src.canvas : src.video;
    gl.bindTexture(gl.TEXTURE_2D, this.tex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(
      gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE,
      source as TexImageSource
    );
    gl.generateMipmap(gl.TEXTURE_2D);
  }

  /** Resize the drawing buffer to the element's CSS size × pixelRatio. */
  resize(cssWidth: number, cssHeight: number): void {
    const w = Math.max(1, Math.round(cssWidth * this.pixelRatio));
    const h = Math.max(1, Math.round(cssHeight * this.pixelRatio));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
  }

  render(params: Partial<GlassParams> = {}): void {
    if (this.disposed) return;
    const gl = this.gl;
    const p = { ...defaultParams(), ...params };

    packParams(p, this.uboData);
    gl.bindBuffer(gl.UNIFORM_BUFFER, this.ubo);
    gl.bufferSubData(gl.UNIFORM_BUFFER, 0, this.uboData);

    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.enable(gl.BLEND);
    gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

    gl.useProgram(this.program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.tex);
    const loc = gl.getUniformLocation(this.program, 'uBackdrop');
    if (loc) gl.uniform1i(loc, 0);

    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.bindVertexArray(null);
  }

  dispose(): void {
    if (this.disposed) return;
    const gl = this.gl;
    gl.deleteProgram(this.program);
    gl.deleteVertexArray(this.vao);
    gl.deleteBuffer(this.ubo);
    gl.deleteTexture(this.tex);
    this.disposed = true;
  }
}

/** True if this browser can run the effect at all. */
export function isSupported(): boolean {
  try {
    const c = document.createElement('canvas');
    return !!c.getContext('webgl2');
  } catch {
    return false;
  }
}
