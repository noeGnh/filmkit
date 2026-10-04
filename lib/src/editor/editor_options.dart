import 'package:flutter/foundation.dart';

import '../edit_spec.dart';
import '../video_info.dart';
import 'adjustments.dart';
import 'crop_state.dart';
import 'editor_state.dart';
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

  EditorTexts copyWith({
    String? done,
    String? crop,
    String? trim,
    String? filters,
    String? adjust,
    String? normal,
    String? brightness,
    String? contrast,
    String? saturation,
    String? warmth,
    String? exporting,
    String? cancel,
    String? exportFailed,
    String? loadFailed,
  }) => EditorTexts(
    done: done ?? this.done,
    crop: crop ?? this.crop,
    trim: trim ?? this.trim,
    filters: filters ?? this.filters,
    adjust: adjust ?? this.adjust,
    normal: normal ?? this.normal,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    exporting: exporting ?? this.exporting,
    cancel: cancel ?? this.cancel,
    exportFailed: exportFailed ?? this.exportFailed,
    loadFailed: loadFailed ?? this.loadFailed,
  );
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

  /// A copy with the given fields replaced. The nullable [looks], [outputPath], [maxDimension]
  /// and [maxDuration] can't be reset to `null` this way.
  EditorOptions copyWith({
    List<Look>? looks,
    List<CropAspect>? aspects,
    bool? export,
    String? outputPath,
    int? maxDimension,
    int? quality,
    bool? keepLocation,
    Duration? minDuration,
    Duration? maxDuration,
    EditorTexts? texts,
  }) => EditorOptions(
    looks: looks ?? this.looks,
    aspects: aspects ?? this.aspects,
    export: export ?? this.export,
    outputPath: outputPath ?? this.outputPath,
    maxDimension: maxDimension ?? this.maxDimension,
    quality: quality ?? this.quality,
    keepLocation: keepLocation ?? this.keepLocation,
    minDuration: minDuration ?? this.minDuration,
    maxDuration: maxDuration ?? this.maxDuration,
    texts: texts ?? this.texts,
  );
}

/// What the editor returns when the user taps Done.
@immutable
class EditorResult {
  const EditorResult({required this.edit, this.export, this.look, required this.state});

  /// The edits. Its `lut`, if any, is a `.cube` file the editor wrote in the temporary
  /// directory (look and adjustments combined): copy it to keep the spec for later.
  final EditSpec edit;

  /// The exported file, when `EditorOptions.export` is true.
  final ExportResult? export;

  /// The chosen filter, `null` for none.
  final Look? look;

  /// The user's choices, to reopen the editor with them (`FilmkitEditor.open(initialState:)`).
  final EditorState state;

  double get lookIntensity => state.lookIntensity;
  Adjustments get adjustments => state.adjustments;
  CropAspect get aspect => state.aspect!;

  @override
  String toString() => 'EditorResult($edit, export: $export, $state)';
}
