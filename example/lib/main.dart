// LUT parity spike: compares the same 3D LUT applied by
// - a CPU reference (trilinear interpolation in Dart),
// - the Flutter shader used for the live preview,
// - Media3 Transformer's SingleColorLut (the Android export pipeline).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int width = 512;
const int height = 512;
const int lutSize = 33;

/// Pixels this close to the border are ignored by the measurements (encoder edge effects).
const int border = 8;

const MethodChannel channel = MethodChannel('filmkit');

void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final List<String> _lines = [];
  final Map<String, Uint8List> _images = {};
  bool _running = false;

  void _log(String line) {
    debugPrint('[spike] $line');
    setState(() => _lines.add(line));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lines.clear();
      _images.clear();
    });

    try {
      final source = makeSource();
      final identityLut = makeLut((r, g, b) => [r, g, b]);
      final lookLut = makeLut(look);

      final cpuLook = applyLutCpu(source, lookLut);

      final shaderIdentity = await applyLutShader(source, identityLut);
      final shaderLook = await applyLutShader(source, lookLut);

      final dir = Directory.systemTemp.path;
      final sourcePath = '$dir/spike_source.png';
      await File(sourcePath).writeAsBytes(await encodePng(source));

      final media3Plain = await exportWithMedia3(sourcePath, '$dir/spike_plain.mp4', null);
      final media3Look = await exportWithMedia3(sourcePath, '$dir/spike_look.mp4', lookLut);

      _log('A. shader (identity LUT) vs source:  ${compare(shaderIdentity, source)}');
      _log('B. shader (look) vs CPU reference:     ${compare(shaderLook, cpuLook)}');
      _log('C. Media3 (no LUT) vs source:          ${compare(media3Plain, source)}');
      _log('D. Media3 (look) vs CPU reference:     ${compare(media3Look, cpuLook)}');
      _log('E. Media3 (look) vs shader (look):     ${compare(media3Look, shaderLook)}');
      _log('F. shader (look) vs source (LUT effect size): ${compare(shaderLook, source)}');

      for (final entry in {
        'source': source,
        'CPU look': cpuLook,
        'shader look': shaderLook,
        'Media3 look': media3Look,
      }.entries) {
        _images[entry.key] = await encodePng(entry.value);
      }
      _log('done');
    } catch (e, s) {
      _log('ERROR $e\n$s');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LUT parity spike')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton(onPressed: _running ? null : _run, child: Text(_running ? 'Running…' : 'Run')),
          const SizedBox(height: 12),
          for (final line in _lines) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _images.entries)
                Column(children: [Image.memory(entry.value, width: 170, height: 170), Text(entry.key)]),
            ],
          ),
        ],
      ),
    );
  }
}

/// An RGBA8 image.
class Rgba {
  Rgba(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;
}

/// Smooth gradients (red along x, green along y, blue as a slow wave), to limit chroma
/// subsampling and compression artifacts in the video export.
Rgba makeSource() {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final b = 0.5 + 0.45 * math.sin(2 * math.pi * (x + 2 * y) / (width + 2 * height) * 1.5);
      bytes[i] = (x / (width - 1) * 255).round();
      bytes[i + 1] = (y / (height - 1) * 255).round();
      bytes[i + 2] = (b * 255).round();
      bytes[i + 3] = 255;
    }
  }
  return Rgba(width, height, bytes);
}

/// A "film" look: S-curve contrast, warm tint, more saturation.
List<double> look(double r, double g, double b) {
  double curve(double x) => x + 0.6 * (x * x * (3 - 2 * x) - x);
  var c = [curve(r) * 1.06, curve(g) * 1.0, curve(b) * 0.9];
  final luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  c = [for (final v in c) luma + 1.3 * (v - luma)];
  return [for (final v in c) v.clamp(0.0, 1.0)];
}

/// A LUT quantized to 8 bits, as `lut[(r * N + g) * N + b]` = [r, g, b] in 0..255.
List<List<int>> makeLut(List<double> Function(double r, double g, double b) transform) {
  final n = lutSize;
  return [
    for (var r = 0; r < n; r++)
      for (var g = 0; g < n; g++)
        for (var b = 0; b < n; b++) [for (final v in transform(r / (n - 1), g / (n - 1), b / (n - 1))) (v * 255).round()],
  ];
}

