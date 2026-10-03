import 'package:flutter/foundation.dart';

import '../edit_spec.dart';
import '../video_info.dart';
import 'adjustments.dart';
import 'crop_state.dart';
import 'looks.dart';

/// The editor's labels, in English by default.
@immutable
class EditorTexts {
  const EditorTexts({
    this.done = 'Done',
    this.crop = 'Crop',
    this.trim = 'Trim',
    this.filters = 'Filters',
    this.adjust = 'Adjust',
    this.normal = 'Normal',
    this.brightness = 'Brightness',
    this.contrast = 'Contrast',
    this.saturation = 'Saturation',
    this.warmth = 'Warmth',
    this.exporting = 'Exporting…',
    this.cancel = 'Cancel',
    this.exportFailed = 'Export failed',
    this.loadFailed = "Can't open this file",
  });

  final String done;
  final String crop;
  final String trim;
  final String filters;
  final String adjust;

  /// Name of the "no filter" entry.
  final String normal;
  final String brightness;
  final String contrast;
  final String saturation;
  final String warmth;
  final String exporting;
  final String cancel;
  final String exportFailed;
  final String loadFailed;
}

@immutable
class EditorOptions {
  const EditorOptions({
    this.looks,
    this.aspects = CropAspect.defaults,
    this.export = true,
    this.outputPath,
    this.maxDimension = 1080,
    this.quality = 90,
    this.keepLocation = false,
    this.minDuration = const Duration(seconds: 1),
    this.maxDuration,
    this.texts = const EditorTexts(),
  });

  /// The filters offered; `null` for [Looks.builtIn].
  final List<Look>? looks;

  /// The crop ratios offered, the first one selected at start.
  final List<CropAspect> aspects;

  /// Whether Done exports the file (with a progress overlay) or only returns the [EditSpec].
  final bool export;

  /// Where to write the export; a new file in the temporary directory by default.
  final String? outputPath;

  /// `EditSpec.maxDimension` of the result.
  final int? maxDimension;

  /// JPEG quality of photo exports.
  final int quality;

  /// Keep the GPS metadata of photos.
  final bool keepLocation;

  /// Shortest and longest trimmed video.
  final Duration minDuration;
  final Duration? maxDuration;

  final EditorTexts texts;
}

/// What the editor returns when the user taps Done.
@immutable
class EditorResult {
  const EditorResult({required this.edit, this.export, this.look, this.lookIntensity = 1, this.adjustments = const Adjustments(), required this.aspect});

  /// The edits. Its `lut`, if any, is a `.cube` file the editor wrote in the temporary
  /// directory (look and adjustments combined): copy it to keep the spec for later.
  final EditSpec edit;

  /// The exported file, when `EditorOptions.export` is true.
  final ExportResult? export;

  /// The chosen filter, `null` for none.
  final Look? look;
  final double lookIntensity;
  final Adjustments adjustments;
  final CropAspect aspect;

  @override
  String toString() => 'EditorResult($edit, export: $export, look: ${look?.name}, adjustments: $adjustments)';
}
