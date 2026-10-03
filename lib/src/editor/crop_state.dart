import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// An aspect ratio offered by the crop tool.
@immutable
class CropAspect {
  const CropAspect(this.label, this.ratio);

  /// Width / height; `null` for the media's own ratio.
  final double? ratio;
  final String label;

  static const original = CropAspect('Original', null);
  static const square = CropAspect('1:1', 1);
  static const portrait = CropAspect('4:5', 4 / 5);
  static const landscape = CropAspect('16:9', 16 / 9);

  /// The ratios Instagram offers.
  static const defaults = [original, square, portrait, landscape];

  @override
  bool operator ==(Object other) => other is CropAspect && other.ratio == ratio && other.label == label;

  @override
  int get hashCode => Object.hash(label, ratio);

  @override
  String toString() => 'CropAspect($label)';
}

/// The crop as the editor manipulates it: a frame of a given aspect over the media, zoomed and
/// panned. Coordinates are normalized to the displayed media (0..1).
@immutable
class CropState {
  const CropState({required this.mediaAspect, this.aspect = CropAspect.original, this.zoom = 1, this.center = const Offset(0.5, 0.5)});

  /// The state showing [rect] (normalized, e.g. a crop chosen in a picker) through a frame of
  /// [aspect]: [rect] is expected to have that aspect; it's zoomed to its width and clamped
  /// into the media.
  factory CropState.fromRect({required double mediaAspect, required CropAspect aspect, required Rect rect}) {
    final base = CropState(mediaAspect: mediaAspect, aspect: aspect);
    final zoom = rect.width > 0 ? (base.cropSize.width / rect.width).clamp(1.0, maxZoom) : 1.0;
    return CropState(mediaAspect: mediaAspect, aspect: aspect, zoom: zoom, center: rect.center).panned(Offset.zero);
  }

  /// Displayed width / height of the media.
  final double mediaAspect;
  final CropAspect aspect;

  /// 1 shows the largest frame that fits in the media; up to [maxZoom].
  final double zoom;

  /// Center of the frame, kept such that the frame stays inside the media.
  final Offset center;

  static const maxZoom = 5.0;

  /// Width / height of the frame.
  double get frameAspect => aspect.ratio ?? mediaAspect;

  /// Size of the frame in normalized media units.
  Size get cropSize {
    final a = frameAspect;
    // At zoom 1: the full width if the frame is wider than the media, else the full height.
    final base = a >= mediaAspect ? Size(1, mediaAspect / a) : Size(a / mediaAspect, 1);
    return Size(base.width / zoom, base.height / zoom);
  }

  /// The cropped area, normalized.
  Rect get rect => Rect.fromCenter(center: center, width: cropSize.width, height: cropSize.height);

  /// Whether the crop keeps the whole media.
  bool get isFull {
    final r = rect;
    const e = 1e-6;
    return r.left <= e && r.top <= e && r.right >= 1 - e && r.bottom >= 1 - e;
  }

  CropState withAspect(CropAspect aspect) => CropState(mediaAspect: mediaAspect, aspect: aspect);

  /// Pans by [delta] in normalized media units (positive moves the frame right / down).
  CropState panned(Offset delta) => _with(zoom, center + delta);

  /// Zooms by [factor] keeping the media point [focal] (normalized) under the same frame point.
  CropState zoomed(double factor, Offset focal) {
    final newZoom = (zoom * factor).clamp(1.0, maxZoom);
    final k = zoom / newZoom;
    return _with(newZoom, focal + (center - focal) * k);
  }

  CropState _with(double zoom, Offset center) {
    final next = CropState(mediaAspect: mediaAspect, aspect: aspect, zoom: zoom, center: center);
    final size = next.cropSize;
    double clampAxis(double c, double extent) => extent >= 1 ? 0.5 : c.clamp(extent / 2, 1 - extent / 2);
    return CropState(
      mediaAspect: mediaAspect,
      aspect: aspect,
      zoom: zoom,
      center: Offset(clampAxis(center.dx, size.width), clampAxis(center.dy, size.height)),
    );
  }

  /// The largest frame of [frameAspect] that fits in [area].
  Size frameSizeIn(Size area) {
    final a = frameAspect;
    return area.width / area.height > a ? Size(area.height * a, area.height) : Size(area.width, area.width / a);
  }

  @override
  bool operator ==(Object other) =>
      other is CropState && other.mediaAspect == mediaAspect && other.aspect == aspect && other.zoom == zoom && other.center == center;

  @override
  int get hashCode => Object.hash(mediaAspect, aspect, zoom, center);

  @override
  String toString() => 'CropState(${aspect.label}, zoom: ${zoom.toStringAsFixed(2)}, rect: $rect)';
}

/// Clamps a trim range to [duration], keeping it at least [minLength] long and, if given, at
/// most [maxLength].
(Duration, Duration) clampTrim(Duration start, Duration end, Duration duration, {required Duration minLength, Duration? maxLength}) {
  final min = minLength > duration ? duration : minLength;
  var s = start < Duration.zero ? Duration.zero : start;
  var e = end > duration ? duration : end;
  if (e - s < min) {
    // Grow toward the side that has room.
    e = s + min;
    if (e > duration) {
      e = duration;
      s = duration - min;
    }
  }
  if (maxLength != null && e - s > maxLength) e = s + maxLength;
  return (s, Duration(microseconds: math.max(e.inMicroseconds, s.inMicroseconds)));
}
