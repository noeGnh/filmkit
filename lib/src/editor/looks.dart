import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../cube_lut.dart';

/// A named filter offered by the editor.
@immutable
class Look {
  const Look(this.name, this.lut);

  /// Builds a look from a color transform (inputs and outputs in 0..1, sRGB-encoded).
  factory Look.generate(String name, (double, double, double) Function(double r, double g, double b) transform) => Look(name, CubeLut.generate(33, transform));

  /// Loads a `.cube` file.
  static Future<Look> fromFile(String name, String path) async => Look(name, await CubeLut.fromFile(path));

  final String name;
  final CubeLut lut;

  @override
  String toString() => 'Look($name)';
}

/// The editor's built-in looks, generated in Dart (no image assets, no licensing).
abstract final class Looks {
  static List<Look>? _builtIn;

  /// Vivid, Warm, Cool, Fade, Film, Cinema, Vintage, Sunset, Mono, Noir.
  static List<Look> get builtIn => _builtIn ??= [
    Look.generate('Vivid', (r, g, b) => _saturate(_contrast((r, g, b), 0.15), 1.35)),
    Look.generate('Warm', (r, g, b) => _contrast((r * 1.07 + 0.02, g * 1.02 + 0.01, b * 0.88), 0.05)),
    Look.generate('Cool', (r, g, b) => _contrast((r * 0.92, g * 0.99 + 0.01, b * 1.06 + 0.03), 0.05)),
    Look.generate('Fade', (r, g, b) => _saturate(_lift((r, g, b), 0.12, 0.94), 0.8)),
    Look.generate('Film', (r, g, b) => _saturate(_sCurve((r * 1.06, g, b * 0.9), 0.6), 1.3)),
    Look.generate('Cinema', (r, g, b) {
      // Teal shadows, orange highlights.
      final y = _luma(r, g, b) - 0.5;
      return _sCurve((r + 0.12 * y, g + 0.02 * y, b - 0.14 * y), 0.3);
    }),
    Look.generate('Vintage', (r, g, b) {
      final (sr, sg, sb) = _sepia(r, g, b);
      return _lift((_mix(r, sr, 0.45), _mix(g, sg, 0.45), _mix(b, sb, 0.45)), 0.08, 0.92);
    }),
    Look.generate('Sunset', (r, g, b) {
      final y = _luma(r, g, b);
      // Magenta shadows, golden highlights.
      return _sCurve((r * 1.08 + 0.04 * (1 - y), g * 0.98, b * 0.9 + 0.06 * (1 - y)), 0.35);
    }),
    Look.generate('Mono', (r, g, b) {
      final y = _luma(r, g, b);
      return (y, y, y);
    }),
    Look.generate('Noir', (r, g, b) {
      final y = _sCurve1(_luma(r, g, b), 1);
      return (y, y, y);
    }),
  ];
}

double _luma(double r, double g, double b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

double _mix(double a, double b, double t) => a + (b - a) * t;

/// Smoothstep S-curve blended with the identity by [amount] (0..1).
double _sCurve1(double x, double amount) {
  final c = x.clamp(0.0, 1.0);
  return _mix(c, c * c * (3 - 2 * c), amount);
}

(double, double, double) _sCurve((double, double, double) c, double amount) => (_sCurve1(c.$1, amount), _sCurve1(c.$2, amount), _sCurve1(c.$3, amount));

/// Linear contrast around mid gray.
(double, double, double) _contrast((double, double, double) c, double amount) {
  double f(double x) => 0.5 + (x - 0.5) * (1 + amount);
  return (f(c.$1), f(c.$2), f(c.$3));
}

/// Raises the black point to [black] and lowers the white point to [white].
(double, double, double) _lift((double, double, double) c, double black, double white) {
  double f(double x) => black + x.clamp(0.0, 1.0) * (white - black);
  return (f(c.$1), f(c.$2), f(c.$3));
}

(double, double, double) _saturate((double, double, double) c, double amount) {
  final y = _luma(c.$1, c.$2, c.$3);
  return (y + (c.$1 - y) * amount, y + (c.$2 - y) * amount, y + (c.$3 - y) * amount);
}

(double, double, double) _sepia(double r, double g, double b) =>
    (math.min(1, 0.393 * r + 0.769 * g + 0.189 * b), math.min(1, 0.349 * r + 0.686 * g + 0.168 * b), math.min(1, 0.272 * r + 0.534 * g + 0.131 * b));
