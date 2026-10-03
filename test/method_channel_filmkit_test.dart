import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  // Completes when native code receives `exportVideo`.
  late Completer<void> exportCalled;

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
    exportCalled = Completer();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'exportVideo':
          exportCalled.complete();
          return nativeExport.future;
        case 'exportImage':
          return {'path': '/out.jpg', 'width': 150, 'height': 200};
        case 'getVideoFrame':
          return {
            'width': 2,
            'height': 1,
            'rgba': Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]),
          };
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
      'lut': null,
      'lutIntensity': 1.0,
    });
    expect(args['lut'], isNull);

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

  group('LUT', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('filmkit_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String writeCube(String content) => (File('${dir.path}/look.cube')..writeAsStringSync(content)).path;

    test('exportVideo sends the parsed table, blended for the intensity', () async {
      final path = writeCube('LUT_3D_SIZE 2\n${List.filled(8, '1 0 0').join('\n')}\n');
      final export = platform.exportVideo(
        input: '/in.mp4',
        output: '/out.mp4',
        edit: EditSpec(lut: path, lutIntensity: 0.5),
      );
      await exportCalled.future;
      final lut = (calls.single.arguments as Map)['lut'] as Map;
      expect(lut['size'], 2);
      // Entry (r=0, g=0, b=0): halfway between black and red.
      expect((lut['data'] as Float32List).sublist(0, 3), [0.5, 0, 0]);
      expect((calls.single.arguments as Map)['edit']['lut'], path);
      nativeExport.complete({'path': '/out.mp4', 'width': 2, 'height': 2});
      await export.result;
    });

    test('a missing or invalid LUT fails with invalidInput without calling native code', () async {
      final invalid = writeCube('LUT_3D_SIZE 2\n0 0 0\n');
      for (final path in ['${dir.path}/missing.cube', invalid]) {
        final export = platform.exportVideo(
          input: '/in.mp4',
          output: '/out.mp4',
          edit: EditSpec(lut: path),
        );
        await expectLater(export.result, throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.invalidInput)));
      }
      expect(calls, isEmpty);
    });

    test('cancel while the LUT loads never starts the native export', () async {
      final path = writeCube('LUT_3D_SIZE 2\n${List.filled(8, '0 0 0').join('\n')}\n');
      final export = platform.exportVideo(
        input: '/in.mp4',
        output: '/out.mp4',
        edit: EditSpec(lut: path),
      );
      await export.cancel();
      await expectLater(export.result, throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.cancelled)));
      expect(calls.map((c) => c.method), ['cancelExport']);
    });
  });

  test('getVideoFrame returns the native pixels as an image', () async {
    final image = await platform.getVideoFrame('/in.mp4', position: const Duration(milliseconds: 1500), maxDimension: 320);
    expect((image.width, image.height), (2, 1));
    expect(calls.single.arguments, {'path': '/in.mp4', 'positionMs': 1500, 'maxDimension': 320});
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    expect(bytes, [255, 0, 0, 255, 0, 0, 255, 255]);
    image.dispose();
  });

  group('exportImage', () {
    test('sends the spec, quality and location choice', () async {
      final result = await platform.exportImage(
        input: '/in.heic',
        output: '/out.jpg',
        edit: const EditSpec(crop: Rect.fromLTRB(0, 0, 0.5, 1)),
        quality: 85,
        keepLocation: true,
      );
      expect((result.path, result.width, result.height), ('/out.jpg', 150, 200));
      final args = calls.single.arguments as Map;
      expect(args['input'], '/in.heic');
      expect(args['quality'], 85);
      expect(args['keepLocation'], isTrue);
      expect(args['lut'], isNull);
      expect((args['edit'] as Map)['crop'], [0.0, 0.0, 0.5, 1.0]);
    });

    test('validates its arguments before calling native code', () async {
      await expectLater(platform.exportImage(input: '/a.jpg', output: '/b.jpg', edit: const EditSpec(), quality: 0, keepLocation: false), throwsArgumentError);
      await expectLater(platform.exportImage(input: '/a.jpg', output: '/a.jpg', edit: const EditSpec(), quality: 90, keepLocation: false), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('maps native errors to FilmkitException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'invalidInput', message: 'Not a supported image'));
      await expectLater(
        platform.exportImage(input: '/a.txt', output: '/b.jpg', edit: const EditSpec(), quality: 90, keepLocation: false),
        throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.invalidInput)),
      );
    });
  });
}
