import 'dart:async';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit/src/method_channel_filmkit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('filmkit');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelFilmkit platform;
  late List<MethodCall> calls;
  // Lets a test finish the native export call when it wants.
  late Completer<Object?> nativeExport;

  /// Simulates a native `onProgress` call.
  Future<void> sendProgress(String id, num progress) => messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(MethodCall('onProgress', {'id': id, 'progress': progress})),
    (_) {},
  );

  setUp(() {
    platform = MethodChannelFilmkit();
    calls = [];
    nativeExport = Completer();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'exportVideo':
          return nativeExport.future;
        case 'getVideoInfo':
          return {'width': 360, 'height': 640, 'durationMs': 6000, 'hasAudio': true, 'isHdr': false};
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('exportVideo sends the spec, reports progress and returns the result', () async {
    final export = platform.exportVideo(
      input: '/in.mp4',
      output: '/out.mp4',
      edit: const EditSpec(trimEnd: Duration(seconds: 3), crop: Rect.fromLTRB(0, 0, 0.5, 1)),
    );
    final progress = <double>[];
    final done = export.progress.listen(progress.add).asFuture<void>();
    await pumpEventQueue();

    expect(calls.single.method, 'exportVideo');
    final args = calls.single.arguments as Map;
    expect(args['input'], '/in.mp4');
    expect(args['output'], '/out.mp4');
    expect(args['edit'], {
      'trimStartMs': 0,
      'trimEndMs': 3000,
      'crop': [0.0, 0.0, 0.5, 1.0],
      'maxDimension': null,
    });

    final id = args['id'] as String;
    await sendProgress(id, 0.25);
    await sendProgress('other', 0.9);
    await sendProgress(id, 1.2);
    nativeExport.complete({'path': '/out.mp4', 'width': 320, 'height': 360});

    final result = await export.result;
    expect(result.path, '/out.mp4');
    expect((result.width, result.height), (320, 360));
    await done;
    expect(progress, [0.25, 1.0]);
  });

  test('exportVideo maps native errors to FilmkitException', () async {
    final export = platform.exportVideo(input: '/in.mp4', output: '/out.mp4', edit: const EditSpec());
    await pumpEventQueue();
    nativeExport.completeError(PlatformException(code: 'cancelled', message: 'Export cancelled'));
    await expectLater(
      export.result,
      throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.cancelled)),
    );
  });

  test('unknown native error codes map to unknown', () {
    final e = FilmkitException.fromPlatform(PlatformException(code: 'weird'));
    expect(e.code, FilmkitErrorCode.unknown);
    expect(e.message, 'weird');
  });

  test('cancel calls cancelExport with the export id', () async {
    final export = platform.exportVideo(input: '/in.mp4', output: '/out.mp4', edit: const EditSpec());
    await export.cancel();
    expect(calls.map((c) => c.method), ['exportVideo', 'cancelExport']);
    expect((calls.last.arguments as Map)['id'], (calls.first.arguments as Map)['id']);
    nativeExport.complete({'path': '/out.mp4', 'width': 2, 'height': 2});
    await export.result;
  });

  test('the cancellation error is not uncaught when result is awaited after cancel', () async {
    final export = platform.exportVideo(input: '/in.mp4', output: '/out.mp4', edit: const EditSpec());
    final cancelled = export.cancel();
    nativeExport.completeError(PlatformException(code: 'cancelled'));
    await cancelled;
    await pumpEventQueue();
    await expectLater(export.result, throwsA(isA<FilmkitException>()));
  });

  test('exportVideo validates its arguments before calling native code', () {
    expect(
      () => platform.exportVideo(input: '/a.mp4', output: '/b.mp4', edit: const EditSpec(maxDimension: 0)),
      throwsArgumentError,
    );
    expect(() => platform.exportVideo(input: '/a.mp4', output: '/a.mp4', edit: const EditSpec()), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test('getVideoInfo parses the native map', () async {
    final info = await platform.getVideoInfo('/in.mp4');
    expect((info.width, info.height), (360, 640));
    expect(info.duration, const Duration(seconds: 6));
    expect(info.hasAudio, isTrue);
    expect(info.isHdr, isFalse);
    expect((calls.single.arguments as Map)['path'], '/in.mp4');
  });
}
