import 'dart:io';
import 'dart:ui';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_example/sample_videos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> videos;
  late Directory out;

  setUpAll(() async {
    videos = await copySampleVideos();
    out = await Directory('${Directory.systemTemp.path}/filmkit_test_out').create(recursive: true);
  });

  /// Durations differ slightly between containers and encoders (audio priming, last frame).
  Matcher about(Duration expected) => predicate<Duration>((d) => (d - expected).abs() < const Duration(milliseconds: 200), 'about $expected');

  group('getVideoInfo', () {
    testWidgets('reads displayed size, duration, audio and HDR', (_) async {
      final landscape = await Filmkit.getVideoInfo(videos['landscape.mp4']!);
      expect((landscape.width, landscape.height), (640, 360));
      expect(landscape.duration, about(const Duration(seconds: 6)));
      expect(landscape.hasAudio, isTrue);
      expect(landscape.isHdr, isFalse);

      final portrait = await Filmkit.getVideoInfo(videos['portrait_noaudio.mp4']!);
      expect((portrait.width, portrait.height), (360, 640), reason: 'rotation tag applied');
      expect(portrait.hasAudio, isFalse);

      final hdr = await Filmkit.getVideoInfo(videos['hdr10.mp4']!);
      expect(hdr.isHdr, isTrue);
    });

    testWidgets('fails with invalidInput on a missing file', (_) async {
      await expectLater(
        Filmkit.getVideoInfo('${out.path}/missing.mp4'),
        throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.invalidInput)),
      );
    });
  });

  group('exportVideo', () {
    testWidgets('trims, crops and resizes', (_) async {
      final output = '${out.path}/landscape_edit.mp4';
      final export = Filmkit.exportVideo(
        input: videos['landscape.mp4']!,
        output: output,
        edit: const EditSpec(
          trimStart: Duration(seconds: 1),
          trimEnd: Duration(seconds: 4),
          crop: Rect.fromLTRB(0.25, 0, 1, 0.75),
          maxDimension: 360,
        ),
      );
      final progress = <double>[];
      final progressDone = export.progress.listen(progress.add).asFuture<void>();

      final result = await export.result;
      await progressDone;
      expect(result.path, output);
      expect((result.width, result.height), (360, 202));
      expect(progress, everyElement(inInclusiveRange(0, 1)));

      final info = await Filmkit.getVideoInfo(output);
      expect((info.width, info.height), (360, 202));
      expect(info.duration, about(const Duration(seconds: 3)));
      expect(info.hasAudio, isTrue);
    });

    testWidgets('keeps the source as is without edits', (_) async {
      final result = await Filmkit.exportVideo(input: videos['landscape.mp4']!, output: '${out.path}/landscape_copy.mp4').result;
      expect((result.width, result.height), (640, 360));
      final info = await Filmkit.getVideoInfo(result.path);
      expect(info.duration, about(const Duration(seconds: 6)));
    });

    testWidgets('crops rotated videos in displayed coordinates', (_) async {
      final result = await Filmkit.exportVideo(
        input: videos['portrait_noaudio.mp4']!,
        output: '${out.path}/portrait_edit.mp4',
        edit: const EditSpec(crop: Rect.fromLTRB(0, 0, 0.5, 1), maxDimension: 320),
      ).result;
      expect((result.width, result.height), (90, 320));
      final info = await Filmkit.getVideoInfo(result.path);
      expect((info.width, info.height), (90, 320));
      expect(info.hasAudio, isFalse);
      expect(info.duration, about(const Duration(seconds: 4)));
    });

    testWidgets('converts HDR to SDR, or reports hdrUnsupported', (_) async {
      try {
        final result = await Filmkit.exportVideo(input: videos['hdr10.mp4']!, output: '${out.path}/hdr_sdr.mp4').result;
        final info = await Filmkit.getVideoInfo(result.path);
        expect(info.isHdr, isFalse);
        debugPrint('HDR export: converted to SDR');
      } on FilmkitException catch (e) {
        debugPrint('HDR export: ${e.message}');
        // Devices without 10-bit GL or MediaCodec tone mapping, e.g. the Android emulator.
        expect(e.code, FilmkitErrorCode.hdrUnsupported, reason: e.message);
      }
    });

    testWidgets('runs several exports at once', (_) async {
      final results = await Future.wait([
        Filmkit.exportVideo(input: videos['landscape.mp4']!, output: '${out.path}/a.mp4', edit: const EditSpec(maxDimension: 320)).result,
        Filmkit.exportVideo(input: videos['portrait_noaudio.mp4']!, output: '${out.path}/b.mp4', edit: const EditSpec(maxDimension: 320)).result,
      ]);
      expect(results.map((r) => (r.width, r.height)), [(320, 180), (180, 320)]);
    });

    testWidgets('cancel stops the export and deletes the output', (_) async {
      final output = '${out.path}/cancelled.mp4';
      final export = Filmkit.exportVideo(input: videos['landscape.mp4']!, output: output);
      await export.cancel();
      await expectLater(export.result, throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.cancelled)));
      expect(File(output).existsSync(), isFalse);
    });

    testWidgets('fails with invalidInput when the trim starts after the end', (_) async {
      final export = Filmkit.exportVideo(
        input: videos['landscape.mp4']!,
        output: '${out.path}/late.mp4',
        edit: const EditSpec(trimStart: Duration(seconds: 10)),
      );
      await expectLater(export.result, throwsA(isA<FilmkitException>().having((e) => e.code, 'code', FilmkitErrorCode.invalidInput)));
    });
  });
}
