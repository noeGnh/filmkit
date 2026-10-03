## 0.3.0

* Photo export: `Filmkit.exportImage` (JPEG, HEIC, PNG, WebP… in, JPEG out) with the same `EditSpec` as videos (crop in displayed coordinates, `maxDimension`, LUT). The EXIF orientation is applied to the pixels; capture date, camera and exposure metadata are kept, the location only with `keepLocation`. Android decodes only the cropped region at the needed resolution.

## 0.2.0

* LUT filters: `CubeLut` (`.cube` parsing and writing, intensity, CPU reference), `EditSpec.lut` / `lutIntensity` applied by the export (Media3 `SingleColorLut`, Core Image `CIColorCubeWithColorSpace` in CoreMedia's BT.709 space), and the `LutFilter` widget for the live preview (shader), which renders the same colors.
* `Filmkit.getVideoFrame`: a frame as displayed, optionally scaled down.

## 0.1.0

* Headless video export: `Filmkit.exportVideo` with an `EditSpec` (trim, crop in displayed coordinates, max output size), progress, cancellation and several exports at once. Media3 Transformer on Android, AVFoundation on iOS. Output: MP4, H.264 + AAC, SDR.
* HDR sources are tone mapped to SDR. On Android, OpenGL tone mapping falls back to MediaCodec, then to a `hdrUnsupported` error.
* `Filmkit.getVideoInfo`: displayed size, duration, audio and HDR flags.

## 0.0.1

* Project scaffold.
