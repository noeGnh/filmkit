import 'package:filmkit/src/editor/trim_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const duration = Duration(seconds: 10);
  // 10 s over 400 px of strip: 25 ms per pixel.
  const stripWidth = 400.0;

  late (Duration, Duration, Duration)? changed;
  late int ends;

  Future<void> pumpBar(WidgetTester tester, {Duration start = Duration.zero, Duration end = duration, Duration? maxLength, Duration? position}) async {
    changed = null;
    ends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: stripWidth + 2 * TrimBar.handleWidth,
            child: TrimBar(
              duration: duration,
              start: start,
              end: end,
              thumbnails: const [],
              position: position,
              minLength: const Duration(seconds: 1),
              maxLength: maxLength,
              onChanged: (s, e, moved) => changed = (s, e, moved),
              onChangeEnd: () => ends++,
            ),
          ),
        ),
      ),
    );
  }

  Finder handle(String which) => find.byKey(ValueKey('filmkit.trim.$which'));

  testWidgets('shows the range and its length', (tester) async {
    await pumpBar(tester, start: const Duration(milliseconds: 1500), end: const Duration(seconds: 7));
    expect(find.text('0:01.5 – 0:07.0  (5.5 s)'), findsOneWidget);
  });

  testWidgets('dragging the start handle moves the start and previews it', (tester) async {
    await pumpBar(tester);
    await tester.drag(handle('start'), const Offset(80, 0));
    final (start, end, moved) = changed!;
    // The drag starts after the touch slop: the start lands a little before 80 px (2 s).
    expect(start, greaterThan(const Duration(milliseconds: 1500)));
    expect(start, lessThanOrEqualTo(const Duration(seconds: 2)));
    expect(end, duration);
    expect(moved, start);
    expect(ends, 1);
  });

  testWidgets('the start stays a minimum length before the end', (tester) async {
    await pumpBar(tester, end: const Duration(seconds: 3));
    await tester.drag(handle('start'), const Offset(300, 0));
    expect(changed!.$1, const Duration(seconds: 2));
  });

  testWidgets('the end clamps to the duration', (tester) async {
    await pumpBar(tester, end: const Duration(seconds: 9));
    await tester.drag(handle('end'), const Offset(200, 0));
    expect(changed!.$2, duration);
    expect(changed!.$3, duration);
  });

  testWidgets('a maximum length pulls the other bound', (tester) async {
    await pumpBar(tester, start: const Duration(seconds: 2), end: const Duration(seconds: 5), maxLength: const Duration(seconds: 4));
    await tester.drag(handle('end'), const Offset(200, 0));
    expect(changed!.$2, const Duration(seconds: 6));
    await pumpBar(tester, start: const Duration(seconds: 4), end: const Duration(seconds: 8), maxLength: const Duration(seconds: 4));
    await tester.drag(handle('start'), const Offset(-100, 0));
    expect(changed!.$1, const Duration(seconds: 4), reason: 'already at the maximum length');
  });

  testWidgets('shows the playhead only inside the range', (tester) async {
    await pumpBar(tester, start: const Duration(seconds: 2), end: const Duration(seconds: 6), position: const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('playhead')), findsOneWidget);
    await pumpBar(tester, start: const Duration(seconds: 2), end: const Duration(seconds: 6), position: const Duration(seconds: 7));
    expect(find.byKey(const ValueKey('playhead')), findsNothing);
  });
}
