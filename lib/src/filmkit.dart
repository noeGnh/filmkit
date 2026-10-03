import 'edit_spec.dart';
import 'filmkit_platform.dart';
import 'video_export.dart';
import 'video_info.dart';

/// Native video export: Media3 Transformer on Android, AVFoundation on iOS.
abstract final class Filmkit {
  /// Exports [input] to [output] with the edits in [edit].
  ///
  /// [input] and [output] are file paths; the output is an MP4 (H.264 + AAC), SDR, and an
  /// existing file there is replaced. Await `result` on the returned export: it completes with
  /// a `FilmkitException` on failure. Throws an [ArgumentError] right away if [edit] is
  /// invalid.
  static VideoExport exportVideo({required String input, required String output, EditSpec edit = const EditSpec()}) =>
      FilmkitPlatform.instance.exportVideo(input: input, output: output, edit: edit);

  /// Reads the displayed size, duration, audio and HDR flags of the video at [path].
  static Future<VideoInfo> getVideoInfo(String path) => FilmkitPlatform.instance.getVideoInfo(path);
}
