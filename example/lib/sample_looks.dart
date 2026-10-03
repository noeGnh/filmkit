import 'package:filmkit/filmkit.dart';

/// A "film" look: S-curve contrast, warm tint, more saturation.
final CubeLut filmLook = CubeLut.generate(33, (r, g, b) {
  double curve(double x) => x + 0.6 * (x * x * (3 - 2 * x) - x);
  final c = [curve(r) * 1.06, curve(g), curve(b) * 0.9];
  final luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  final s = [for (final v in c) luma + 1.3 * (v - luma)];
  return (s[0], s[1], s[2]);
});
