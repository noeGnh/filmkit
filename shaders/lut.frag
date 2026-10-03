#version 460 core

#include <flutter/runtime_effect.glsl>

// Applies a 3D LUT to the filtered widget (`ImageFilter.shader`). The LUT is a 2D strip
// (width N*N, height N): texel (r + b*N, g). The interpolation is done here (trilinear on 8
// texels fetched at their centers) so that the result doesn't depend on the GPU sampler
// filtering, and matches `CubeLut.apply`.

uniform vec2 uSize;        // set by the engine: size of the input texture
uniform float uLutSize;
uniform float uIntensity;
uniform sampler2D uInput;  // set by the engine: the filtered widget
uniform sampler2D uLut;

out vec4 fragColor;

vec3 lutAt(float r, float g, float b) {
  vec2 uv = vec2(r + b * uLutSize + 0.5, g + 0.5) / vec2(uLutSize * uLutSize, uLutSize);
  return texture(uLut, uv).rgb;
}

void main() {
  // No y flip on OpenGL ES: since Flutter 3.46 its offscreen textures are stored top-down,
  // like Metal and Vulkan (flutter/flutter#186556), despite the ImageFilter.shader docs.
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 color = texture(uInput, uv);
  // Premultiplied input: the LUT applies to the straight color.
  vec3 rgb = color.a > 0.0 ? color.rgb / color.a : vec3(0.0);

  vec3 p = clamp(rgb, 0.0, 1.0) * (uLutSize - 1.0);
  vec3 i0 = floor(p);
  vec3 i1 = min(i0 + 1.0, uLutSize - 1.0);
  vec3 f = p - i0;

  vec3 c00 = mix(lutAt(i0.r, i0.g, i0.b), lutAt(i1.r, i0.g, i0.b), f.r);
  vec3 c10 = mix(lutAt(i0.r, i1.g, i0.b), lutAt(i1.r, i1.g, i0.b), f.r);
  vec3 c01 = mix(lutAt(i0.r, i0.g, i1.b), lutAt(i1.r, i0.g, i1.b), f.r);
  vec3 c11 = mix(lutAt(i0.r, i1.g, i1.b), lutAt(i1.r, i1.g, i1.b), f.r);
  vec3 graded = mix(mix(c00, c10, f.g), mix(c01, c11, f.g), f.b);

  fragColor = vec4(mix(rgb, graded, uIntensity) * color.a, color.a);
}
