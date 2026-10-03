import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../cube_lut.dart';
import 'looks.dart';

/// Color adjustments, each from -1 to 1 (0: unchanged). Color-only, so they bake into a LUT
/// with the look ([combinedLut]) and need nothing more from the exporters.
@immutable
class Adjustments {
  const Adjustments({this.brightness = 0, this.contrast = 0, this.saturation = 0, this.warmth = 0});

  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  bool get isNeutral => brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0;

  Adjustments copyWith({double? brightness, double? contrast, double? saturation, double? warmth}) => Adjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
  );

  /// Applies the adjustments to a color in 0..1 (sRGB-encoded).
  (double, double, double) apply(double r, double g, double b) {
    // Brightness: a gamma curve, which keeps black and white.
    final gamma = math.pow(2, -0.8 * brightness).toDouble();
    double bright(double x) => math.pow(x.clamp(0.0, 1.0), gamma).toDouble();
    r = bright(r);
    g = bright(g);
    b = bright(b);
    // Contrast around mid gray.
    double contrasted(double x) => 0.5 + (x - 0.5) * (1 + 0.6 * contrast);
    r = contrasted(r);
    g = contrasted(g);
    b = contrasted(b);
    // Saturation around the luma (-1: gray).
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final s = 1 + saturation;
    r = y + (r - y) * s;
    g = y + (g - y) * s;
    b = y + (b - y) * s;
    // Warmth: red up and blue down, or the reverse.
    r *= 1 + 0.1 * warmth;
    b *= 1 - 0.1 * warmth;
    return (r.clamp(0, 1), g.clamp(0, 1), b.clamp(0, 1));
  }

  @override
  bool operator ==(Object other) =>
      other is Adjustments && other.brightness == brightness && other.contrast == contrast && other.saturation == saturation && other.warmth == warmth;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, warmth);

  @override
  String toString() => 'Adjustments(brightness: $brightness, contrast: $contrast, saturation: $saturation, warmth: $warmth)';
}

/// The table applying [look] at [intensity], then [adjustments]; `null` if neither changes
/// colors.
CubeLut? combinedLut(Look? look, double intensity, Adjustments adjustments) {
  final lookActive = look != null && intensity > 0;
  if (!lookActive && adjustments.isNeutral) return null;
  if (lookActive && adjustments.isNeutral) return look.lut.withIntensity(intensity);
  return CubeLut.generate(33, (r, g, b) {
    if (lookActive) {
      final (lr, lg, lb) = look.lut.apply(r, g, b);
      r += (lr - r) * intensity;
      g += (lg - g) * intensity;
      b += (lb - b) * intensity;
    }
    return adjustments.apply(r, g, b);
  });
}
