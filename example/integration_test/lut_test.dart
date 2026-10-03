import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_example/sample_looks.dart';
import 'package:filmkit_example/sample_videos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'pixels.dart';

/// Checks that a LUT gives the same colors in the CPU reference ([CubeLut.apply]), the preview
/// ([LutFilter]) and the native export, on the gradient sample video.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> videos;
  late Directory out;
  late CubeLut look;
  late String lookPath;
  late Rgba source;

  setUpAll(() async {
    videos = await copySampleVideos();
    out = await Directory('${Directory.systemTemp.path}/filmkit_lut_out').create(recursive: true);
    look = filmLook;
    lookPath = '${out.path}/look.cube';
    await File(lookPath).writeAsString(look.encode());
    source = await Rgba.fromImage(await Filmkit.getVideoFrame(videos['gradient.mp4']!, position: const Duration(seconds: 1)));
  });

  testWidgets('getVideoFrame returns displayed frames at the requested time', (_) async {
    final landscape = await Rgba.fromImage(await Filmkit.getVideoFrame(videos['landscape.mp4']!, position: const Duration(seconds: 3)));
    expect((landscape.width, landscape.height), (640, 360));
    // Time band: luma 255 × t / 6 s in limited range, i.e. gray (127.5 - 16) × 255 / 219 at 3 s.
    expect(landscape.pixel(320, 180).$1, closeTo(130, 8));

    final portrait = await Rgba.fromImage(await Filmkit.getVideoFrame(videos['portrait_noaudio.mp4']!, maxDimension: 320));
    expect((portrait.width, portrait.height), (180, 320), reason: 'rotation applied, then scaled down');
    expect(colorName(portrait.pixel(20, 20)), 'red', reason: 'top left');
    expect(colorName(portrait.pixel(160, 20)), 'green', reason: 'top right');
    expect(colorName(portrait.pixel(20, 300)), 'blue', reason: 'bottom left');
    expect(colorName(portrait.pixel(160, 300)), 'white', reason: 'bottom right');
  });

  testWidgets(
    'export keeps the source colors',
    (_) async {
      final plain = await exportFrame(videos['gradient.mp4']!, '${out.path}/plain.mp4', const EditSpec());
      final codec = Diff.of(plain, source);
      debugPrint('export without LUT vs source: $codec');
      expect(codec.mean, lessThan(2), reason: '$codec');
      expect(codec.p99, lessThan(8), reason: '$codec');
    },
    // The Android emulator's graphics layer converts BT.709 frames with the BT.601 matrix, which
    // Media3 reads through an external texture: run with --dart-define=EMULATOR=true there.
    skip: Platform.isAndroid && const bool.fromEnvironment('EMULATOR'),
  );

  testWidgets('export applies the LUT like the CPU reference', (_) async {
    final effect = Diff.of(source, source.graded(look));
    expect(effect.mean, greaterThan(10), reason: 'the look must change colors visibly: $effect');

    // Reference: the LUT applied to the export without LUT, so that the check covers the LUT
    // only, whatever the decoding of the device.
    final plain = await exportFrame(videos['gradient.mp4']!, '${out.path}/plain.mp4', const EditSpec());
    final graded = await exportFrame(videos['gradient.mp4']!, '${out.path}/graded.mp4', EditSpec(lut: lookPath));
    final half = await exportFrame(videos['gradient.mp4']!, '${out.path}/half.mp4', EditSpec(lut: lookPath, lutIntensity: 0.5));

    final full = Diff.of(graded, plain.graded(look));
    final halfDiff = Diff.of(half, plain.graded(look.withIntensity(0.5)));
    debugPrint('LUT effect: $effect | export vs CPU: $full | 50 %: $halfDiff');
    // Codec error only: a wrong color space gave a mean of 3 to 17 in the spikes.
    for (final diff in [full, halfDiff]) {
      expect(diff.mean, lessThan(1.5), reason: '$diff');
      expect(diff.p99, lessThan(6), reason: '$diff');
    }
  });

  testWidgets('LutFilter previews the LUT like the CPU reference', (tester) async {
    final image = await source.toImage();
    final key = GlobalKey();
    final dpr = tester.view.devicePixelRatio;

    Future<Rgba> render(double intensity) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: LutFilter(
                lut: look,
                intensity: intensity,
                child: RawImage(image: image, width: source.width / dpr, height: source.height / dpr, fit: BoxFit.fill, filterQuality: FilterQuality.none),
              ),
            ),
          ),
        ),
      );
      // Shader program and LUT texture load asynchronously.
      bool applied() => tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled;
      for (var i = 0; i < 100 && !applied(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(applied(), isTrue, reason: 'LutFilter never applied the shader');
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final rendered = (await tester.runAsync(() => boundary.toImage(pixelRatio: dpr)))!;
      return (await tester.runAsync(() => Rgba.fromImage(rendered)))!;
    }

    final full = Diff.of(await render(1), source.graded(look));
    final half = Diff.of(await render(0.5), source.graded(look.withIntensity(0.5)));
    debugPrint('preview vs CPU: $full | 50 %: $half');
    // The texture holds the LUT in 8 bits: up to ±1 after rounding.
    expect(full.max, lessThanOrEqualTo(2), reason: '$full');
    expect(half.max, lessThanOrEqualTo(2), reason: '$half');
  });
}

Future<Rgba> exportFrame(String input, String output, EditSpec edit) async {
  final result = await Filmkit.exportVideo(input: input, output: output, edit: edit).result;
  return Rgba.fromImage(await Filmkit.getVideoFrame(result.path, position: const Duration(seconds: 1)));
}
