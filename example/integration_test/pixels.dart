import 'dart:io';
import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decodes an image file (EXIF orientation applied) into pixels.
Future<Rgba> decodeFile(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return Rgba.fromImage(frame.image);
}

String colorName((int, int, int) c) {
  final (r, g, b) = c;
  if (r > 180 && g < 90 && b < 90) return 'red';
  if (g > 180 && r < 90 && b < 90) return 'green';
  if (b > 180 && r < 90 && g < 90) return 'blue';
  if (r > 180 && g > 180 && b > 180) return 'white';
  return 'rgb($r, $g, $b)';
}

/// Opaque RGBA8 pixels.
class Rgba {
  Rgba(this.width, this.height, this.bytes);

  static Future<Rgba> fromImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = Rgba(image.width, image.height, data!.buffer.asUint8List());
    image.dispose();
    return rgba;
  }

  final int width;
  final int height;
  final Uint8List bytes;

  (int, int, int) pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  Rgba graded(CubeLut lut) {
    final graded = Uint8List.fromList(bytes);
    for (var i = 0; i < bytes.length; i += 4) {
      final (r, g, b) = lut.apply(bytes[i] / 255, bytes[i + 1] / 255, bytes[i + 2] / 255);
      graded[i] = (r * 255).round();
      graded[i + 1] = (g * 255).round();
      graded[i + 2] = (b * 255).round();
    }
    return Rgba(width, height, graded);
  }

  Future<ui.Image> toImage() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
    return (await (await descriptor.instantiateCodec()).getNextFrame()).image;
  }
}

/// Per-channel absolute differences (0..255), ignoring an 8 px border (encoder edge effects).
class Diff {
  Diff(this.mean, this.p99, this.max);

  factory Diff.of(Rgba a, Rgba b) {
    expect((a.width, a.height), (b.width, b.height));
    const border = 8;
    final diffs = <int>[];
    for (var y = border; y < a.height - border; y++) {
      for (var x = border; x < a.width - border; x++) {
        final i = (y * a.width + x) * 4;
        for (var k = 0; k < 3; k++) {
          diffs.add((a.bytes[i + k] - b.bytes[i + k]).abs());
        }
      }
    }
    diffs.sort();
    return Diff(diffs.reduce((s, v) => s + v) / diffs.length, diffs[(diffs.length * 0.99).floor()], diffs.last);
  }

  final double mean;
  final int p99;
  final int max;

  @override
  String toString() => 'mean ${mean.toStringAsFixed(2)} p99 $p99 max $max';
}
