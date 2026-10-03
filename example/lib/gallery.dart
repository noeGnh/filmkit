import 'dart:async';

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';
import 'package:insta_assets_picker/insta_assets_picker.dart';

/// Picks a photo or video with insta_assets_picker, then edits it with filmkit. The picker's
/// own crop is skipped: the ratio and area chosen in it become the editor's initial crop.
Future<EditorResult?> pickAndEdit(BuildContext context, {EditorOptions options = const EditorOptions()}) async {
  final details = Completer<InstaAssetsExportDetails>();
  final selected = await InstaAssetPicker.pickAssets(
    context,
    maxAssets: 1,
    pickerConfig: const InstaAssetPickerConfig(title: 'Gallery', closeOnComplete: true, skipCropOnComplete: true),
    onCompleted: (stream) => stream.first.then(details.complete),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return null;
  final asset = selected.first;
  final file = await asset.originFile;
  if (file == null || !context.mounted) return null;

  final mediaAspect = asset.orientatedWidth / asset.orientatedHeight;
  // Without the picker's details, the editor opens with its default crop.
  final picked = await details.future.then<InstaAssetsExportDetails?>((d) => d).timeout(const Duration(seconds: 2), onTimeout: () => null);
  var initialState = const EditorState();
  if (picked != null) {
    final aspect = _aspectFor(picked.aspectRatio, options.aspects);
    final area = picked.data.firstOrNull?.selectedData.area;
    final crop = area == null ? null : CropState.fromRect(mediaAspect: mediaAspect, aspect: aspect, rect: area);
    initialState = EditorState(aspect: aspect, cropZoom: crop?.zoom ?? 1, cropCenter: crop?.center ?? const Offset(0.5, 0.5));
  }
  if (!context.mounted) return null;
  return FilmkitEditor.open(context, path: file.path, isVideo: asset.type == AssetType.video, options: options, initialState: initialState);
}

/// The editor ratio matching the picker's (1:1 or 4:5 by default).
CropAspect _aspectFor(double ratio, List<CropAspect> aspects) =>
    aspects.where((a) => a.ratio != null && (a.ratio! - ratio).abs() < 0.01).firstOrNull ?? CropAspect('${ratio.toStringAsFixed(2)}:1', ratio);
