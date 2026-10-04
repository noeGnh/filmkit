import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../cube_lut.dart';
import '../edit_spec.dart';
import '../exceptions.dart';
import '../filmkit.dart';
import '../lut_filter.dart';
import '../video_export.dart';
import '../video_info.dart';
import 'adjustments.dart';
import 'crop_state.dart';
import 'crop_view.dart';
import 'editor_options.dart';
import 'editor_state.dart';
import 'looks.dart';
import 'trim_bar.dart';

/// The Instagram-style editor: crop, trim (videos), filters and adjustments, then export.
abstract final class FilmkitEditor {
  /// Opens the editor on the photo or video at [path] and returns the result when the user
  /// taps Done, `null` if they close it. [isVideo] defaults to a guess from the extension.
  ///
  /// [initialState] reopens the editor with earlier choices (`EditorResult.state`) on the same
  /// file. [title] is shown in the app bar, e.g. "2/4" when editing several files in a row.
  static Future<EditorResult?> open(
    BuildContext context, {
    required String path,
    bool? isVideo,
    EditorOptions options = const EditorOptions(),
    EditorState? initialState,
    String? title,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FilmkitEditorPage(path: path, isVideo: isVideo, options: options, initialState: initialState, title: title),
    ),
  );
}

const _videoExtensions = {'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'};

enum _Tool { filters, adjust, crop, trim }

enum _Adjustment { brightness, contrast, saturation, warmth }

/// The editor screen, for apps that manage their own navigation: it pops an [EditorResult].
class FilmkitEditorPage extends StatefulWidget {
  const FilmkitEditorPage({super.key, required this.path, this.isVideo, this.options = const EditorOptions(), this.initialState, this.title});

  final String path;
  final bool? isVideo;
  final EditorOptions options;
  final EditorState? initialState;

  /// Shown in the app bar.
  final String? title;

  @override
  State<FilmkitEditorPage> createState() => _FilmkitEditorPageState();
}

class _FilmkitEditorPageState extends State<FilmkitEditorPage> {
  late final bool _isVideo = widget.isVideo ?? _videoExtensions.contains(widget.path.split('.').last.toLowerCase());
  late final List<Look> _looks = widget.options.looks ?? Looks.builtIn;
  EditorTexts get _texts => widget.options.texts;

  Directory? _dir;
  Object? _error;
  bool _loading = true;

  /// Photo preview (oriented, sRGB).
  ui.Image? _photo;
  VideoPlayerController? _video;
  Duration _duration = Duration.zero;

  /// Small frame for the filter thumbnails.
  ui.Image? _thumbnail;
  List<ui.Image> _trimThumbnails = [];

  late CropState _crop;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = Duration.zero;
  Look? _look;
  double _intensity = 1;
  Adjustments _adjustments = const Adjustments();
  CubeLut? _lut;

  late _Tool _tool = _Tool.filters;
  bool _editingIntensity = false;
  _Adjustment? _editingAdjustment;
  bool _scrubbing = false;
  bool _looping = false;

  bool _exporting = false;
  VideoExport? _export;
  double? _exportProgress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _dir = await Directory('${Directory.systemTemp.path}/filmkit_editor/${DateTime.now().microsecondsSinceEpoch}').create(recursive: true);
      if (_isVideo) {
        await _loadVideo();
      } else {
        await _loadPhoto();
      }
      _restore(widget.initialState ?? const EditorState());
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Applies [state] once the media is loaded (its aspect and duration are known).
  void _restore(EditorState state) {
    final aspect = state.aspect ?? (widget.options.aspects.isEmpty ? CropAspect.original : widget.options.aspects.first);
    _crop = CropState(mediaAspect: _crop.mediaAspect, aspect: aspect, zoom: state.cropZoom, center: state.cropCenter).panned(Offset.zero);
    _look = _looks.where((look) => look.name == state.look).firstOrNull;
    _intensity = state.lookIntensity.clamp(0, 1);
    _adjustments = state.adjustments;
    _updateLut();
    if (_isVideo) {
      final (start, end) = clampTrim(
        state.trimStart,
        state.trimEnd ?? _duration,
        _duration,
        minLength: widget.options.minDuration,
        maxLength: widget.options.maxDuration,
      );
      _trimStart = start;
      _trimEnd = end;
    }
  }

