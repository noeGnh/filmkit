import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// A description of the edits applied by an export.
///
/// Coordinates are in the video's displayed orientation (after its rotation tag), so a crop
/// drawn over a preview can be passed as is. The spec is serializable ([toJson] /
/// [EditSpec.fromJson]) to be stored and exported later.
@immutable
class EditSpec {
  const EditSpec({this.trimStart = Duration.zero, this.trimEnd, this.crop, this.maxDimension, this.lut, this.lutIntensity = 1});

  /// Restores a spec written by [toJson].
  factory EditSpec.fromJson(Map<String, Object?> json) {
    final crop = (json['crop'] as List<Object?>?)?.cast<num>();
    final trimEndMs = json['trimEndMs'] as int?;
    return EditSpec(
      trimStart: Duration(milliseconds: json['trimStartMs'] as int? ?? 0),
      trimEnd: trimEndMs == null ? null : Duration(milliseconds: trimEndMs),
      crop: crop == null ? null : Rect.fromLTRB(crop[0].toDouble(), crop[1].toDouble(), crop[2].toDouble(), crop[3].toDouble()),
      maxDimension: json['maxDimension'] as int?,
      lut: json['lut'] as String?,
      lutIntensity: (json['lutIntensity'] as num?)?.toDouble() ?? 1,
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

  /// Path of a `.cube` file (see `CubeLut`) applied to the colors, `null` for none.
  final String? lut;

  /// Strength of [lut], from 0 (no effect) to 1 (the table as is).
  final double lutIntensity;

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
    if (lutIntensity < 0 || lutIntensity > 1) throw ArgumentError.value(lutIntensity, 'lutIntensity', 'must be in [0, 1]');
  }

  Map<String, Object?> toJson() => {
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd?.inMilliseconds,
    'crop': crop == null ? null : [crop!.left, crop!.top, crop!.right, crop!.bottom],
    'maxDimension': maxDimension,
    'lut': lut,
    'lutIntensity': lutIntensity,
  };

  @override
  bool operator ==(Object other) =>
      other is EditSpec &&
      other.trimStart == trimStart &&
      other.trimEnd == trimEnd &&
      other.crop == crop &&
      other.maxDimension == maxDimension &&
      other.lut == lut &&
      other.lutIntensity == lutIntensity;

  @override
  int get hashCode => Object.hash(trimStart, trimEnd, crop, maxDimension, lut, lutIntensity);

  @override
  String toString() => 'EditSpec(trimStart: $trimStart, trimEnd: $trimEnd, crop: $crop, maxDimension: $maxDimension, lut: $lut, lutIntensity: $lutIntensity)';
}
