import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts its states, to check that toggling the filter keeps the child's state.
class _Counter extends StatefulWidget {
  const _Counter();

  static int created = 0;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    _Counter.created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: 10);
}

void main() {
  final warm = CubeLut.generate(9, (r, g, b) => (r, g * 0.9, b * 0.8));

  Future<void> pumpFilter(WidgetTester tester, CubeLut? lut, {double intensity = 1}) => tester.pumpWidget(
    MaterialApp(
      home: LutFilter(lut: lut, intensity: intensity, child: const _Counter()),
    ),
  );

  testWidgets('shows the child unfiltered without a LUT', (tester) async {
    await pumpFilter(tester, null);
    expect(find.byType(_Counter), findsOneWidget);
    expect(tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isFalse);
  });

  testWidgets('keeps the child state when the LUT or the intensity changes', (tester) async {
    _Counter.created = 0;
    await pumpFilter(tester, null);
    await tester.runAsync(() => pumpFilter(tester, warm));
    await tester.pump();
    await pumpFilter(tester, warm, intensity: 0);
    await pumpFilter(tester, CubeLut.identity(5));
    await pumpFilter(tester, null);
    expect(_Counter.created, 1);
  });

  testWidgets('a zero intensity disables the filter', (tester) async {
    await tester.runAsync(() => pumpFilter(tester, warm, intensity: 0));
    await tester.pump();
    expect(tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isFalse);
  });
}
