import 'dart:io';
import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_example/sample_looks.dart';
import 'package:filmkit_example/sample_videos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'pixels.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> photos;
  late Directory out;
  late String lookPath;

  setUpAll(() async {
    photos = await copySamplePhotos();
    out = await Directory('${Directory.systemTemp.path}/filmkit_image_out').create(recursive: true);
    lookPath = '${out.path}/look.cube';
    await File(lookPath).writeAsString(filmLook.encode());
  });

  Matcher hasCode(FilmkitErrorCode code) => throwsA(isA<FilmkitException>().having((e) => e.code, 'code', code));

  testWidgets('applies the EXIF orientation, then the crop in displayed coordinates', (_) async {
    for (var o = 1; o <= 8; o++) {
      final result = await Filmkit.exportImage(
        input: photos['oriented_$o.jpg']!,
        output: '${out.path}/oriented_$o.jpg',
        edit: const EditSpec(crop: ui.Rect.fromLTRB(0, 0, 0.5, 1)),
      );
      expect((result.width, result.height), (150, 200), reason: 'orientation $o');
      final image = await decodeFile(result.path);
      expect((image.width, image.height), (150, 200), reason: 'orientation $o: the output must not keep an orientation tag');
      expect(colorName(image.pixel(75, 50)), 'red', reason: 'orientation $o, top');
      expect(colorName(image.pixel(75, 150)), 'blue', reason: 'orientation $o, bottom');
    }
  });

  testWidgets('scales down to maxDimension, never up', (_) async {
    final small = await Filmkit.exportImage(input: photos['gradient.jpg']!, output: '${out.path}/small.jpg', edit: const EditSpec(maxDimension: 320));
    expect((small.width, small.height), (320, 240));
    final same = await Filmkit.exportImage(input: photos['gradient.jpg']!, output: '${out.path}/same.jpg', edit: const EditSpec(maxDimension: 4000));
    expect((same.width, same.height), (640, 480));
    final image = await decodeFile(small.path);
    expect((image.width, image.height), (320, 240));
  });

  testWidgets('applies the LUT like the CPU reference', (_) async {
    final source = await decodeFile(photos['gradient.jpg']!);
    final plain = await decodeFile((await Filmkit.exportImage(input: photos['gradient.jpg']!, output: '${out.path}/plain.jpg', quality: 100)).path);
    final graded = await decodeFile(
      (await Filmkit.exportImage(
        input: photos['gradient.jpg']!,
        output: '${out.path}/graded.jpg',
        edit: EditSpec(lut: lookPath),
        quality: 100,
      )).path,
    );
    final half = await decodeFile(
      (await Filmkit.exportImage(
        input: photos['gradient.jpg']!,
        output: '${out.path}/half.jpg',
        edit: EditSpec(lut: lookPath, lutIntensity: 0.5),
        quality: 100,
      )).path,
    );

    final effect = Diff.of(source, source.graded(filmLook));
    final codec = Diff.of(plain, source);
    final full = Diff.of(graded, source.graded(filmLook));
    final halfDiff = Diff.of(half, source.graded(filmLook.withIntensity(0.5)));
    debugPrint('photo LUT effect: $effect | JPEG (no LUT): $codec | export vs CPU: $full | 50 %: $halfDiff');
    for (final diff in [codec, full, halfDiff]) {
      expect(diff.mean, lessThan(1.5), reason: '$diff');
      expect(diff.p99, lessThan(6), reason: '$diff');
    }
  });

  testWidgets('keeps the capture metadata, and the location only on request', (_) async {
    Future<String> exifOf(bool keepLocation) async {
      final result = await Filmkit.exportImage(input: photos['oriented_6.jpg']!, output: '${out.path}/meta_$keepLocation.jpg', keepLocation: keepLocation);
      // EXIF strings are stored as ASCII.
      return String.fromCharCodes(await File(result.path).readAsBytes());
    }

    final withoutLocation = await exifOf(false);
    expect(withoutLocation, contains('FilmkitCam'));
    expect(withoutLocation, contains('2024:05:06 07:08:09'));
    expect(withoutLocation, isNot(contains('FILMKITDATUM')));

    final withLocation = await exifOf(true);
    expect(withLocation, contains('FilmkitCam'));
    expect(withLocation, contains('FILMKITDATUM'));
  });

  testWidgets('reads HEIC photos', (_) async {
    final result = await Filmkit.exportImage(input: photos['gradient.heic']!, output: '${out.path}/heic.jpg', quality: 100);
    expect((result.width, result.height), (640, 480));
    final diff = Diff.of(await decodeFile(result.path), await decodeFile(photos['gradient.jpg']!));
    debugPrint('HEIC export vs JPEG source: $diff');
    expect(diff.mean, lessThan(3), reason: '$diff');
  });

  testWidgets('exports a 12 MP photo', (_) async {
    final input = '${out.path}/large.png';
    if (!File(input).existsSync()) await File(input).writeAsBytes(await largeGradientPng(4000, 3000));
    final watch = Stopwatch()..start();
    final result = await Filmkit.exportImage(
      input: input,
      output: '${out.path}/large.jpg',
      edit: EditSpec(maxDimension: 1080, lut: lookPath),
    );
    debugPrint('12 MP photo exported in ${watch.elapsedMilliseconds} ms');
    expect((result.width, result.height), (1080, 810));

    watch.reset();
    final full = await Filmkit.exportImage(
      input: input,
      output: '${out.path}/large_full.jpg',
      edit: EditSpec(lut: lookPath),
    );
    debugPrint('12 MP photo exported at full size with a LUT in ${watch.elapsedMilliseconds} ms');
    expect((full.width, full.height), (4000, 3000));
  });

  testWidgets('fails with invalidInput on a missing or unreadable file', (_) async {
    await expectLater(Filmkit.exportImage(input: '${out.path}/missing.jpg', output: '${out.path}/x.jpg'), hasCode(FilmkitErrorCode.invalidInput));
    final text = '${out.path}/not_an_image.jpg';
    await File(text).writeAsString('not an image');
    await expectLater(Filmkit.exportImage(input: text, output: '${out.path}/y.jpg'), hasCode(FilmkitErrorCode.invalidInput));
  });
}

Future<Uint8List> largeGradientPng(int width, int height) async {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      bytes[i] = x * 255 ~/ (width - 1);
      bytes[i + 1] = y * 255 ~/ (height - 1);
      bytes[i + 2] = (x + y) * 255 ~/ (width + height - 2);
      bytes[i + 3] = 255;
    }
  }
  final image = await Rgba(width, height, bytes).toImage();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}