  EditorState get _state => EditorState(
    look: _look?.name,
    lookIntensity: _intensity,
    adjustments: _adjustments,
    aspect: _crop.aspect,
    cropZoom: _crop.zoom,
    cropCenter: _crop.center,
    trimStart: _isVideo ? _trimStart : Duration.zero,
    trimEnd: _isVideo && _trimEnd < _duration ? _trimEnd : null,
  );

  Future<void> _loadPhoto() async {
    // A downscaled, oriented sRGB JPEG: decodes everywhere (HEIC included) and fast.
    final preview = await Filmkit.exportImage(input: widget.path, output: '${_dir!.path}/preview.jpg', edit: const EditSpec(maxDimension: 1600), quality: 92);
    final bytes = await File(preview.path).readAsBytes();
    _photo = await _decode(bytes);
    _thumbnail = await _decode(bytes, maxDimension: 240);
    _crop = CropState(mediaAspect: preview.width / preview.height);
  }

  Future<void> _loadVideo() async {
    final info = await Filmkit.getVideoInfo(widget.path);
    _duration = info.duration;
    // Until _restore applies the initial trim, so that the loop doesn't fire on a zero end.
    _trimEnd = info.duration;
    _crop = CropState(mediaAspect: info.width / info.height);
    final controller = VideoPlayerController.file(File(widget.path));
    await controller.initialize();
    _video = controller..addListener(_onVideoTick);
    // Thumbnails only decorate the filter strip and the trim bar: the video opens without them.
    _thumbnail = await Filmkit.getVideoFrame(
      widget.path,
      position: info.duration ~/ 2,
      maxDimension: 240,
    ).then<ui.Image?>((i) => i).catchError((_) => null, test: (e) => e is FilmkitException);
    unawaited(controller.play());
    unawaited(_loadTrimThumbnails());
  }

  Future<void> _loadTrimThumbnails() async {
    const count = 8;
    final thumbnails = <ui.Image>[];
    for (var i = 0; i < count; i++) {
      final position = _duration * ((i + 0.5) / count);
      try {
        thumbnails.add(await Filmkit.getVideoFrame(widget.path, position: position, maxDimension: 120));
      } on FilmkitException {
        break;
      }
      if (!mounted) {
        for (final image in thumbnails) {
          image.dispose();
        }
        return;
      }
    }
    if (thumbnails.isEmpty) return;
    setState(() => _trimThumbnails = thumbnails);
  }

