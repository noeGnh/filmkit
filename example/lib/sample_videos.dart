import 'dart:io';

import 'package:flutter/services.dart';

/// Test videos bundled in `assets/videos`: four colored quadrants (red top left, green top
/// right, blue bottom left, white bottom right) and a central gray band that brightens over
/// time. `gradient.mp4` is a still 320×320 gradient covering many colors (red along x, green
/// along y, blue as a wave), BT.709, for color tests.
const sampleVideos = ['landscape.mp4', 'portrait_noaudio.mp4', 'hdr10.mp4', 'gradient.mp4'];

/// Copies the bundled videos to a temporary directory (native exporters read files) and
/// returns their paths by name.
Future<Map<String, String>> copySampleVideos() async {
  final dir = await Directory('${Directory.systemTemp.path}/filmkit_samples').create(recursive: true);
  return {
    for (final name in sampleVideos) name: await _copy(name, dir),
  };
}

Future<String> _copy(String name, Directory dir) async {
  final file = File('${dir.path}/$name');
  final data = await rootBundle.load('assets/videos/$name');
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  return file.path;
}
