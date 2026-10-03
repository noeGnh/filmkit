import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// A description of the edits applied by an export.
///
/// Coordinates are in the video's displayed orientation (after its rotation tag), so a crop
/// drawn over a preview can be passed as is. The spec is serializable ([toJson] /
/// [EditSpec.fromJson]) to be stored and exported later.
@immutable
class EditSpec {
  const EditSpec({this.trimStart = Duration.zero, this.trimEnd, this.crop, this.maxDimension});

  /// Restores a spec written by [toJson].
  factory EditSpec.fromJson(Map<String, Object?> json) {
    final crop = (json['crop'] as List<Object?>?)?.cast<num>();
    final trimEndMs = json['trimEndMs'] as int?;
    return EditSpec(
      trimStart: Duration(milliseconds: json['trimStartMs'] as int? ?? 0),
      trimEnd: trimEndMs == null ? null : Duration(milliseconds: trimEndMs),
      crop: crop == null ? null : Rect.fromLTRB(crop[0].toDouble(), crop[1].toDouble(), crop[2].toDouble(), crop[3].toDouble()),
      maxDimension: json['maxDimension'] as int?,
    );
  }

  /// Start of the kept range.
  final Duration trimStart;

  /// End of the kept range, `null` for the end of the video.
  final Duration? trimEnd;

  /// Kept area, normalized: `Rect.fromLTRB(0, 0, 1, 1)` is the whole frame. `null` keeps the
  /// whole frame.
  final Rect? crop;

  /// Longest side of the output in pixels. The output is scaled down to fit, never up.
  /// `null` keeps the (cropped) source size.
  final int? maxDimension;

  /// Throws an [ArgumentError] if the spec can't describe a valid export.
  void validate() {
    if (trimStart.isNegative) throw ArgumentError.value(trimStart, 'trimStart', 'must not be negative');
    final end = trimEnd;
    if (end != null && end <= trimStart) throw ArgumentError.value(end, 'trimEnd', 'must be after trimStart');
    final c = crop;
    if (c != null && (c.left < 0 || c.top < 0 || c.right > 1 || c.bottom > 1 || c.width <= 0 || c.height <= 0)) {
      throw ArgumentError.value(c, 'crop', 'must be a non-empty rect within [0, 1]');
    }
    final max = maxDimension;
    if (max != null && max < 2) throw ArgumentError.value(max, 'maxDimension', 'must be at least 2');
  }

  Map<String, Object?> toJson() => {
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd?.inMilliseconds,
    'crop': crop == null ? null : [crop!.left, crop!.top, crop!.right, crop!.bottom],
    'maxDimension': maxDimension,
  };

  @override
  bool operator ==(Object other) =>
      other is EditSpec && other.trimStart == trimStart && other.trimEnd == trimEnd && other.crop == crop && other.maxDimension == maxDimension;

  @override
  int get hashCode => Object.hash(trimStart, trimEnd, crop, maxDimension);

  @override
  String toString() => 'EditSpec(trimStart: $trimStart, trimEnd: $trimEnd, crop: $crop, maxDimension: $maxDimension)';
}
