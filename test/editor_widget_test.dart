import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes.dart';

/// The editor screen against fake native code: the flows of the device integration tests,
/// without encoding.
void main() {
  late FakeFilmkit filmkit;
  late FakeVideoPlayer player;
  late List<int> preview;
  final mono = Looks.builtIn.firstWhere((look) => look.name == 'Mono');
  final warm = Looks.builtIn.firstWhere((look) => look.name == 'Warm');

  setUpAll(() async {
    preview = await pngBytes(300, 200);
  });

  setUp(() {
    FilmkitPlatform.instance = filmkit = FakeFilmkit(preview: preview);
    VideoPlayerPlatform.instance = player = FakeVideoPlayer();
  });

  /// Runs real I/O (temporary files, image decoding) and pumps until [condition] holds.
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String reason = ''}) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(condition(), isTrue, reason: 'timed out: $reason');
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  bool doneEnabled(WidgetTester tester) => key('filmkit.done').evaluate().isNotEmpty && tester.widget<TextButton>(key('filmkit.done')).onPressed != null;

  /// Opens the editor and waits for it to load; returns whether it closed, and its result.
  Future<({bool Function() closed, EditorResult? Function() result})> open(
    WidgetTester tester, {
    String path = '/media/photo.jpg',
    EditorOptions options = const EditorOptions(export: false),
    EditorState? initialState,
    String? title,
    bool waitLoaded = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var closed = false;
    EditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await FilmkitEditor.open(context, path: path, options: options, initialState: initialState, title: title);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(key('open'));
    await tester.pump();
    if (waitLoaded) await pumpUntil(tester, () => doneEnabled(tester), reason: 'editor loading');
    await tester.pump(const Duration(milliseconds: 500)); // route transition
    return (closed: () => closed, result: () => result);
  }

  /// Unmounts the editor, so that the video player's timers stop.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.tap(key(name));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester, bool Function() closed) async {
    await tap(tester, 'filmkit.done');
    await pumpUntil(tester, closed, reason: 'editor closed');
  }

  group('photo', () {
    testWidgets('shows the title', (tester) async {
      await open(tester, title: '2/4');
      expect(find.text('2/4'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('loads a downscaled preview, then returns the edits', (tester) async {
      final editor = await open(tester, options: EditorOptions(export: false, looks: [mono, warm]));
      final previewCall = filmkit.imageCalls.single;
      expect(previewCall.input, '/media/photo.jpg');
      expect(previewCall.edit.maxDimension, 1600);
      expect(find.text('Trim'), findsNothing, reason: 'no trim for photos');

      await tap(tester, 'filmkit.look.Mono');
      await tap(tester, 'filmkit.tool.crop');
      await tap(tester, 'filmkit.aspect.1:1');
      await done(tester, editor.closed);

      final result = editor.result()!;
      expect(result.export, isNull, reason: 'export: false');
      expect(filmkit.imageCalls, hasLength(1), reason: 'only the preview was exported');
      expect(result.look, mono);
      expect(result.aspect, CropAspect.square);
      expect(result.edit.crop!.width, closeTo(200 / 300, 1e-9));
      expect(result.edit.crop!.height, closeTo(1, 1e-9));
      expect(result.edit.maxDimension, 1080);
      expect(result.state.look, 'Mono');
      expect(await tester.runAsync(() => File(result.edit.lut!).exists()), isTrue);
      await unmount(tester);
    });

    testWidgets('exports with the options', (tester) async {
      final editor = await open(tester, options: const EditorOptions(quality: 75, keepLocation: true, maxDimension: 2048));
      await done(tester, editor.closed);

      final call = filmkit.imageCalls.last;
      expect(filmkit.imageCalls, hasLength(2));
      expect((call.quality, call.keepLocation), (75, true));
      expect(call.edit, const EditSpec(maxDimension: 2048), reason: 'no change: no crop, no LUT');
      expect(editor.result()!.export!.path, call.output);
      await unmount(tester);
    });

    testWidgets('closing returns null', (tester) async {
      final editor = await open(tester);
      await tap(tester, 'filmkit.close');
      await pumpUntil(tester, editor.closed);
      expect(editor.result(), isNull);
      await unmount(tester);
    });

    testWidgets('shows an error when the file can\'t be read', (tester) async {
      filmkit.imageError = const FilmkitException(FilmkitErrorCode.invalidInput, 'File not found: /media/photo.jpg');
      await open(tester, waitLoaded: false);
      await pumpUntil(tester, () => find.textContaining("Can't open this file").evaluate().isNotEmpty);
      expect(find.textContaining('File not found'), findsOneWidget);
      expect(doneEnabled(tester), isFalse);
      await unmount(tester);
    });

    testWidgets('stays open when the export fails', (tester) async {
      final editor = await open(tester, options: const EditorOptions());
      filmkit.imageError = const FilmkitException(FilmkitErrorCode.exportFailed, 'disk full');
      await tap(tester, 'filmkit.done');
      await pumpUntil(tester, () => find.text('Export failed: disk full').evaluate().isNotEmpty);
      expect(editor.closed(), isFalse);
      expect(doneEnabled(tester), isTrue, reason: 'the user can try again');
      await unmount(tester);
    });

    testWidgets('filter intensity and adjustments', (tester) async {
      final editor = await open(tester, options: EditorOptions(export: false, looks: [warm]));
      await tap(tester, 'filmkit.look.Warm');
      await tap(tester, 'filmkit.look.Warm'); // a second tap opens the intensity slider
      // The drag starts at the middle of the slider (50 %), then moves left.
      await tester.drag(key('filmkit.intensity'), const Offset(-40, 0));
      await tap(tester, 'filmkit.slider.done');
      await tap(tester, 'filmkit.tool.adjust');
      await tap(tester, 'filmkit.adjust.contrast');
      await tester.drag(key('filmkit.adjust.contrast.slider'), const Offset(-100, 0));
      await tap(tester, 'filmkit.slider.done');
      await done(tester, editor.closed);

      final result = editor.result()!;
      expect(result.lookIntensity, inExclusiveRange(0, 1));
      expect(result.adjustments.contrast, lessThan(0));
      expect(result.adjustments.brightness, 0);
      // One table with the look at that intensity, then the adjustments.
      final lut = (await tester.runAsync(() => CubeLut.fromFile(result.edit.lut!)))!;
      final (r, g, b) = lut.apply(0.5, 0.5, 0.5);
      final expected = combinedLut(warm, result.lookIntensity, result.adjustments)!.apply(0.5, 0.5, 0.5);
      expect(
        [r, g, b],
        [
          for (final v in [expected.$1, expected.$2, expected.$3]) closeTo(v, 1e-4),
        ],
      );
      await unmount(tester);
    });

    testWidgets('reopens with an earlier state', (tester) async {
      const state = EditorState(
        look: 'Mono',
        lookIntensity: 0.4,
        adjustments: Adjustments(warmth: 0.5),
        aspect: CropAspect.square,
        cropZoom: 2,
        cropCenter: Offset(0.3, 0.5),
      );
      final editor = await open(
        tester,
        options: EditorOptions(export: false, looks: [mono]),
        initialState: state,
      );
      await done(tester, editor.closed);
      expect(editor.result()!.state, state);
      await unmount(tester);
    });

    testWidgets('an earlier state with a removed look opens without it', (tester) async {
      final editor = await open(
        tester,
        options: EditorOptions(export: false, looks: [mono]),
        initialState: const EditorState(look: 'Gone'),
      );
      await done(tester, editor.closed);
      expect(editor.result()!.look, isNull);
      expect(editor.result()!.edit.lut, isNull);
      await unmount(tester);
    });
  });

  group('video', () {
    testWidgets('trims, and loads the thumbnails', (tester) async {
      final editor = await open(tester, path: '/media/clip.mp4');
      await tap(tester, 'filmkit.tool.trim');
      await pumpUntil(tester, () => filmkit.frameCalls.length == 9, reason: 'filter thumbnail + 8 trim thumbnails');
      await tester.drag(key('filmkit.trim.start'), const Offset(100, 0));
      await tester.pump();
      await tester.drag(key('filmkit.trim.end'), const Offset(-100, 0));
      await tester.pump();
      await done(tester, editor.closed);

      final edit = editor.result()!.edit;
      expect(edit.trimStart, greaterThan(Duration.zero));
      expect(edit.trimEnd, lessThan(const Duration(seconds: 10)));
      expect(edit.trimEnd! - edit.trimStart, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(editor.result()!.state.trimStart, edit.trimStart);
      await unmount(tester);
    });

    testWidgets('exports with progress', (tester) async {
      final editor = await open(tester, path: '/media/clip.mp4', options: const EditorOptions());
      await tap(tester, 'filmkit.done');
      await pumpUntil(tester, () => filmkit.videoProgress != null);
      expect(player.playing.values.single, isFalse, reason: 'paused during the export');
      filmkit.videoProgress!.add(0.5);
      await tester.pump();
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);

      filmkit.videoResult!.complete(const ExportResult(path: '/out/clip.mp4', width: 1080, height: 608));
      await pumpUntil(tester, editor.closed);
      expect(editor.result()!.export!.path, '/out/clip.mp4');
      expect(filmkit.videoCalls.single.edit, const EditSpec(maxDimension: 1080), reason: 'no trim, crop or LUT');
      await unmount(tester);
    });

    testWidgets('cancelling the export keeps the editor open, without an error', (tester) async {
      final editor = await open(tester, path: '/media/clip.mp4', options: const EditorOptions());
      await tap(tester, 'filmkit.done');
      await pumpUntil(tester, () => key('filmkit.export.cancel').evaluate().isNotEmpty);
      await tap(tester, 'filmkit.export.cancel');
      await pumpUntil(tester, () => doneEnabled(tester));
      expect(filmkit.videoCancelled, isTrue);
      expect(editor.closed(), isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(player.playing.values.single, isTrue, reason: 'playing again');
      await unmount(tester);
    });

    testWidgets('opens without thumbnails when frames fail', (tester) async {
      filmkit.frameError = const FilmkitException(FilmkitErrorCode.invalidInput, 'No frame at 5000 ms');
      final editor = await open(tester, path: '/media/clip.mp4');
      await tap(tester, 'filmkit.tool.trim');
      await tester.pump();
      expect(key('filmkit.trim.start'), findsOneWidget);
      await done(tester, editor.closed);
      expect(editor.result(), isNotNull);
      await unmount(tester);
    });
  });
}
