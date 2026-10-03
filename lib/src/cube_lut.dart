import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A 3D color lookup table, as stored in `.cube` files (Adobe / Resolve format).
///
/// The same table drives the preview ([LutFilter], a shader) and the native export, which
/// both interpolate it trilinearly in the encoded (non-linear) color values, as [apply] does.
@immutable
class CubeLut {
  /// [data] holds `size`³ RGB triplets in 0..1, red varying fastest, then green, then blue.
  CubeLut(this.size, this.data, {this.title}) {
    if (size < 2 || size > 256) throw ArgumentError.value(size, 'size', 'must be in 2..256');
    if (data.length != size * size * size * 3) throw ArgumentError.value(data.length, 'data.length', 'must be size³ × 3');
  }

  /// The table that leaves colors unchanged.
  factory CubeLut.identity([int size = 33]) => CubeLut.generate(size, (r, g, b) => (r, g, b));

  /// Samples [transform] on a `size`³ grid; inputs and outputs are in 0..1.
  factory CubeLut.generate(int size, (double, double, double) Function(double r, double g, double b) transform) {
    final data = Float32List(size * size * size * 3);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final (outR, outG, outB) = transform(r / (size - 1), g / (size - 1), b / (size - 1));
          data[i++] = outR.clamp(0, 1);
          data[i++] = outG.clamp(0, 1);
          data[i++] = outB.clamp(0, 1);
        }
      }
    }
    return CubeLut(size, data);
  }

  /// Parses a `.cube` file's content. Throws a [FormatException] for 1D LUTs, input domains
  /// other than 0..1, or a wrong number of entries.
  factory CubeLut.parse(String source) {
    int? size;
    String? title;
    Float32List? data;
    var count = 0;
    var lineNumber = 0;
    for (final rawLine in const LineSplitter().convert(source)) {
      lineNumber++;
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts.first) {
        case 'TITLE':
          title = line.substring(5).trim().replaceAll('"', '');
        case 'LUT_3D_SIZE':
          size = int.tryParse(parts.length > 1 ? parts[1] : '');
          if (size == null || size < 2 || size > 256) throw FormatException('Invalid LUT_3D_SIZE', line, lineNumber);
          data = Float32List(size * size * size * 3);
        case 'LUT_1D_SIZE':
          throw FormatException('1D LUTs are not supported', line, lineNumber);
        case 'DOMAIN_MIN' || 'DOMAIN_MAX':
          final expected = parts.first == 'DOMAIN_MIN' ? 0.0 : 1.0;
          if (parts.skip(1).any((v) => double.tryParse(v) != expected)) {
            throw FormatException('Only the 0..1 input domain is supported', line, lineNumber);
          }
        default:
          final values = parts.length == 3 ? parts.map(double.tryParse).toList() : null;
          if (values == null || values.contains(null)) throw FormatException('Unexpected line', line, lineNumber);
          if (data == null) throw FormatException('Data before LUT_3D_SIZE', line, lineNumber);
          if (count == data.length) throw FormatException('More entries than LUT_3D_SIZE³', line, lineNumber);
          for (final v in values) {
            data[count++] = v!.clamp(0, 1);
          }
      }
    }
    if (data == null || size == null) throw const FormatException('Missing LUT_3D_SIZE');
    if (count != data.length) throw FormatException('Expected ${size * size * size} entries, found ${count ~/ 3}');
    return CubeLut(size, data, title: title);
  }

  /// Reads and parses a `.cube` file (in a background isolate).
  static Future<CubeLut> fromFile(String path) async {
    final source = await File(path).readAsString();
    return Isolate.run(() => CubeLut.parse(source));
  }

  /// Number of entries per axis.
  final int size;

  /// RGB triplets, red varying fastest.
  final Float32List data;

  /// The `TITLE` of the `.cube` file, if any.
  final String? title;

  /// The table as `.cube` file content, readable by [CubeLut.parse] and color grading tools.
  String encode() {
    final buffer = StringBuffer();
    if (title != null) buffer.writeln('TITLE "$title"');
    buffer.writeln('LUT_3D_SIZE $size');
    for (var i = 0; i < data.length; i += 3) {
      buffer.writeln('${data[i].toStringAsFixed(6)} ${data[i + 1].toStringAsFixed(6)} ${data[i + 2].toStringAsFixed(6)}');
    }
    return buffer.toString();
  }

  /// The table blended with the identity: `intensity` 0 leaves colors unchanged, 1 is this
  /// table. Same result as blending the source and graded colors, since interpolation is
  /// linear.
  CubeLut withIntensity(double intensity) {
    if (intensity >= 1) return this;
    final identity = CubeLut.identity(size).data;
    final t = intensity.clamp(0.0, 1.0);
    return CubeLut(size, Float32List.fromList([for (var i = 0; i < data.length; i++) identity[i] + (data[i] - identity[i]) * t]), title: title);
  }

  /// Applies the table to a color in 0..1 (trilinear interpolation): the CPU reference of the
  /// preview shader and the native exports.
  (double, double, double) apply(double r, double g, double b) {
    final n = size - 1;
    final pr = r.clamp(0.0, 1.0) * n, pg = g.clamp(0.0, 1.0) * n, pb = b.clamp(0.0, 1.0) * n;
    final r0 = pr.floor(), g0 = pg.floor(), b0 = pb.floor();
    final r1 = math.min(r0 + 1, n), g1 = math.min(g0 + 1, n), b1 = math.min(b0 + 1, n);
    final fr = pr - r0, fg = pg - g0, fb = pb - b0;
    double channel(int c) {
      double at(int r, int g, int b) => data[((b * size + g) * size + r) * 3 + c];
      double lerp(double a, double b, double t) => a + (b - a) * t;
      final c00 = lerp(at(r0, g0, b0), at(r1, g0, b0), fr);
      final c10 = lerp(at(r0, g1, b0), at(r1, g1, b0), fr);
      final c01 = lerp(at(r0, g0, b1), at(r1, g0, b1), fr);
      final c11 = lerp(at(r0, g1, b1), at(r1, g1, b1), fr);
      return lerp(lerp(c00, c10, fg), lerp(c01, c11, fg), fb);
    }

    return (channel(0), channel(1), channel(2));
  }

  /// The table as the preview shader's texture: a strip of width `size`², height `size`,
  /// texel (r + b × size, g), 8 bits per channel.
  Future<ui.Image> toTexture() async {
    final bytes = Uint8List(size * size * size * 4);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final o = (g * size * size + r + b * size) * 4;
          bytes[o] = (data[i++] * 255).round();
          bytes[o + 1] = (data[i++] * 255).round();
          bytes[o + 2] = (data[i++] * 255).round();
          bytes[o + 3] = 255;
        }
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: size * size, height: size, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return image;
  }

  @override
  String toString() => 'CubeLut(${title ?? 'untitled'}, size: $size)';
}
