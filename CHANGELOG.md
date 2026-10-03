## 0.1.0

* Headless video export: `Filmkit.exportVideo` with an `EditSpec` (trim, crop in displayed coordinates, max output size), progress, cancellation and several exports at once. Media3 Transformer on Android, AVFoundation on iOS. Output: MP4, H.264 + AAC, SDR.
* HDR sources are tone mapped to SDR. On Android, OpenGL tone mapping falls back to MediaCodec, then to a `hdrUnsupported` error.
* `Filmkit.getVideoInfo`: displayed size, duration, audio and HDR flags.

## 0.0.1

* Project scaffold.
