import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A strip of video thumbnails with start and end handles, and the playback position.
class TrimBar extends StatelessWidget {
  const TrimBar({
    super.key,
    required this.duration,
    required this.start,
    required this.end,
    required this.thumbnails,
    required this.position,
    required this.minLength,
    this.maxLength,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Duration duration;
  final Duration start;
  final Duration end;
  final List<ui.Image> thumbnails;

  /// Playback position, `null` to hide it.
  final Duration? position;
  final Duration minLength;
  final Duration? maxLength;

  /// Called while a handle moves, with the handle's time ([moved]) to preview.
  final void Function(Duration start, Duration end, Duration moved) onChanged;
  final VoidCallback onChangeEnd;

  static const handleWidth = 16.0;
  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_format(start)} – ${_format(end)}  (${((end - start).inMilliseconds / 1000).toStringAsFixed(1)} s)',
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontFeatures: [ui.FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Handles sit outside the strip, so that the full range stays reachable.
              final width = constraints.maxWidth - 2 * handleWidth;
              double x(Duration t) => handleWidth + width * t.inMicroseconds / duration.inMicroseconds;
              Duration at(double dx) => Duration(microseconds: ((dx - handleWidth) / width * duration.inMicroseconds).round());
              final startX = x(start);
              final endX = x(end);
              return Stack(
                children: [
                  Positioned(
                    left: handleWidth,
                    width: width,
                    top: 4,
                    bottom: 4,
                    child: Row(
                      children: [
                        for (final thumbnail in thumbnails)
                          Expanded(
                            child: RawImage(image: thumbnail, fit: BoxFit.cover),
                          ),
                      ],
                    ),
                  ),
                  // Dim the parts outside the range.
                  Positioned(
                    left: handleWidth,
                    width: startX - handleWidth,
                    top: 4,
                    bottom: 4,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                  Positioned(
                    left: endX,
                    right: handleWidth,
                    top: 4,
                    bottom: 4,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                  Positioned(
                    left: startX,
                    width: endX - startX,
                    top: 0,
                    bottom: 0,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.symmetric(horizontal: BorderSide(color: Colors.white, width: 4)),
                        ),
                      ),
                    ),
                  ),
                  if (position != null && position! >= start && position! <= end)
                    Positioned(
                      // Keyed, like the handles: this line comes and goes while dragging, and must
                      // not shift the handles' elements (which would cancel the drag).
                      key: const ValueKey('playhead'),
                      left: x(position!) - 1,
                      width: 2,
                      top: 0,
                      bottom: 0,
                      child: const IgnorePointer(child: ColoredBox(color: Colors.white)),
                    ),
                  _handle(
                    key: const ValueKey('filmkit.trim.start'),
                    left: startX - handleWidth,
                    boundaryX: startX,
                    onDrag: (boundaryX) {
                      var s = _clamp(at(boundaryX), Duration.zero, end - minLength);
                      if (maxLength != null && end - s > maxLength!) s = end - maxLength!;
                      onChanged(s, end, s);
                    },
                  ),
                  _handle(
                    key: const ValueKey('filmkit.trim.end'),
                    left: endX,
                    boundaryX: endX,
                    onDrag: (boundaryX) {
                      var e = _clamp(at(boundaryX), start + minLength, duration);
                      if (maxLength != null && e - start > maxLength!) e = start + maxLength!;
                      onChanged(start, e, e);
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// A handle whose drag reports the new x of the range boundary it holds.
  Widget _handle({required Key key, required double left, required double boundaryX, required ValueChanged<double> onDrag}) {
    var x = boundaryX;
    return Positioned(
      key: ObjectKey(key),
      left: left,
      width: handleWidth,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => x = boundaryX,
        onHorizontalDragUpdate: (details) {
          x += details.delta.dx;
          onDrag(x);
        },
        onHorizontalDragEnd: (_) => onChangeEnd(),
        onHorizontalDragCancel: onChangeEnd,
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(4))),
          child: const Center(
            child: SizedBox(width: 2, height: 18, child: ColoredBox(color: Colors.black54)),
          ),
        ),
      ),
    );
  }

  static Duration _clamp(Duration t, Duration min, Duration max) => t < min ? min : (t > max ? max : t);

  static String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inMilliseconds % 60000) / 1000;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
