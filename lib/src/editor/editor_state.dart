import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'adjustments.dart';
import 'crop_state.dart';

/// Everything the user chose in the editor, to reopen it where they left off
/// (`FilmkitEditor.open(initialState:)`). Serializable with [toJson] / [EditorState.fromJson].
@immutable
class EditorState {
  const EditorState({
    this.look,
    this.lookIntensity = 1,
    this.adjustments = const Adjustments(),
    this.aspect,
    this.cropZoom = 1,
    this.cropCenter = const Offset(0.5, 0.5),
    this.trimStart = Duration.zero,
    this.trimEnd,
  });

  factory EditorState.fromJson(Map<String, Object?> json) {
    final adjustments = (json['adjustments'] as Map?)?.cast<String, Object?>();
    final aspect = (json['aspect'] as Map?)?.cast<String, Object?>();
    final center = (json['cropCenter'] as List?)?.cast<num>();
    final trimEndMs = json['trimEndMs'] as int?;
    double number(Map<String, Object?>? map, String key, double fallback) => (map?[key] as num?)?.toDouble() ?? fallback;
    return EditorState(
      look: json['look'] as String?,
      lookIntensity: number(json, 'lookIntensity', 1),
      adjustments: Adjustments(
        brightness: number(adjustments, 'brightness', 0),
        contrast: number(adjustments, 'contrast', 0),
        saturation: number(adjustments, 'saturation', 0),
        warmth: number(adjustments, 'warmth', 0),
      ),
      aspect: aspect == null ? null : CropAspect(aspect['label']! as String, (aspect['ratio'] as num?)?.toDouble()),
      cropZoom: number(json, 'cropZoom', 1),
      cropCenter: center == null ? const Offset(0.5, 0.5) : Offset(center[0].toDouble(), center[1].toDouble()),
      trimStart: Duration(milliseconds: json['trimStartMs'] as int? ?? 0),
      trimEnd: trimEndMs == null ? null : Duration(milliseconds: trimEndMs),
    );
  }

  /// Name of the chosen look (matched against `EditorOptions.looks`), `null` for none.
  final String? look;
  final double lookIntensity;
  final Adjustments adjustments;

  /// The crop ratio; `null` for the first of `EditorOptions.aspects`.
  final CropAspect? aspect;

  /// Crop zoom and center, as in [CropState].
  final double cropZoom;
  final Offset cropCenter;

  /// Video trim; `trimEnd` `null` for the end of the video.
  final Duration trimStart;
  final Duration? trimEnd;

  Map<String, Object?> toJson() => {
    'look': look,
    'lookIntensity': lookIntensity,
    'adjustments': {
      'brightness': adjustments.brightness,
      'contrast': adjustments.contrast,
      'saturation': adjustments.saturation,
      'warmth': adjustments.warmth,
    },
    'aspect': aspect == null ? null : {'label': aspect!.label, 'ratio': aspect!.ratio},
    'cropZoom': cropZoom,
    'cropCenter': [cropCenter.dx, cropCenter.dy],
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd?.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is EditorState &&
      other.look == look &&
      other.lookIntensity == lookIntensity &&
      other.adjustments == adjustments &&
      other.aspect == aspect &&
      other.cropZoom == cropZoom &&
      other.cropCenter == cropCenter &&
      other.trimStart == trimStart &&
      other.trimEnd == trimEnd;

  @override
  int get hashCode => Object.hash(look, lookIntensity, adjustments, aspect, cropZoom, cropCenter, trimStart, trimEnd);

  @override
  String toString() =>
      'EditorState(look: $look, lookIntensity: $lookIntensity, $adjustments, aspect: ${aspect?.label}, cropZoom: $cropZoom, '
      'cropCenter: $cropCenter, trim: $trimStart–$trimEnd)';
}
