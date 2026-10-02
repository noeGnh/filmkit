#version 460 core

#include <flutter/runtime_effect.glsl>

// Applies a 3D LUT stored as a 2D strip (width N*N, height N): texel (r + b*N, g).
// The interpolation is done here (trilinear on 8 texels fetched at their centers) so that
// the result does not depend on the sampler filtering of the GPU.

uniform vec2 uSize;
uniform float uLutSize;
uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

vec3 lutAt(float r, float g, float b) {
  vec2 uv = vec2(r + b * uLutSize + 0.5, g + 0.5) / vec2(uLutSize * uLutSize, uLutSize);
  return texture(uLut, uv).rgb;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 color = texture(uImage, uv);

  vec3 p = clamp(color.rgb, 0.0, 1.0) * (uLutSize - 1.0);
  vec3 i0 = floor(p);
  vec3 i1 = min(i0 + 1.0, uLutSize - 1.0);
  vec3 f = p - i0;

  vec3 c00 = mix(lutAt(i0.r, i0.g, i0.b), lutAt(i1.r, i0.g, i0.b), f.r);
  vec3 c10 = mix(lutAt(i0.r, i1.g, i0.b), lutAt(i1.r, i1.g, i0.b), f.r);
  vec3 c01 = mix(lutAt(i0.r, i0.g, i1.b), lutAt(i1.r, i0.g, i1.b), f.r);
  vec3 c11 = mix(lutAt(i0.r, i1.g, i1.b), lutAt(i1.r, i1.g, i1.b), f.r);
  vec3 c0 = mix(c00, c10, f.g);
  vec3 c1 = mix(c01, c11, f.g);

  fragColor = vec4(mix(c0, c1, f.b), 1.0) * color.a;
}
