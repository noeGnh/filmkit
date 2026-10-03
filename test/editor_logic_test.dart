import 'dart:ui';

import 'package:filmkit/filmkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CropState', () {
    test('the original aspect keeps the whole media', () {
      const state = CropState(mediaAspect: 16 / 9);
      expect(state.rect, const Rect.fromLTRB(0, 0, 1, 1));
      expect(state.isFull, isTrue);
    });

    test('a narrower aspect uses the full height, centered', () {
      final state = const CropState(mediaAspect: 16 / 9).withAspect(CropAspect.square);
      expect(state.rect.height, closeTo(1, 1e-9));
      expect(state.rect.width, closeTo(9 / 16, 1e-9));
      expect(state.rect.center, const Offset(0.5, 0.5));
      expect(state.isFull, isFalse);
    });

    test('a wider aspect uses the full width', () {
      final state = const CropState(mediaAspect: 3 / 4).withAspect(CropAspect.landscape);
      expect(state.rect.width, closeTo(1, 1e-9));
      // Pixel aspect of the crop: (w × 3) / (h × 4) = 16 / 9.
      expect(state.rect.width * 3 / (state.rect.height * 4), closeTo(16 / 9, 1e-9));
    });

    test('panning stays inside the media', () {
      final state = const CropState(mediaAspect: 16 / 9).withAspect(CropAspect.square).panned(const Offset(1, 1));
      expect(state.rect.right, closeTo(1, 1e-9));
      expect(state.rect.top, closeTo(0, 1e-9), reason: 'no vertical room at zoom 1');
    });

    test('zooming keeps the focal point and is clamped', () {
      const state = CropState(mediaAspect: 1);
      final zoomed = state.zoomed(2, const Offset(0.25, 0.25));
      expect(zoomed.zoom, 2);
      // The focal point stays a quarter of the way into the frame.
      expect(zoomed.rect.left, closeTo(0.125, 1e-9));
      expect(zoomed.rect.right, closeTo(0.625, 1e-9));
      expect(zoomed.rect.top, closeTo(0.125, 1e-9));
      expect(zoomed.zoomed(100, const Offset(0.5, 0.5)).zoom, CropState.maxZoom);
      expect(zoomed.zoomed(0.01, const Offset(0.5, 0.5)).rect, const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('frameSizeIn fits the frame aspect in the area', () {
      final state = const CropState(mediaAspect: 16 / 9).withAspect(CropAspect.portrait);
      expect(state.frameSizeIn(const Size(400, 400)), const Size(320, 400));
      expect(state.frameSizeIn(const Size(400, 1000)), const Size(400, 500));
    });
  });

  group('clampTrim', () {
    const d = Duration(seconds: 10);
    const min = Duration(seconds: 1);

    test('keeps a valid range', () {
      expect(clampTrim(const Duration(seconds: 2), const Duration(seconds: 5), d, minLength: min), (const Duration(seconds: 2), const Duration(seconds: 5)));
    });

    test('clamps to the video and keeps the minimum length', () {
      expect(clampTrim(const Duration(seconds: -1), const Duration(seconds: 20), d, minLength: min), (Duration.zero, d));
      expect(clampTrim(const Duration(seconds: 3), const Duration(seconds: 3), d, minLength: min), (const Duration(seconds: 3), const Duration(seconds: 4)));
      expect(clampTrim(const Duration(seconds: 10), const Duration(seconds: 10), d, minLength: min), (const Duration(seconds: 9), d));
    });

    test('applies the maximum length', () {
      expect(
        clampTrim(Duration.zero, d, d, minLength: min, maxLength: const Duration(seconds: 3)),
        (Duration.zero, const Duration(seconds: 3)),
      );
    });
  });

  group('Adjustments', () {
    test('neutral adjustments leave colors unchanged', () {
      final (r, g, b) = const Adjustments().apply(0.2, 0.5, 0.9);
      expect([r, g, b], [closeTo(0.2, 1e-9), closeTo(0.5, 1e-9), closeTo(0.9, 1e-9)]);
    });

    test('each adjustment moves colors the expected way', () {
      expect(const Adjustments(brightness: 0.5).apply(0.5, 0.5, 0.5).$1, greaterThan(0.5));
      expect(const Adjustments(brightness: -0.5).apply(0.5, 0.5, 0.5).$1, lessThan(0.5));
      expect(const Adjustments(contrast: 0.5).apply(0.8, 0.8, 0.8).$1, greaterThan(0.8));
      final (gr, gg, gb) = const Adjustments(saturation: -1).apply(1, 0, 0);
      expect([gr, gg, gb], everyElement(closeTo(0.2126, 1e-9)));
      final (wr, _, wb) = const Adjustments(warmth: 1).apply(0.5, 0.5, 0.5);
      expect(wr, greaterThan(0.5));
      expect(wb, lessThan(0.5));
    });

    test('brightness keeps black and white', () {
      expect(const Adjustments(brightness: 1).apply(0, 0, 0), (0, 0, 0));
      expect(const Adjustments(brightness: -1).apply(1, 1, 1), (1, 1, 1));
    });
  });

  group('combinedLut', () {
    final look = Looks.builtIn.firstWhere((l) => l.name == 'Mono');

    test('is null without look or adjustment', () {
      expect(combinedLut(null, 1, const Adjustments()), isNull);
      expect(combinedLut(look, 0, const Adjustments()), isNull);
    });

    test('applies the look at its intensity, then the adjustments', () {
      final half = combinedLut(look, 0.5, const Adjustments())!;
      final (r, _, _) = half.apply(1, 0, 0);
      expect(r, closeTo((1 + 0.2126) / 2, 1e-3));

      final both = combinedLut(look, 1, const Adjustments(brightness: 0.5))!;
      final (gray, _, _) = both.apply(0.5, 0.5, 0.5);
      expect(gray, closeTo(const Adjustments(brightness: 0.5).apply(0.5, 0.5, 0.5).$1, 2e-3));
    });
  });

  test('built-in looks have distinct names and change colors', () {
    final looks = Looks.builtIn;
    expect(looks.map((l) => l.name).toSet(), hasLength(looks.length));
    for (final look in looks) {
      final (r, g, b) = look.lut.apply(0.6, 0.4, 0.3);
      expect((r - 0.6).abs() + (g - 0.4).abs() + (b - 0.3).abs(), greaterThan(0.02), reason: look.name);
    }
  });
}
