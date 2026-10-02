// Video export spike: runs the same edit (trim 1.0–4.0 s, crop, resize) on each test video
// with Media3 Transformer. The outputs are checked on the host with ffprobe / ffmpeg.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel channel = MethodChannel('filmkit');

/// Where the host pushes the test videos: the app files directory on Android (`adb shell
/// run-as … cp`), the app container's tmp directory on the iOS simulator.
final String base = Platform.isIOS
    ? '${Directory.systemTemp.path}/spike'
    : '/data/user/0/dev.noegnh.filmkit_example/files/spike';

/// Test videos.
const List<String> inputs = [
  'h264_landscape',
  'hevc_landscape',
  'h264_rot90',
  'h264_rot270',
  'h264_vfr_noaudio',
  'h264_4k60',
  'hevc_hdr10',
];

/// [left, top, right, bottom], normalized, in displayed coordinates.
const List<double> crop = [0.25, 0.0, 1.0, 0.75];

void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final List<String> _lines = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Simulators can't be tapped from the host: --dart-define=AUTORUN=true starts the run.
    if (const bool.fromEnvironment('AUTORUN')) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _log(String line) {
    debugPrint('[spike] $line');
    setState(() => _lines.add(line));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lines.clear();
    });

    for (final name in inputs) {
      try {
        final result = (await channel.invokeMapMethod<String, Object?>('exportVideo', {
          'input': '$base/$name.mp4',
          'output': '$base/out_$name.mp4',
          'startMs': 1000,
          'endMs': 4000,
          'crop': crop,
          'maxDimension': 1080,
        }))!;
        _log('$name: OK ${result['width']}x${result['height']} in ${result['elapsedMs']} ms '
            '(encoder ${result['videoEncoder']})');
      } on PlatformException catch (e) {
        _log('$name: ERROR ${e.message} | ${e.details}');
      }
    }
    _log('done');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video export spike')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton(onPressed: _running ? null : _run, child: Text(_running ? 'Running…' : 'Run')),
          const SizedBox(height: 12),
          for (final line in _lines) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ],
      ),
    );
  }
}
