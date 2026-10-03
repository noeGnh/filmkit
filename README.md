# filmkit

Photo and video editing for Flutter: crop, trim, LUT filters and adjustments, exported natively (Media3 Transformer on Android, AVFoundation on iOS), with an Instagram-style editor screen.

> **Status**: 0.2, headless video export (trim, crop, resize, LUT filters) and filter preview. Photos and the editor screen come next.

## Video export

```dart
final export = Filmkit.exportVideo(
  input: '/path/to/input.mp4',
  output: '/path/to/output.mp4',
  edit: const EditSpec(
    trimStart: Duration(seconds: 1),
    trimEnd: Duration(seconds: 4),
    crop: Rect.fromLTRB(0, 0.2, 1, 0.8), // normalized, as the video is displayed
    maxDimension: 1080,                  // longest output side, never upscaled
  ),
);
export.progress.listen((p) => print('${(p * 100).round()} %'));
try {
  final result = await export.result; // path, width, height
} on FilmkitException catch (e) {
  // e.code: invalidInput, cancelled, hdrUnsupported, exportFailed
}
// export.cancel() stops it and deletes the partial file.
```

## Filters

Filters are 3D LUTs in `.cube` files (Resolve, Photoshop, Lightroom…), applied with the same result by the preview and the export.

```dart
final look = await CubeLut.fromFile('/path/to/look.cube');

// Live preview on any widget: an image, a video player…
LutFilter(lut: look, intensity: 0.8, child: VideoPlayer(controller));

// Export
Filmkit.exportVideo(input: input, output: output, edit: const EditSpec(lut: '/path/to/look.cube', lutIntensity: 0.8));
```

- `CubeLut.generate` builds a table from a function, `encode()` writes it as `.cube`.
- `Filmkit.getVideoFrame(path, position: …, maxDimension: …)` returns a frame as a `ui.Image` (e.g. for filter thumbnails).
- `LutFilter` needs Impeller (the default on Android and iOS); without it the child is shown unfiltered.

- Input and output are file paths. With photo_manager / insta_assets_picker, use `await asset.originFile`.
- The output is an MP4 (H.264 + AAC), SDR: HDR sources are tone mapped. Some Android devices can't tone map HDR; the export then fails with `hdrUnsupported`.
- Crop coordinates are in the displayed orientation (rotation tag applied), so a rect drawn over a preview can be passed as is.
- `Filmkit.getVideoInfo(path)` returns the displayed size, duration, and audio / HDR flags.
- `EditSpec` is serializable (`toJson` / `EditSpec.fromJson`).

Requirements: Android API 24+, iOS 15+.

## Principles

- The editing UI is Flutter; everything that produces a file is native.
- Filters are 3D LUTs, shared by the live preview (Flutter shader) and the native export, so that the preview and the exported file look the same.
- Edits are described by a serializable `EditSpec`, exportable with or without the editor screen.
- Picker-agnostic input: a file path (e.g. from an insta_assets_picker `AssetEntity`).

## Development

- Dart tests: `flutter test`.
- Native tests: `./gradlew :filmkit:testDebugUnitTest` in `example/android`; `RunnerTests` in `example/ios` (`xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=<device>' -only-testing:RunnerTests`).
- Export tests on a device: `flutter test integration_test -d <device>` in `example`, with the sample videos of `example/assets/videos` (colored quadrants and a gray band that encodes time, a color gradient, see `example/lib/sample_videos.dart`). They compare the export and the preview with the CPU reference pixel by pixel.
- On the Android emulator, add `--dart-define=EMULATOR=true`: its graphics layer converts BT.709 video frames with the BT.601 matrix, which shifts the colors of every Media3 export there (test `export keeps the source colors`).
