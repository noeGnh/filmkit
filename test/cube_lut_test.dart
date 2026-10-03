import 'package:filmkit/filmkit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 2³ table that inverts colors, with red varying fastest.
const invert2 = '''
# Comment
TITLE "Invert"
LUT_3D_SIZE 2
DOMAIN_MIN 0 0 0
DOMAIN_MAX 1.0 1.0 1.0

1 1 1
0 1 1
1 0 1
0 0 1
1 1 0
0 1 0
1 0 0
0 0 0
''';

void main() {
  test('parse reads size, title and entries in .cube order', () {
    final lut = CubeLut.parse(invert2);
    expect(lut.size, 2);
    expect(lut.title, 'Invert');
    expect(lut.apply(0, 0, 0), (1, 1, 1));
    expect(lut.apply(1, 0, 0), (0, 1, 1));
    expect(lut.apply(0, 1, 0), (1, 0, 1));
    expect(lut.apply(0, 0, 1), (1, 1, 0));
    final (r, g, b) = lut.apply(0.25, 0.5, 0.75);
    expect([r, g, b], [closeTo(0.75, 1e-6), closeTo(0.5, 1e-6), closeTo(0.25, 1e-6)]);
  });

  test('parse clamps values and accepts Windows line endings', () {
    final lut = CubeLut.parse(invert2.replaceFirst('1 1 1', '1.5 -0.5 1').replaceAll('\n', '\r\n'));
    expect(lut.apply(0, 0, 0), (1, 0, 1));
  });

  test('parse rejects unsupported or malformed files', () {
    void invalid(String source) => expect(() => CubeLut.parse(source), throwsFormatException, reason: source);
    invalid('LUT_1D_SIZE 4\n0 0 0');
    invalid(invert2.replaceFirst('DOMAIN_MAX 1.0 1.0 1.0', 'DOMAIN_MAX 2 2 2'));
    invalid(invert2.replaceFirst('0 0 0\n', ''));
    invalid('$invert2\n0 0 0');
    invalid(invert2.replaceFirst('0 1 0', '0 x 0'));
    invalid('0 0 0\nLUT_3D_SIZE 2');
    invalid('TITLE "empty"');
    invalid('LUT_3D_SIZE 1');
  });

  test('identity leaves colors unchanged', () {
    final lut = CubeLut.identity(17);
    final (r, g, b) = lut.apply(0.1, 0.52, 0.97);
    expect([r, g, b], [closeTo(0.1, 1e-6), closeTo(0.52, 1e-6), closeTo(0.97, 1e-6)]);
  });

  test('withIntensity blends with the identity', () {
    final lut = CubeLut.parse(invert2);
    expect(identical(lut.withIntensity(1), lut), isTrue);
    final (r0, g0, b0) = lut.withIntensity(0).apply(0.2, 0.4, 0.6);
    expect([r0, g0, b0], [closeTo(0.2, 1e-6), closeTo(0.4, 1e-6), closeTo(0.6, 1e-6)]);
    final (r, g, b) = lut.withIntensity(0.5).apply(0.2, 0.4, 1);
    expect([r, g, b], [closeTo(0.5, 1e-6), closeTo(0.5, 1e-6), closeTo(0.5, 1e-6)]);
  });

  test('generate samples the transform with red varying fastest', () {
    final lut = CubeLut.generate(3, (r, g, b) => (b, g, r));
    expect(lut.data.sublist(0, 6), [0, 0, 0, 0, 0, 0.5]);
    expect(lut.apply(1, 0, 0.5), (0.5, 0, 1));
  });

  test('constructor checks the data length', () {
    expect(() => CubeLut(2, CubeLut.identity(3).data), throwsArgumentError);
  });

  test('encode round-trips through parse', () {
    final lut = CubeLut.parse(invert2);
    final decoded = CubeLut.parse(lut.encode());
    expect(decoded.title, 'Invert');
    expect(decoded.data, lut.data);
    expect(CubeLut.identity(2).encode(), startsWith('LUT_3D_SIZE 2\n0.000000 0.000000 0.000000\n1.000000 0.000000 0.000000\n'));
  });
}
