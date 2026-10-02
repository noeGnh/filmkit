import 'dart:ui';

import 'package:filmkit/filmkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditSpec', () {
    test('round-trips through JSON', () {
      const spec = EditSpec(
        trimStart: Duration(milliseconds: 1500),
        trimEnd: Duration(seconds: 4),
        crop: Rect.fromLTRB(0.25, 0, 1, 0.75),
        maxDimension: 1080,
      );
      expect(spec.toJson(), {
        'trimStartMs': 1500,
        'trimEndMs': 4000,
        'crop': [0.25, 0.0, 1.0, 0.75],
        'maxDimension': 1080,
      });
      expect(EditSpec.fromJson(spec.toJson()), spec);
    });

    test('defaults keep the whole video', () {
      expect(const EditSpec().toJson(), {'trimStartMs': 0, 'trimEndMs': null, 'crop': null, 'maxDimension': null});
      expect(EditSpec.fromJson(const {}), const EditSpec());
    });

    test('accepts integer crop values from JSON', () {
      expect(
        EditSpec.fromJson(const {
          'crop': [0, 0, 1, 1],
        }).crop,
        const Rect.fromLTRB(0, 0, 1, 1),
      );
    });

    test('validate rejects invalid specs', () {
      void invalid(EditSpec spec) => expect(spec.validate, throwsArgumentError, reason: '$spec');
      invalid(const EditSpec(trimStart: Duration(milliseconds: -1)));
      invalid(const EditSpec(trimStart: Duration(seconds: 2), trimEnd: Duration(seconds: 2)));
      invalid(const EditSpec(crop: Rect.fromLTRB(-0.1, 0, 1, 1)));
      invalid(const EditSpec(crop: Rect.fromLTRB(0, 0, 1.1, 1)));
      invalid(const EditSpec(crop: Rect.fromLTRB(0.5, 0, 0.5, 1)));
      invalid(const EditSpec(maxDimension: 1));
    });

    test('validate accepts valid specs', () {
      const EditSpec().validate();
      const EditSpec(
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(seconds: 2),
        crop: Rect.fromLTRB(0, 0, 1, 1),
        maxDimension: 2,
      ).validate();
    });
  });
}
