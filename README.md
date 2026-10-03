# filmkit

Photo and video editing for Flutter: crop, trim, LUT filters and adjustments, exported natively (Media3 Transformer on Android, AVFoundation on iOS), with an Instagram-style editor screen.

> **Status**: 0.6, Instagram-style editor with re-editing, and headless video and photo export (trim, crop, resize, LUT filters). Tested on Android (Pixel 8a, emulator) and the iOS simulator.

## Editor

<p>
  <img src="doc/filters.jpg" width="200" alt="Filters">
  <img src="doc/crop.jpg" width="200" alt="Crop">
  <img src="doc/adjust.jpg" width="200" alt="Adjustments">
  <img src="doc/trim.jpg" width="200" alt="Video trim">
</p>

<sub>Photo: <a href="https://commons.wikimedia.org/wiki/File:Brighton_beach_at_sunset_2025-02-27.jpg">Brighton beach at sunset</a>, Wikimedia Commons, CC0.</sub>

```dart
final result = await FilmkitEditor.open(context, path: file.path);
if (result != null) {
  print(result.export!.path); // the exported MP4 or JPEG
  print(result.edit);         // the EditSpec, to export again later
}
```

- Tools: filters (tap again for the intensity), adjustments (brightness, contrast, saturation, warmth), crop (ratios, pan and pinch-zoom), trim for videos.
- `EditorOptions`: the looks offered (`looks:`, default `Looks.builtIn`), the crop ratios (`aspects:`), `export: false` to only get the `EditSpec`, `outputPath`, `maxDimension` (1080 by default), `quality`, `keepLocation`, `minDuration` / `maxDuration` of the trim, and `texts:` to translate the labels (`EditorTexts`).
- Your own filters: `Look('Name', await CubeLut.fromFile(path))` or `Look.generate('Name', (r, g, b) => ...)`.
- Reopen the editor where the user left off: save `result.state.toJson()` (an `EditorState`), and pass `EditorState.fromJson(...)` as `initialState:` to `FilmkitEditor.open` on the same file.
- `FilmkitEditorPage` is the screen itself, for apps that handle navigation themselves.
- Adjustments only change colors, so they are baked into the look's LUT: the exporters only ever apply one table. The result's `edit.lut` is that combined table, written to the temporary directory.

## With insta_assets_picker

filmkit doesn't include a picker: [insta_assets_picker](https://pub.dev/packages/insta_assets_picker) gives the Instagram-style gallery, filmkit the editing. Skip the picker's own crop and hand its ratio and area to the editor (full version in [example/lib/gallery.dart](example/lib/gallery.dart)):

```dart
final details = Completer<InstaAssetsExportDetails>();
final selected = await InstaAssetPicker.pickAssets(
  context,
  maxAssets: 1,
  pickerConfig: const InstaAssetPickerConfig(closeOnComplete: true, skipCropOnComplete: true),
  onCompleted: (stream) => stream.first.then(details.complete),
);
final asset = selected!.first;
final file = (await asset.originFile)!;
final picked = await details.future;
final aspect = CropAspect('picker', picked.aspectRatio);
final crop = CropState.fromRect(
  mediaAspect: asset.orientatedWidth / asset.orientatedHeight,
  aspect: aspect,
  rect: picked.data.first.selectedData.area ?? const Rect.fromLTRB(0, 0, 1, 1),
);
final result = await FilmkitEditor.open(
  context,
  path: file.path,
  isVideo: asset.type == AssetType.video,
  initialState: EditorState(aspect: aspect, cropZoom: crop.zoom, cropCenter: crop.center),
);
```

Setup, as of insta_assets_picker 3.4.0:

- Gallery permissions, see [wechat_assets_picker's guide](https://pub.dev/packages/wechat_assets_picker#preparing-for-use-) (`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` on Android, `NSPhotoLibraryUsageDescription` on iOS).
- Android: its `insta_assets_crop` dependency compiles against API 31, which current AndroidX libraries refuse. Raise it in `android/build.gradle.kts` (see the [example](example/android/build.gradle.kts)).
- iOS: `insta_assets_crop` doesn't support Swift Package Manager yet, so the app builds with CocoaPods for it (Flutter does it automatically).

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

## Photo export

```dart
final result = await Filmkit.exportImage(
  input: '/path/to/photo.heic',
  output: '/path/to/photo.jpg',
  edit: const EditSpec(crop: Rect.fromLTRB(0, 0.1, 1, 0.9), maxDimension: 2048, lut: '/path/to/look.cube'),
  quality: 90,           // JPEG quality
  keepLocation: false,   // GPS metadata removed by default
);
```

- Input: JPEG, HEIC, PNG, WebP… Output: an sRGB JPEG.
- The EXIF orientation is applied to the pixels, and the crop is in the displayed orientation, as for videos.
- Capture date, camera, lens and exposure metadata are kept; the location only if `keepLocation` is true.

## Filters

Filters are 3D LUTs in `.cube` files (Resolve, Photoshop, Lightroom…), applied with the same result by the preview and the export.

```dart
final look = await CubeLut.fromFile('/path/to/look.cube');

// Live preview on any widget: an image, a video player…
LutFilter(lut: look, intensity: 0.8, child: VideoPlayer(controller));

// Export
Filmkit.exportVideo(input: input, output: output, edit: const EditSpec(lut: '/path/to/look.cube', lutIntensity: 0.8));
Filmkit.exportImage(input: photo, output: jpeg, edit: const EditSpec(lut: '/path/to/look.cube', lutIntensity: 0.8));
```

- `CubeLut.generate` builds a table from a function, `encode()` writes it as `.cube`.
- `Filmkit.getVideoFrame(path, position: …, maxDimension: …)` returns a frame as a `ui.Image` (e.g. for filter thumbnails).
- `LutFilter` needs Impeller (the default on Android and iOS); without it the child is shown unfiltered.

- Input and output are file paths. With photo_manager / insta_assets_picker, use `await asset.originFile`.
- The output is an MP4 (H.264 + AAC), SDR: HDR sources are tone mapped by the platform (Media3 on Android, AVFoundation on iOS), so the result differs slightly between the two. Phone videos (HLG) convert well on both; Android renders them a little darker. With HDR10 (PQ) sources, Android adds a slight pink cast to bright grays, and iOS clips bright saturated colors, which can change their hue (a bright sky turns cyan). Some Android devices can't tone map HDR; the export then fails with `hdrUnsupported`.
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
- Export tests on a device: `flutter test integration_test -d <device>` in `example`, with the sample videos of `example/assets/videos` (colored quadrants and a gray band that encodes time, a color gradient) and photos of `example/assets/photos` (a gradient, the quadrant pattern in the 8 EXIF orientations with metadata), see `example/lib/sample_videos.dart`). They compare the export and the preview with the CPU reference pixel by pixel.
- On the Android emulator, add `--dart-define=EMULATOR=true`: its graphics layer converts BT.709 video frames with the BT.601 matrix, which shifts the colors of every Media3 export there (test `export keeps the source colors`).
