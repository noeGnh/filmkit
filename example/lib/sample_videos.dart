import 'dart:io';

import 'package:flutter/services.dart';

/// Test videos bundled in `assets/videos`: four colored quadrants (red top left, green top
/// right, blue bottom left, white bottom right) and a central gray band that brightens over
/// time. `gradient.mp4` is a still 320×320 gradient covering many colors (red along x, green
/// along y, blue as a wave), BT.709, for color tests.
const sampleVideos = ['landscape.mp4', 'portrait_noaudio.mp4', 'hdr10.mp4', 'gradient.mp4'];

/// Test photos bundled in `assets/photos`: `gradient.jpg` (640×480, as the gradient video,
/// no metadata) and its HEIC conversion, and `oriented_<1-8>.jpg`, the quadrant pattern
/// displayed at 300×200 but stored for each EXIF orientation, with the make `FilmkitCam`, the
/// capture date `2024:05:06 07:08:09` and a GPS location whose map datum is `FILMKITDATUM`.
final samplePhotos = ['gradient.jpg', 'gradient.heic', for (var o = 1; o <= 8; o++) 'oriented_$o.jpg'];

/// Copies the bundled videos to a temporary directory (native exporters read files) and
/// returns their paths by name.
Future<Map<String, String>> copySampleVideos() => _copyAll('videos', sampleVideos);

/// Copies the bundled photos to a temporary directory and returns their paths by name.
Future<Map<String, String>> copySamplePhotos() => _copyAll('photos', samplePhotos);

Future<Map<String, String>> _copyAll(String folder, List<String> names) async {
  final dir = await Directory('${Directory.systemTemp.path}/filmkit_samples').create(recursive: true);
  return {
    for (final name in names) name: await _copy('$folder/$name', dir),
  };
}

Future<String> _copy(String asset, Directory dir) async {
  final file = File('${dir.path}/${asset.split('/').last}');
  final data = await rootBundle.load('assets/$asset');
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  return file.path;
}
