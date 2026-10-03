import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_example/sample_videos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'pixels.dart';

/// Drives the editor like a user: tools, ratio, filter, trim handles, Done.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> media;

  setUpAll(() async {
    media = {...await copySampleVideos(), ...await copySamplePhotos()};
  });

  /// Pumps real frames until [condition] holds (the editor waits on native calls and plays
  /// video, so pumpAndSettle can't be used).
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String reason = ''}) async {
    for (var i = 0; i < 600 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(condition(), isTrue, reason: 'timed out: $reason');
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  /// Scrolls the filter strip to [name] and selects it.
  Future<void> tapLook(WidgetTester tester, String name) async {
    final look = find.byKey(ValueKey('filmkit.look.$name'));
    await tester.dragUntilVisible(look, find.byKey(const ValueKey('filmkit.looks')), const Offset(-200, 0));
    await tester.pump();
    await tester.tap(look);
    await tester.pump();
  }

  /// Opens the editor on [path] and returns a getter for its result.
  Future<EditorResult? Function()> open(WidgetTester tester, String path, {EditorOptions options = const EditorOptions(), EditorState? initialState}) async {
    // A previous editor may still be animating out.
    await pumpUntil(tester, () => find.byKey(const ValueKey('filmkit.done')).evaluate().isEmpty, reason: 'previous editor closed');
    EditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () async => result = await FilmkitEditor.open(context, path: path, options: options, initialState: initialState),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, 'open');
    bool loaded() {
      final done = find.byKey(const ValueKey('filmkit.done'));
      return done.evaluate().isNotEmpty && tester.widget<TextButton>(done).onPressed != null;
    }

    await pumpUntil(tester, loaded, reason: 'editor loading');
    // Let the route transition (a slide from the bottom on iOS) end before tapping.
    final route = ModalRoute.of(tester.element(find.byKey(const ValueKey('filmkit.done'))))!;
    await pumpUntil(tester, () => route.animation!.isCompleted, reason: 'route transition');
    return () => result;
  }

  testWidgets('photo: square crop and Mono filter', (tester) async {
    final result = await open(tester, media['gradient.jpg']!);
    await tap(tester, 'filmkit.tool.crop');
    await tap(tester, 'filmkit.aspect.1:1');
    await tap(tester, 'filmkit.tool.filters');
    await tapLook(tester, 'Mono');
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'export');

    final r = result()!;
    expect(r.look?.name, 'Mono');
    expect(r.aspect, CropAspect.square);
    expect(r.edit.crop!.width, closeTo(0.75, 1e-6), reason: '480 of 640 px');
    expect((r.export!.width, r.export!.height), (480, 480));
    expect(File(r.edit.lut!).existsSync(), isTrue);

    final image = await tester.runAsync(() => decodeFile(r.export!.path));
    for (final (x, y) in [(50, 50), (240, 240), (400, 100)]) {
      final (red, green, blue) = image!.pixel(x, y);
      expect((red - green).abs() + (green - blue).abs(), lessThan(8), reason: 'Mono at ($x, $y): ($red, $green, $blue)');
    }
  });

  testWidgets('photo: adjustments and filter intensity', (tester) async {
    final result = await open(tester, media['oriented_6.jpg']!);
    await tap(tester, 'filmkit.look.Warm');
    // A second tap opens the intensity slider.
    await tap(tester, 'filmkit.look.Warm');
    await tester.drag(find.byKey(const ValueKey('filmkit.intensity')), const Offset(-100, 0));
    await tap(tester, 'filmkit.slider.done');
    await tap(tester, 'filmkit.tool.adjust');
    await tap(tester, 'filmkit.adjust.brightness');
    await tester.drag(find.byKey(const ValueKey('filmkit.adjust.brightness.slider')), const Offset(60, 0));
    await tap(tester, 'filmkit.slider.done');
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'export');

    final r = result()!;
    expect(r.lookIntensity, inExclusiveRange(0, 1));
    expect(r.adjustments.brightness, greaterThan(0));
    expect(r.edit.crop, isNull, reason: 'original ratio');
    expect((r.export!.width, r.export!.height), (300, 200), reason: 'EXIF orientation applied');
  });

  testWidgets('video: trim, crop and filter', (tester) async {
    final result = await open(tester, media['landscape.mp4']!);
    await tap(tester, 'filmkit.tool.trim');
    await pumpUntil(tester, () => find.byType(RawImage).evaluate().length >= 8, reason: 'trim thumbnails');
    await tester.drag(find.byKey(const ValueKey('filmkit.trim.end')), const Offset(-120, 0));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('filmkit.trim.start')), const Offset(40, 0));
    await tester.pump();
    await tap(tester, 'filmkit.tool.crop');
    await tap(tester, 'filmkit.aspect.4:5');
    await tap(tester, 'filmkit.tool.filters');
    await tapLook(tester, 'Noir');
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'export');

    final r = result()!;
    final edit = r.edit;
    expect(edit.trimStart, greaterThan(Duration.zero));
    expect(edit.trimEnd, lessThan(const Duration(seconds: 6)));
    final info = await tester.runAsync(() => Filmkit.getVideoInfo(r.export!.path));
    expect(info!.duration.inMilliseconds, closeTo((edit.trimEnd! - edit.trimStart).inMilliseconds, 200));
    // 4:5 crop of 640×360: 288×360.
    expect((info.width, info.height), (288, 360));
  });

  testWidgets('closing returns null', (tester) async {
    final result = await open(tester, media['gradient.jpg']!);
    await tap(tester, 'filmkit.close');
    await pumpUntil(tester, () => find.byKey(const ValueKey('open')).evaluate().isNotEmpty, reason: 'pop');
    expect(result(), isNull);
  });

  testWidgets('reopens a photo with an earlier state', (tester) async {
    const noExport = EditorOptions(export: false);
    var result = await open(tester, media['gradient.jpg']!, options: noExport);
    await tap(tester, 'filmkit.tool.crop');
    await tap(tester, 'filmkit.aspect.4:5');
    await tester.drag(find.byKey(const ValueKey('filmkit.preview')), const Offset(80, 0));
    await tester.pump();
    await tap(tester, 'filmkit.tool.filters');
    await tapLook(tester, 'Film');
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'first session');
    final first = result()!;
    expect(first.export, isNull);
    expect(first.state.look, 'Film');
    expect(first.edit.crop!.left, lessThan(0.5 - first.edit.crop!.width / 2), reason: 'panned left of center');

    result = await open(tester, media['gradient.jpg']!, options: noExport, initialState: EditorState.fromJson(first.state.toJson()));
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'second session');
    final second = result()!;
    expect(second.state, first.state);
    expect(second.edit.crop, first.edit.crop);
    expect(second.look?.name, 'Film');
  });

  testWidgets('reopens a video with its trim and look', (tester) async {
    final result = await open(
      tester,
      media['landscape.mp4']!,
      options: const EditorOptions(export: false),
      initialState: const EditorState(look: 'Mono', trimStart: Duration(seconds: 1), trimEnd: Duration(seconds: 3)),
    );
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, () => result() != null, reason: 'done');
    final r = result()!;
    expect((r.edit.trimStart, r.edit.trimEnd), (const Duration(seconds: 1), const Duration(seconds: 3)));
    expect(r.look?.name, 'Mono');
    expect(r.edit.lut, isNotNull);
  });
}
