import 'dart:io';

import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';

import 'sample_looks.dart';
import 'sample_videos.dart';

void main() => runApp(const MaterialApp(home: ExportDemoPage()));

/// Exports a bundled sample video with a few edit presets and an optional film look, previewed
/// on a frame with [LutFilter].
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

  Map<String, String>? _videos;
  String _video = sampleVideos.first;
  String _preset = _presets.keys.first;
  VideoInfo? _inputInfo;
  ui.Image? _frame;
  String? _lookPath;
  bool _look = false;
  double _intensity = 1;

  VideoExport? _export;
  double _progress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    copySampleVideos().then((videos) async {
      final lookPath = '${Directory.systemTemp.path}/film_look.cube';
      await File(lookPath).writeAsString(filmLook.encode());
      setState(() {
        _videos = videos;
        _lookPath = lookPath;
      });
      _loadInfo();
    });
  }

  Future<void> _loadInfo() async {
    final path = _videos![_video]!;
    final info = await Filmkit.getVideoInfo(path);
    final frame = await Filmkit.getVideoFrame(path, position: info.duration ~/ 2, maxDimension: 640);
    if (!mounted) return frame.dispose();
    final old = _frame;
    setState(() {
      _inputInfo = info;
      _frame = frame;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
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

  Future<void> _run() async {
    final input = _videos![_video]!;
    final output = '${Directory.systemTemp.path}/filmkit_demo_${_video.replaceAll('.mp4', '')}.mp4';
    final export = Filmkit.exportVideo(input: input, output: output, edit: _edit);
    setState(() {
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
        _export = null;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _export != null;
    return Scaffold(
      appBar: AppBar(title: const Text('filmkit')),
      body: _videos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownMenu<String>(
                  label: const Text('Video'),
                  initialSelection: _video,
                  enabled: !busy,
                  dropdownMenuEntries: [for (final v in sampleVideos) DropdownMenuEntry(value: v, label: v)],
                  onSelected: (v) {
                    setState(() {
                      _video = v!;
                      _inputInfo = null;
                    });
                    _loadInfo();
                  },
                ),
                const SizedBox(height: 8),
                Text(_inputInfo?.toString() ?? '…'),
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
                    OutlinedButton(onPressed: busy ? _export!.cancel : null, child: const Text('Cancel')),
                  ],
                ),
                const SizedBox(height: 16),
                if (busy) LinearProgressIndicator(value: _progress),
                if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
              ],
            ),
    );
  }
}
