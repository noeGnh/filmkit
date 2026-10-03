import 'dart:io';

import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';

import 'sample_looks.dart';
import 'sample_videos.dart';

void main() => runApp(const MaterialApp(home: ExportDemoPage()));

/// Exports a bundled sample video or photo with a few edit presets and an optional film look,
/// previewed with [LutFilter].
class ExportDemoPage extends StatefulWidget {
  const ExportDemoPage({super.key});

  @override
  State<ExportDemoPage> createState() => _ExportDemoPageState();
}

class _ExportDemoPageState extends State<ExportDemoPage> {
  static const _presets = {
    'Trim 1–4 s': EditSpec(trimStart: Duration(seconds: 1), trimEnd: Duration(seconds: 4)),
    'Square crop': EditSpec(crop: Rect.fromLTRB(0.25, 0, 0.75, 1)),
    'Max 320 px': EditSpec(maxDimension: 320),
    'All': EditSpec(trimStart: Duration(seconds: 1), trimEnd: Duration(seconds: 4), crop: Rect.fromLTRB(0.25, 0, 0.75, 1), maxDimension: 320),
  };

  static final _names = [...sampleVideos, 'gradient.jpg', 'oriented_6.jpg', 'gradient.heic'];

  /// Sample files by name.
  Map<String, String>? _media;
  String _name = _names.first;
  bool get _isPhoto => !_name.endsWith('.mp4');
  String _preset = _presets.keys.first;
  String? _inputInfo;
  ui.Image? _frame;
  String? _lookPath;
  bool _look = false;
  double _intensity = 1;

  bool _exporting = false;
  VideoExport? _export;
  double _progress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    Future.wait([copySampleVideos(), copySamplePhotos()]).then((copies) async {
      final lookPath = '${Directory.systemTemp.path}/film_look.cube';
      await File(lookPath).writeAsString(filmLook.encode());
      setState(() {
        _media = {...copies[0], ...copies[1]};
        _lookPath = lookPath;
      });
      _loadInfo();
    });
  }

  Future<void> _loadInfo() async {
    final path = _media![_name]!;
    final String info;
    final ui.Image frame;
    if (_isPhoto) {
      // A small oriented sRGB JPEG decodes everywhere, HEIC included.
      final preview = await Filmkit.exportImage(
        input: path,
        output: '${Directory.systemTemp.path}/filmkit_preview.jpg',
        edit: const EditSpec(maxDimension: 640),
      );
      frame = await _decode(preview.path);
      info = 'Photo';
    } else {
      final video = await Filmkit.getVideoInfo(path);
      frame = await Filmkit.getVideoFrame(path, position: video.duration ~/ 2, maxDimension: 640);
      info = '$video';
    }
    if (!mounted) return frame.dispose();
    final old = _frame;
    setState(() {
      _inputInfo = info;
      _frame = frame;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  static Future<ui.Image> _decode(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  }

  @override
  void dispose() {
    _frame?.dispose();
    super.dispose();
  }

  EditSpec get _edit {
    final preset = _presets[_preset]!;
    return EditSpec(
      trimStart: preset.trimStart,
      trimEnd: preset.trimEnd,
      crop: preset.crop,
      maxDimension: preset.maxDimension,
      lut: _look ? _lookPath : null,
      lutIntensity: _intensity,
    );
  }

  Future<void> _run() => _isPhoto ? _runPhoto() : _runVideo();

  Future<void> _runPhoto() async {
    final input = _media![_name]!;
    final output = '${Directory.systemTemp.path}/filmkit_demo_${_name.split('.').first}.jpg';
    setState(() {
      _exporting = true;
      _status = 'Exporting…';
    });
    final watch = Stopwatch()..start();
    String status;
    try {
      final result = await Filmkit.exportImage(input: input, output: output, edit: _edit);
      status = 'Done in ${watch.elapsedMilliseconds} ms\n$result';
    } on FilmkitException catch (e) {
      status = 'Failed: $e';
    }
    if (mounted) {
      setState(() {
        _exporting = false;
        _status = status;
      });
    }
  }

  Future<void> _runVideo() async {
    final input = _media![_name]!;
    final output = '${Directory.systemTemp.path}/filmkit_demo_${_name.replaceAll('.mp4', '')}.mp4';
    final export = Filmkit.exportVideo(input: input, output: output, edit: _edit);
    setState(() {
      _exporting = true;
      _export = export;
      _progress = 0;
      _status = 'Exporting…';
    });
    export.progress.listen((p) => setState(() => _progress = p));
    final watch = Stopwatch()..start();
    String status;
    try {
      final result = await export.result;
      final info = await Filmkit.getVideoInfo(result.path);
      status = 'Done in ${watch.elapsedMilliseconds} ms\n$info\n${result.path}';
    } on FilmkitException catch (e) {
      status = e.code == FilmkitErrorCode.cancelled ? 'Cancelled' : 'Failed: $e';
    }
    if (mounted) {
      setState(() {
        _exporting = false;
        _export = null;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _exporting;
    return Scaffold(
      appBar: AppBar(title: const Text('filmkit')),
      body: _media == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownMenu<String>(
                  label: const Text('Sample'),
                  initialSelection: _name,
                  enabled: !busy,
                  dropdownMenuEntries: [for (final v in _names) DropdownMenuEntry(value: v, label: v)],
                  onSelected: (v) {
                    setState(() {
                      _name = v!;
                      _inputInfo = null;
                    });
                    _loadInfo();
                  },
                ),
                const SizedBox(height: 8),
                Text(_inputInfo ?? '…'),
                const SizedBox(height: 8),
                if (_frame != null)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: AspectRatio(
                        aspectRatio: _frame!.width / _frame!.height,
                        child: LutFilter(
                          lut: _look ? filmLook : null,
                          intensity: _intensity,
                          child: RawImage(image: _frame, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Film look'),
                  value: _look,
                  onChanged: busy ? null : (v) => setState(() => _look = v),
                ),
                if (_look)
                  Slider(
                    value: _intensity,
                    label: '${(_intensity * 100).round()} %',
                    divisions: 20,
                    onChanged: busy ? null : (v) => setState(() => _intensity = v),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in _presets.keys)
                      ChoiceChip(label: Text(name), selected: name == _preset, onSelected: busy ? null : (_) => setState(() => _preset = name)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(onPressed: busy ? null : _run, child: const Text('Export')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _export?.cancel, child: const Text('Cancel')),
                  ],
                ),
                const SizedBox(height: 16),
                if (busy) LinearProgressIndicator(value: _export == null ? null : _progress),
                if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
              ],
            ),
    );
  }
}
