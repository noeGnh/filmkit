# Spike: video export with Media3 (Android)

Question: can Media3 Transformer apply an edit described in displayed coordinates (trim, crop, resize, HDR → SDR) correctly on the kinds of videos phones produce?

## Setup

- `FilmkitPlugin.exportVideo`: `ClippingConfiguration` (trim), `Crop` (normalized displayed rect converted to NDC), `Presentation.createForWidthAndHeight` (longest side ≤ `maxDimension`, even sizes), H.264 + AAC output, `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL`, audio kept when the source has an audio track.
- Test videos (`spike/gen.sh`, `spike/vfr.sh`): in displayed orientation, four solid quadrants (red TL, green TR, blue BL, white BR) and a central band whose gray level encodes time. Portrait videos are stored like phones do: landscape frames + rotation tag.
- Same edit for every video: trim 1.0–4.0 s, crop [0.25, 0, 1, 0.75], max 1080 px.
- Outputs checked on the host (`spike/verify.py`): ffprobe for size / duration / rotation / audio, and the frame at 0.5 s decoded with the rotation applied, colors sampled at 6 points (including both sides of the quadrant edge, which moves with the crop) and at the time band.

## Results (Android 16 emulator, Media3 1.11.1, software encoder `c2.android.avc.encoder`)

| Source | Output | Duration | Audio | Crop | Trim | Export time |
|---|---|---|---|---|---|---|
| H.264 640×360 30 fps | 480×270 | 3.02 s | kept | ✓ | ✓ | 1.7 s |
| HEVC 640×360 | 480×270 | 3.02 s | kept | ✓ | ✓ | 1.0 s |
| H.264, rotation 90 (displayed 360×640) | 270×480, rotation tag kept | 3.02 s | kept | ✓ | ✓ | 0.8 s |
| H.264, rotation 270 | 270×480, rotation tag kept | 3.02 s | kept | ✓ | ✓ | 0.8 s |
| H.264 VFR (33/67/100 ms frames), no audio | 480×270, VFR kept | 3.03 s | none | ✓ | ✓ | 0.5 s |
| H.264 3840×2160 60 fps | 1080×608 | 3.02 s | kept | ✓ | ✓ | 19 s |
| HEVC Main10 HDR10 (PQ) | — | — | — | — | — | **fails** |

Trim: the time band is within 1–3 frames of the expected value.

## Conclusions

- Crop coordinates can be expressed in displayed orientation: Media3 applies the effects after the rotation and keeps the rotation tag in the output.
- Trim, resize, VFR sources, sources without audio and HEVC input work with a single code path.
- HDR10 fails on the emulator with a `VideoFrameProcessingException` (`EGL_BAD_ATTRIBUTE`, `mapper.ranchu … UNSUPPORTED`): the emulator's GL / gralloc lacks 10-bit support. To test on a real device, and the API needs a fallback (`HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC`, or a clear error) for devices without OpenGL tone mapping.
- 4K60 takes ~6× real time on the emulator's software encoder; to measure on real hardware encoders.

## iOS results (iPhone 18 Pro simulator, iOS 27.0, AVFoundation)

`ios/.../FilmkitPlugin.swift`, `exportVideo`: same arguments as on Android. `AVMutableVideoComposition` with a Core Image handler (crop in displayed coordinates, origin bottom-left, then scale), `renderSize` = output size, BT.709 color properties, `AVAssetExportSession` (`AVAssetExportPresetHighestQuality`) with `timeRange`. Fallbacks for iOS 15 (`AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`, `export()`).

| Source | Output | Duration | Audio | Crop | Trim | Export time |
|---|---|---|---|---|---|---|
| H.264 640×360 | H.264 480×270 | 3.00 s | kept | ✓ | ✓ | 0.7 s |
| HEVC 640×360 | H.264 480×270 | 3.00 s | kept | ✓ | ✓ | 0.2 s |
| H.264, rotation 90 | 270×480, pixels rotated (rotation 0) | 3.00 s | kept | ✓ | ✓ | 0.2 s |
| H.264, rotation 270 | 270×480, pixels rotated (rotation 0) | 3.00 s | kept | ✓ | ✓ | 0.2 s |
| H.264 VFR, no audio | 480×270, VFR kept | 3.00 s | none | ✓ | ✓ | 0.1 s |
| H.264 3840×2160 60 fps | 1080×608 | 3.00 s | kept | ✓ | ✓ | 1.1 s |
| HEVC Main10 HDR10 (PQ) | H.264 480×270, BT.709 SDR | 3.00 s | kept | ✓ | (see below) | 0.7 s |

- The Core Image handler receives frames in displayed orientation: the same displayed crop rect works on rotated videos. Unlike Media3, the output has its pixels rotated instead of keeping the rotation tag; both display correctly.
- HDR10 is tone mapped to SDR BT.709. The time band check does not apply to it: the test "HDR" source holds SDR code values tagged PQ, so tone mapping legitimately changes its gray levels. A real HDR clip is needed to judge the tone mapping quality.
- The simulator encodes through the Mac's VideoToolbox: timings are not representative of an iPhone.
