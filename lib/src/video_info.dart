import 'package:flutter/foundation.dart';

/// Properties of a video file, as a player displays it.
@immutable
class VideoInfo {
  const VideoInfo({
    required this.width,
    required this.height,
    required this.duration,
    required this.hasAudio,
    required this.isHdr,
  });

  factory VideoInfo.fromMap(Map<String, Object?> map) => VideoInfo(
    width: map['width']! as int,
    height: map['height']! as int,
    duration: Duration(milliseconds: map['durationMs']! as int),
    hasAudio: map['hasAudio']! as bool,
    isHdr: map['isHdr']! as bool,
  );

  /// Displayed size, i.e. with the rotation tag applied.
  final int width;
  final int height;
  final Duration duration;
  final bool hasAudio;

  /// HDR10, HLG or Dolby Vision. Exports convert it to SDR.
  final bool isHdr;

  @override
  String toString() => 'VideoInfo(${width}x$height, duration: $duration, hasAudio: $hasAudio, isHdr: $isHdr)';
}

/// The file written by an export (video or photo).
@immutable
class ExportResult {
  const ExportResult({required this.path, required this.width, required this.height});

  factory ExportResult.fromMap(Map<String, Object?> map) =>
      ExportResult(path: map['path']! as String, width: map['width']! as int, height: map['height']! as int);

  /// The output path passed to the export.
  final String path;

  /// Displayed size of the output.
  final int width;
  final int height;

  @override
  String toString() => 'ExportResult($path, ${width}x$height)';
}
