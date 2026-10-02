import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    final result = methodChannel
        .invokeMapMethod<String, Object?>('exportVideo', {
          'id': id,
          'input': input,
          'output': output,
          'edit': edit.toJson(),
        })
        .then((map) => ExportResult.fromMap(map!))
        .onError<PlatformException>((e, stack) => Error.throwWithStackTrace(FilmkitException.fromPlatform(e), stack))
        .whenComplete(() {
          _progress.remove(id);
          controller.close();
        });
    return VideoExport(
      progress: controller.stream,
      result: result,
      cancel: () => methodChannel.invokeMethod<void>('cancelExport', {'id': id}),
    );
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

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onProgress') return;
    final args = (call.arguments as Map<Object?, Object?>).cast<String, Object?>();
    final controller = _progress[args['id']];
    if (controller != null && !controller.isClosed) {
      controller.add((args['progress']! as num).toDouble().clamp(0, 1));
    }
  }
}
