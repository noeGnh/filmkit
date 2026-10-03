import 'package:filmkit/filmkit.dart';
import 'package:filmkit/src/editor/crop_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CropState state;

  /// A 16:9 media under a square frame, in a 400 × 400 box: the frame is 400 px for 9/16 of the
  /// media width.
  Future<void> pumpCrop(WidgetTester tester, {bool interactive = true, CropState? initial}) async {
    state = initial ?? const CropState(mediaAspect: 16 / 9, aspect: CropAspect.square);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: StatefulBuilder(
              builder: (context, setState) => CropView(
                state: state,
                interactive: interactive,
                onChanged: (next) => setState(() => state = next),
                frameBuilder: (frame) => KeyedSubtree(key: const ValueKey('wrapped'), child: frame),
                child: const ColoredBox(key: ValueKey('media'), color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sizes the frame to the crop ratio and the media to the crop', (tester) async {
    await pumpCrop(tester);
    expect(tester.getSize(find.byKey(const ValueKey('wrapped'))), const Size(400, 400));
    // The media is 16/9 of the frame wide, centered: it overflows the frame on both sides.
    final media = tester.getRect(find.byKey(const ValueKey('media')));
    expect(media.width, closeTo(400 * 16 / 9, 0.01));
    expect(media.center.dx, closeTo(tester.getCenter(find.byKey(const ValueKey('wrapped'))).dx, 0.01));
  });

  testWidgets('dragging the media moves the crop the other way', (tester) async {
    await pumpCrop(tester);
    await tester.drag(find.byKey(const ValueKey('wrapped')), const Offset(100, 0));
    expect(state.center.dx, lessThan(0.5));
    expect(state.center.dy, 0.5, reason: 'no vertical room in a 16:9 media under a square frame');
  });

  testWidgets('the crop stays inside the media', (tester) async {
    await pumpCrop(tester);
    await tester.drag(find.byKey(const ValueKey('wrapped')), const Offset(-2000, 0));
    expect(state.rect.right, closeTo(1, 1e-9));
  });

  testWidgets('pinching zooms around the fingers, up to the maximum', (tester) async {
    await pumpCrop(tester);
    final center = tester.getCenter(find.byKey(const ValueKey('wrapped')));
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center - Offset(20.0 + i * 20, 0));
      await b.moveTo(center + Offset(20.0 + i * 20, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    // The two fingers move in turn, as two pointer events of the same frame: each update must
    // build on the previous one, not on the state of the last build.
    expect(state.zoom, CropState.maxZoom, reason: 'the fingers spread 11 times apart');
    expect(state.center.dx, closeTo(0.5, 1e-6), reason: 'the media point under the fingers stays under them');
    expect(tester.getSize(find.byKey(const ValueKey('wrapped'))), const Size(400, 400), reason: 'the frame keeps its size');
  });

  testWidgets('does nothing when not interactive', (tester) async {
    await pumpCrop(tester, interactive: false);
    await tester.drag(find.byKey(const ValueKey('wrapped')), const Offset(100, 0));
    expect(state.center, const Offset(0.5, 0.5));
  });
}
