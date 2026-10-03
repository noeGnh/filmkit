import 'package:flutter/widgets.dart';

import 'crop_state.dart';

/// Shows [child] (the media, at its displayed aspect) through the crop frame of [state]. When
/// [interactive], the media can be panned and zoomed under the frame, over a rule-of-thirds
/// grid.
class CropView extends StatefulWidget {
  const CropView({super.key, required this.state, required this.onChanged, required this.interactive, required this.child, this.frameBuilder});

  final CropState state;
  final ValueChanged<CropState> onChanged;
  final bool interactive;
  final Widget child;

  /// Wraps the visible (clipped) frame, e.g. in a `LutFilter`, so that effects only process
  /// what is shown.
  final Widget Function(Widget frame)? frameBuilder;

  @override
  State<CropView> createState() => _CropViewState();
}

class _CropViewState extends State<CropView> {
  Size _frame = Size.zero;
  double _lastScale = 1;

  /// The latest state: several gesture updates can arrive before the parent rebuilds this
  /// widget with the previous one (two fingers moving in the same frame).
  late CropState _state = widget.state;

  @override
  void didUpdateWidget(CropView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _state = widget.state;
  }

  void _onScaleStart(ScaleStartDetails details) => _lastScale = 1;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_frame.isEmpty) return;
    // First the pan, at the current zoom: the media point under the previous focal point moves
    // under the new one (dragging the media right moves the frame left over it). Then the zoom
    // around the new focal point, which keeps that point under the fingers.
    var next = _state;
    var rect = next.rect;
    final delta = details.focalPointDelta;
    next = next.panned(Offset(-delta.dx / _frame.width * rect.width, -delta.dy / _frame.height * rect.height));
    if (details.scale != _lastScale) {
      rect = next.rect;
      final focal = details.localFocalPoint;
      final focalMedia = Offset(rect.left + focal.dx / _frame.width * rect.width, rect.top + focal.dy / _frame.height * rect.height);
      next = next.zoomed(details.scale / _lastScale, focalMedia);
      _lastScale = details.scale;
    }
    if (next != _state) {
      _state = next;
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final state = widget.state;
        _frame = state.frameSizeIn(constraints.biggest);
        final rect = state.rect;
        final media = Size(_frame.width / rect.width, _frame.height / rect.height);
        Widget frame = ClipRect(
          child: Stack(
            children: [
              Positioned(left: -rect.left * media.width, top: -rect.top * media.height, width: media.width, height: media.height, child: widget.child),
            ],
          ),
        );
        frame = widget.frameBuilder?.call(frame) ?? frame;
        return Center(
          child: SizedBox.fromSize(
            size: _frame,
            child: GestureDetector(
              onScaleStart: widget.interactive ? _onScaleStart : null,
              onScaleUpdate: widget.interactive ? _onScaleUpdate : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  frame,
                  if (widget.interactive) const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), line);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}