  static Future<ui.Image> _decode(List<int> bytes, {int? maxDimension}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final landscape = descriptor.width >= descriptor.height;
    final codec = await descriptor.instantiateCodec(
      targetWidth: maxDimension != null && landscape ? maxDimension : null,
      targetHeight: maxDimension != null && !landscape ? maxDimension : null,
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return image;
  }

  /// Loops the trimmed range (the player stops by itself at the end of the file).
  void _onVideoTick() {
    final video = _video!;
    final value = video.value;
    if (_scrubbing || _exporting || _looping) return;
    if (value.isCompleted || value.position >= _trimEnd || (value.isPlaying && value.position < _trimStart - const Duration(milliseconds: 300))) {
      _looping = true;
      video.seekTo(_trimStart).then((_) => video.play()).whenComplete(() => _looping = false);
    }
  }

  @override
  void dispose() {
    _export?.cancel();
    _video?.dispose();
    _photo?.dispose();
    _thumbnail?.dispose();
    for (final image in _trimThumbnails) {
      image.dispose();
    }
    super.dispose();
  }

  void _updateLut() => _lut = combinedLut(_look, _intensity, _adjustments);

  Future<void> _done() async {
    final options = widget.options;
    String? lutPath;
    if (_lut != null) {
      lutPath = '${_dir!.path}/look.cube';
      await File(lutPath).writeAsString(_lut!.encode());
    }
    final edit = EditSpec(
      trimStart: _isVideo ? _trimStart : Duration.zero,
      trimEnd: _isVideo && _trimEnd < _duration ? _trimEnd : null,
      crop: _crop.isFull ? null : _crop.rect,
      maxDimension: options.maxDimension,
      lut: lutPath,
    );
    ExportResult? exported;
    if (options.export) {
      final output = options.outputPath ?? '${_dir!.path}/export.${_isVideo ? 'mp4' : 'jpg'}';
      setState(() {
        _exporting = true;
        _exportProgress = _isVideo ? 0 : null;
      });
      try {
        if (_isVideo) {
          await _video!.pause();
          final export = _export = Filmkit.exportVideo(input: widget.path, output: output, edit: edit);
          export.progress.listen((p) {
            if (mounted) setState(() => _exportProgress = p);
          });
          exported = await export.result;
        } else {
          exported = await Filmkit.exportImage(
            input: widget.path,
            output: output,
            edit: edit,
            quality: options.quality,
            keepLocation: options.keepLocation,
          );
        }
      } on FilmkitException catch (e) {
        if (!mounted) return;
        setState(() {
          _exporting = false;
          _export = null;
        });
        if (e.code != FilmkitErrorCode.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_texts.exportFailed}: ${e.message}')));
        }
        unawaited(_video?.play());
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      EditorResult(edit: edit, export: exported, look: _look, state: _state),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.white, scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(key: const ValueKey('filmkit.close'), icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          title: widget.title == null ? null : Text(widget.title!),
          centerTitle: true,
          actions: [
            TextButton(
              key: const ValueKey('filmkit.done'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _loading || _error != null || _exporting ? null : _done,
              child: Text(_texts.done, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${_texts.loadFailed}\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CropView(
                  key: const ValueKey('filmkit.preview'),
                  state: _crop,
                  interactive: _tool == _Tool.crop,
                  onChanged: (state) => setState(() => _crop = state),
                  frameBuilder: (frame) => LutFilter(lut: _lut, child: frame),
                  child: _isVideo ? VideoPlayer(_video!) : RawImage(image: _photo, fit: BoxFit.fill),
                ),
              ),
            ),
            SizedBox(height: 140, child: _panel()),
            _tabs(),
          ],
        ),
        if (_exporting) _exportOverlay(),
      ],
    );
  }

  Widget _tabs() {
    final tools = [_Tool.filters, _Tool.adjust, _Tool.crop, if (_isVideo) _Tool.trim];
    String label(_Tool tool) => switch (tool) {
      _Tool.filters => _texts.filters,
      _Tool.adjust => _texts.adjust,
      _Tool.crop => _texts.crop,
      _Tool.trim => _texts.trim,
    };
    IconData icon(_Tool tool) => switch (tool) {
      _Tool.filters => Icons.auto_awesome,
      _Tool.adjust => Icons.tune,
      _Tool.crop => Icons.crop,
      _Tool.trim => Icons.content_cut,
    };
    return SafeArea(
      top: false,
      child: Row(
        children: [
          for (final tool in tools)
            Expanded(
              child: InkWell(
                key: ValueKey('filmkit.tool.${tool.name}'),
                onTap: () => setState(() {
                  _tool = tool;
                  _editingIntensity = false;
                  _editingAdjustment = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Icon(icon(tool), color: tool == _tool ? Colors.white : Colors.white54),
                      const SizedBox(height: 4),
                      Text(label(tool), style: TextStyle(fontSize: 12, color: tool == _tool ? Colors.white : Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel() => switch (_tool) {
    _Tool.filters => _editingIntensity ? _intensityPanel() : _filtersPanel(),
    _Tool.adjust => _editingAdjustment == null ? _adjustPanel() : _adjustmentSlider(_editingAdjustment!),
    _Tool.crop => _cropPanel(),
    _Tool.trim => _trimPanel(),
  };

  Widget _filtersPanel() {
    final entries = <Look?>[null, ..._looks];
    return ListView.separated(
      key: const ValueKey('filmkit.looks'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final look = entries[i];
        final selected = look == _look;
        return GestureDetector(
          key: ValueKey('filmkit.look.${look?.name ?? 'none'}'),
          onTap: () => setState(() {
            if (selected && look != null) {
              _editingIntensity = true;
            } else {
              _look = look;
              _intensity = 1;
              _updateLut();
            }
          }),
          child: Column(
            children: [
              Text(look?.name ?? _texts.normal, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white70)),
              const SizedBox(height: 6),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2)),
                child: LutFilter(
                  lut: look?.lut,
                  child: RawImage(image: _thumbnail, fit: BoxFit.cover),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _intensityPanel() => _slider(
    key: const ValueKey('filmkit.intensity'),
    label: _look!.name,
    value: _intensity * 100,
    min: 0,
    onChanged: (v) => setState(() {
      _intensity = v / 100;
      _updateLut();
    }),
    onDone: () => setState(() => _editingIntensity = false),
  );

  Widget _adjustPanel() {
    String label(_Adjustment a) => switch (a) {
      _Adjustment.brightness => _texts.brightness,
      _Adjustment.contrast => _texts.contrast,
      _Adjustment.saturation => _texts.saturation,
      _Adjustment.warmth => _texts.warmth,
    };
    IconData icon(_Adjustment a) => switch (a) {
      _Adjustment.brightness => Icons.wb_sunny_outlined,
      _Adjustment.contrast => Icons.contrast,
      _Adjustment.saturation => Icons.water_drop_outlined,
      _Adjustment.warmth => Icons.thermostat,
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      children: [
        for (final a in _Adjustment.values)
          InkWell(
            key: ValueKey('filmkit.adjust.${a.name}'),
            onTap: () => setState(() => _editingAdjustment = a),
            child: SizedBox(
              width: 88,
              child: Column(
                children: [
                  Text(label(a), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Icon(icon(a), size: 32),
                  const SizedBox(height: 6),
                  Text(_value(a) == 0 ? '' : '${(_value(a) * 100).round()}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  double _value(_Adjustment a) => switch (a) {
    _Adjustment.brightness => _adjustments.brightness,
    _Adjustment.contrast => _adjustments.contrast,
    _Adjustment.saturation => _adjustments.saturation,
    _Adjustment.warmth => _adjustments.warmth,
  };

  Widget _adjustmentSlider(_Adjustment a) => _slider(
    key: ValueKey('filmkit.adjust.${a.name}.slider'),
    label: switch (a) {
      _Adjustment.brightness => _texts.brightness,
      _Adjustment.contrast => _texts.contrast,
      _Adjustment.saturation => _texts.saturation,
      _Adjustment.warmth => _texts.warmth,
    },
    value: _value(a) * 100,
    min: -100,
    onChanged: (v) => setState(() {
      final value = v / 100;
      _adjustments = switch (a) {
        _Adjustment.brightness => _adjustments.copyWith(brightness: value),
        _Adjustment.contrast => _adjustments.copyWith(contrast: value),
        _Adjustment.saturation => _adjustments.copyWith(saturation: value),
        _Adjustment.warmth => _adjustments.copyWith(warmth: value),
      };
      _updateLut();
    }),
    onDone: () => setState(() => _editingAdjustment = null),
  );

  Widget _slider({
    required Key key,
    required String label,
    required double value,
    required double min,
    required ValueChanged<double> onChanged,
    required VoidCallback onDone,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label  ${value.round()}', style: const TextStyle(fontSize: 13)),
          Slider(key: key, value: value, min: min, max: 100, onChanged: onChanged),
          TextButton(key: const ValueKey('filmkit.slider.done'), onPressed: onDone, child: Text(_texts.done)),
        ],
      ),
    );
  }

  Widget _cropPanel() {
    return Center(
      child: Wrap(
        spacing: 8,
        children: [
          for (final aspect in widget.options.aspects)
            ChoiceChip(
              key: ValueKey('filmkit.aspect.${aspect.label}'),
              label: Text(aspect.label),
              selected: aspect == _crop.aspect,
              onSelected: (_) => setState(() => _crop = _crop.withAspect(aspect)),
            ),
        ],
      ),
    );
  }

  Widget _trimPanel() {
    final video = _video!;
    return Padding(
      // Keeps the handles out of Android's back-gesture zones along the screen edges.
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: video,
          builder: (context, value, _) => TrimBar(
            duration: _duration,
            start: _trimStart,
            end: _trimEnd,
            thumbnails: _trimThumbnails,
            position: _scrubbing ? null : value.position,
            minLength: widget.options.minDuration > _duration ? _duration : widget.options.minDuration,
            maxLength: widget.options.maxDuration,
            onChanged: (start, end, moved) {
              if (!_scrubbing) video.pause();
              setState(() {
                _scrubbing = true;
                _trimStart = start;
                _trimEnd = end;
              });
              video.seekTo(moved);
            },
            onChangeEnd: () {
              setState(() => _scrubbing = false);
              video
                ..seekTo(_trimStart)
                ..play();
            },
          ),
        ),
      ),
    );
  }

  Widget _exportOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 200, child: LinearProgressIndicator(value: _exportProgress)),
              const SizedBox(height: 12),
              Text(_texts.exporting),
              if (_export != null) TextButton(key: const ValueKey('filmkit.export.cancel'), onPressed: _export!.cancel, child: Text(_texts.cancel)),
            ],
          ),
        ),
      ),
    );
  }
}