/// CPU reference: trilinear interpolation of the 8-bit LUT, in sRGB-encoded values.
Rgba applyLutCpu(Rgba src, List<List<int>> lut) {
  final n = lutSize;
  final out = Uint8List(src.bytes.length);
  for (var i = 0; i < src.bytes.length; i += 4) {
    final p = [for (var k = 0; k < 3; k++) src.bytes[i + k] / 255 * (n - 1)];
    final i0 = [for (final v in p) v.floor()];
    final i1 = [for (final v in i0) math.min(v + 1, n - 1)];
    final f = [for (var k = 0; k < 3; k++) p[k] - i0[k]];
    for (var k = 0; k < 3; k++) {
      double at(int r, int g, int b) => lut[(r * n + g) * n + b][k] / 255;
      double lerp(double a, double b, double t) => a + (b - a) * t;
      final c00 = lerp(at(i0[0], i0[1], i0[2]), at(i1[0], i0[1], i0[2]), f[0]);
      final c10 = lerp(at(i0[0], i1[1], i0[2]), at(i1[0], i1[1], i0[2]), f[0]);
      final c01 = lerp(at(i0[0], i0[1], i1[2]), at(i1[0], i0[1], i1[2]), f[0]);
      final c11 = lerp(at(i0[0], i1[1], i1[2]), at(i1[0], i1[1], i1[2]), f[0]);
      out[i + k] = (lerp(lerp(c00, c10, f[1]), lerp(c01, c11, f[1]), f[2]) * 255).round();
    }
    out[i + 3] = 255;
  }
  return Rgba(src.width, src.height, out);
}

Future<ui.Image> toUiImage(Rgba image) => decodeImage(image.bytes, image.width, image.height);

Future<ui.Image> decodeImage(Uint8List rgba, int w, int h) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

/// The LUT as a strip texture: width N*N, height N, texel (r + b * N, g).
Future<ui.Image> lutTexture(List<List<int>> lut) {
  final n = lutSize;
  final bytes = Uint8List(n * n * n * 4);
  for (var r = 0; r < n; r++) {
    for (var g = 0; g < n; g++) {
      for (var b = 0; b < n; b++) {
        final c = lut[(r * n + g) * n + b];
        final i = (g * n * n + (r + b * n)) * 4;
        bytes[i] = c[0];
        bytes[i + 1] = c[1];
        bytes[i + 2] = c[2];
        bytes[i + 3] = 255;
      }
    }
  }
  return decodeImage(bytes, n * n, n);
}

Future<Rgba> applyLutShader(Rgba src, List<List<int>> lut) async {
  final program = await ui.FragmentProgram.fromAsset('packages/filmkit/shaders/lut.frag');
  final shader = program.fragmentShader()
    ..setFloat(0, src.width.toDouble())
    ..setFloat(1, src.height.toDouble())
    ..setFloat(2, lutSize.toDouble())
    ..setImageSampler(0, await toUiImage(src))
    ..setImageSampler(1, await lutTexture(lut));

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final image = await recorder.endRecording().toImage(src.width, src.height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return Rgba(src.width, src.height, data!.buffer.asUint8List());
}

Future<Uint8List> encodePng(Rgba image) async {
  final data = await (await toUiImage(image)).toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Rgba> exportWithMedia3(String input, String output, List<List<int>>? lut) async {
  await channel.invokeMethod<String>('exportImageToVideo', {
    'input': input,
    'output': output,
    if (lut != null) 'lutSize': lutSize,
    if (lut != null) 'lut': Int32List.fromList([for (final c in lut) (0xFF << 24) | (c[0] << 16) | (c[1] << 8) | c[2]]),
  });
  final frame = (await channel.invokeMapMethod<String, Object?>('extractFrame', {'path': output}))!;
  return Rgba(frame['width'] as int, frame['height'] as int, frame['rgba'] as Uint8List);
}

/// Per-channel absolute differences over the inner pixels: mean, p95, p99 and max (0..255).
String compare(Rgba a, Rgba b) {
  if (a.width != b.width || a.height != b.height) {
    return 'size mismatch ${a.width}x${a.height} vs ${b.width}x${b.height}';
  }
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
  final mean = diffs.reduce((s, v) => s + v) / diffs.length;
  int pct(double p) => diffs[((diffs.length - 1) * p).round()];
  return 'mean ${mean.toStringAsFixed(2)}  p95 ${pct(0.95)}  p99 ${pct(0.99)}  max ${diffs.last}';
}
