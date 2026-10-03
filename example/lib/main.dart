import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';

import 'sample_videos.dart';

void main() => runApp(const MaterialApp(home: ExportDemoPage()));

/// Exports a bundled sample video with a few edit presets.
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

  VideoExport? _export;
  double _progress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    copySampleVideos().then((videos) {
      setState(() => _videos = videos);
      _loadInfo();
    });
  }

  Future<void> _loadInfo() async {
    final info = await Filmkit.getVideoInfo(_videos![_video]!);
    if (mounted) setState(() => _inputInfo = info);
  }

  Future<void> _run() async {
    final input = _videos![_video]!;
    final output = '${Directory.systemTemp.path}/filmkit_demo_${_video.replaceAll('.mp4', '')}.mp4';
    final export = Filmkit.exportVideo(input: input, output: output, edit: _presets[_preset]!);
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
