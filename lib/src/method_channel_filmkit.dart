import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cube_lut.dart';
import 'edit_spec.dart';
import 'exceptions.dart';
import 'filmkit_platform.dart';
import 'video_export.dart';
import 'video_info.dart';

/// [FilmkitPlatform] over the `filmkit` method channel.
///
/// Native code reports progress by calling `onProgress` with `{id, progress}` on the same
/// channel.
class MethodChannelFilmkit extends FilmkitPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('filmkit');

  final Map<String, StreamController<double>> _progress = {};
  int _nextId = 0;
  bool _listening = false;

  @override
  VideoExport exportVideo({required String input, required String output, required EditSpec edit}) {
    edit.validate();
    if (input == output) throw ArgumentError.value(output, 'output', 'must differ from input');
    // Set lazily: the binary messenger needs the Flutter binding.
    if (!_listening) {
      methodChannel.setMethodCallHandler(_handleCall);
      _listening = true;
    }

    final id = '${_nextId++}';
    final controller = StreamController<double>.broadcast();
    _progress[id] = controller;
    var cancelled = false;

    Future<ExportResult> run() async {
      final lut = edit.lut == null ? null : await _loadLut(edit.lut!, edit.lutIntensity);
      // Cancelled while the LUT was loading: native code never saw this export.
      if (cancelled) throw const FilmkitException(FilmkitErrorCode.cancelled, 'Export cancelled');
      try {
        final map = await methodChannel.invokeMapMethod<String, Object?>('exportVideo', {
          'id': id,
          'input': input,
          'output': output,
          'edit': edit.toJson(),
          'lut': lut == null ? null : {'size': lut.size, 'data': lut.data},
        });
        return ExportResult.fromMap(map!);
      } on PlatformException catch (e, stack) {
        Error.throwWithStackTrace(FilmkitException.fromPlatform(e), stack);
      }
    }

    final result = run().whenComplete(() {
      _progress.remove(id);
      controller.close();
    });
    return VideoExport(
      progress: controller.stream,
      result: result,
      cancel: () {
        cancelled = true;
        return methodChannel.invokeMethod<void>('cancelExport', {'id': id});
      },
    );
  }

  @override
  Future<ExportResult> exportImage({
    required String input,
    required String output,
    required EditSpec edit,
    required int quality,
    required bool keepLocation,
  }) async {
    edit.validate();
    if (input == output) throw ArgumentError.value(output, 'output', 'must differ from input');
    if (quality < 1 || quality > 100) throw ArgumentError.value(quality, 'quality', 'must be in 1..100');
    final lut = edit.lut == null ? null : await _loadLut(edit.lut!, edit.lutIntensity);
    try {
      final map = await methodChannel.invokeMapMethod<String, Object?>('exportImage', {
        'input': input,
        'output': output,
        'edit': edit.toJson(),
        'lut': lut == null ? null : {'size': lut.size, 'data': lut.data},
        'quality': quality,
        'keepLocation': keepLocation,
      });
      return ExportResult.fromMap(map!);
    } on PlatformException catch (e) {
      throw FilmkitException.fromPlatform(e);
    }
  }

  /// Native code gets the parsed table, already blended for [intensity].
  static Future<CubeLut> _loadLut(String path, double intensity) async {
    try {
      return (await CubeLut.fromFile(path)).withIntensity(intensity);
    } on FileSystemException catch (e) {
      throw FilmkitException(FilmkitErrorCode.invalidInput, "Can't read the LUT $path: ${e.message}");
    } on FormatException catch (e) {
      throw FilmkitException(FilmkitErrorCode.invalidInput, 'Invalid LUT $path: ${e.message}');
    }
  }

  @override
  Future<VideoInfo> getVideoInfo(String path) async {
    try {
      final map = await methodChannel.invokeMapMethod<String, Object?>('getVideoInfo', {'path': path});
      return VideoInfo.fromMap(map!);
    } on PlatformException catch (e) {
      throw FilmkitException.fromPlatform(e);
    }
  }

  @override
  Future<ui.Image> getVideoFrame(String path, {Duration position = Duration.zero, int? maxDimension}) async {
    if (maxDimension != null && maxDimension < 1) throw ArgumentError.value(maxDimension, 'maxDimension', 'must be positive');
    final Map<String, Object?> frame;
    try {
      frame = (await methodChannel.invokeMapMethod<String, Object?>('getVideoFrame', {
        'path': path,
        'positionMs': position.inMilliseconds,
        'maxDimension': maxDimension,
      }))!;
    } on PlatformException catch (e) {
      throw FilmkitException.fromPlatform(e);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(frame['rgba']! as Uint8List);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: frame['width']! as int, height: frame['height']! as int, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return image;
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onProgress') return;
    final args = (call.arguments as Map<Object?, Object?>).cast<String, Object?>();
    final controller = _progress[args['id']];
    if (controller != null && !controller.isClosed) {
      controller.add((args['progress']! as num).toDouble().clamp(0, 1));
    }
  }
}
