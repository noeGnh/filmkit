import 'dart:ui' as ui;

import 'edit_spec.dart';
import 'filmkit_platform.dart';
import 'video_export.dart';
import 'video_info.dart';

/// Native photo and video export: Media3 Transformer and Android graphics on Android,
/// AVFoundation and Core Image on iOS.
abstract final class Filmkit {
  /// Exports [input] to [output] with the edits in [edit].
  ///
  /// [input] and [output] are file paths (also `edit.lut`); the output is an MP4 (H.264 + AAC), SDR, and an
  /// existing file there is replaced. Await `result` on the returned export: it completes with
  /// a `FilmkitException` on failure. Throws an [ArgumentError] right away if [edit] is
  /// invalid.
  static VideoExport exportVideo({required String input, required String output, EditSpec edit = const EditSpec()}) =>
      FilmkitPlatform.instance.exportVideo(input: input, output: output, edit: edit);

  /// Exports the photo at [input] (JPEG, PNG, HEIC, WebP…) to a JPEG at [output] with the
  /// crop, `maxDimension` and LUT of [edit] (trim is ignored).
  ///
  /// The EXIF orientation is applied to the pixels, and [edit]'s crop is in the displayed
  /// orientation, as for videos. The output is sRGB, with the capture date, camera and
  /// exposure metadata of the input; the location is removed unless [keepLocation] is true.
  /// [quality] is the JPEG quality, 1 to 100. Fails with a `FilmkitException`.
  static Future<ExportResult> exportImage({
    required String input,
    required String output,
    EditSpec edit = const EditSpec(),
    int quality = 90,
    bool keepLocation = false,
  }) => FilmkitPlatform.instance.exportImage(input: input, output: output, edit: edit, quality: quality, keepLocation: keepLocation);

  /// Reads the displayed size, duration, audio and HDR flags of the video at [path].
  static Future<VideoInfo> getVideoInfo(String path) => FilmkitPlatform.instance.getVideoInfo(path);

  /// The frame of the video at [path] closest to [position], as displayed (rotation applied),
  /// scaled down so that its longest side fits [maxDimension] if given. Colors are the
  /// decoded values, as a video player shows them: the input of `LutFilter` and of the export.
  /// Dispose the image when done.
  static Future<ui.Image> getVideoFrame(String path, {Duration position = Duration.zero, int? maxDimension}) =>
      FilmkitPlatform.instance.getVideoFrame(path, position: position, maxDimension: maxDimension);
}
