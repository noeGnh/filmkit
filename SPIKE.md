# Spike: LUT rendering parity (Android)

Question: does a 3D LUT rendered by the Flutter shader (live preview) match the native export (Media3 Transformer `SingleColorLut`)?

## Setup

- 512×512 test image of smooth gradients (red along x, green along y, blue as a slow wave).
- 33³ LUT quantized to 8 bits: S-curve contrast, warm tint, +30 % saturation.
- CPU reference: trilinear interpolation in Dart, in sRGB-encoded values.
- Flutter shader (`shaders/lut.frag`): LUT as a 2D strip texture, trilinear interpolation done in the shader (8 nearest texel fetches), so it does not depend on GPU sampler filtering.
- Media3 1.11.1: the image is exported to a 200 ms H.264 video with `SingleColorLut.createFromCube`, then the first frame is read back with `MediaMetadataRetriever`.
- Differences per channel in 0..255, 8 px border ignored.

## Results (Android 16 emulator, Flutter 3.47.2, Impeller)

| Comparison | mean | p95 | p99 | max |
|---|---|---|---|---|
| A. shader (identity LUT) vs source | 0.00 | 0 | 0 | 0 |
| B. shader (look) vs CPU reference | 0.00 | 0 | 0 | 0 |
| C. Media3 (no LUT) vs source — codec baseline | 1.24 | 3 | 4 | 8 |
| D. Media3 (look) vs CPU reference | 1.17 | 3 | 5 | 11 |
| E. **Media3 (look) vs shader (look)** | 1.17 | 3 | 5 | 11 |
| F. shader (look) vs source — size of the effect | 22.08 | 50 | 60 | 70 |

## Conclusions

- The shader is bit-exact with the CPU reference (A, B): the preview renders the LUT exactly.
- Media3 applies the LUT in the same encoded (non-linear) domain as the shader: otherwise E would be in the tens.
- Preview vs export (E) is at the level of the video codec's own error (C): the LUT adds about +1 at p99 and +3 at max, consistent with the S-curve amplifying codec noise. That is ~5 % of the effect size (F), not visible.
- The "one LUT for preview and export" architecture holds on Android.

## iOS results (iPhone 18 Pro simulator, iOS 27.0, Impeller Metal)

Same image and LUT; Core Image applies the 8-bit cube (`ios/.../FilmkitPlugin.swift`, `applyLutImage`) in three modes.

| Comparison | mean | p95 | p99 | max |
|---|---|---|---|---|
| A. shader (identity LUT) vs source | 0.00 | 0 | 0 | 0 |
| B. shader (look) vs CPU reference | 0.00 | 0 | 0 | 1 |
| `CIColorCube`, default context (linear working space) vs shader | 16.81 | 45 | 71 | 110 |
| **`CIColorCubeWithColorSpace` (sRGB) vs shader** | 0.02 | 0 | 1 | 1 |
| `CIColorCube`, color management disabled vs shader | 0.02 | 0 | 1 | 1 |

- The shader is exact on Metal too.
- Core Image's default applies the cube to linear values: the result is visibly wrong (banding, darker shadows). The LUT must be applied with `CIColorCubeWithColorSpace` in sRGB (or with color management disabled): then it matches the preview to 1/255.
- For video (AVFoundation), the cube color space has to match the video frames' encoding (BT.709): to check in the AVFoundation spike.

## Not covered

- Real devices: the emulator uses a software H.264 encoder and its own GPU path; hardware encoders and 10-bit/HDR sources may differ.
- The test image covers a 2D slice of the color cube, with a single LUT.
