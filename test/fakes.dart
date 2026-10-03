import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A PNG of [width] × [height] (a horizontal gradient), as the native photo preview export
/// writes a JPEG.
Future<List<int>> pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(width.toDouble(), 0), [const ui.Color(0xFFFF0000), const ui.Color(0xFF0000FF)]),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Records the calls and answers like the native side, without encoding anything.
class FakeFilmkit extends FilmkitPlatform {
  FakeFilmkit({required this.preview});

  /// Bytes written for photo exports (the editor decodes its preview from them).
  final List<int> preview;

  VideoInfo videoInfo = const VideoInfo(width: 1920, height: 1080, duration: Duration(seconds: 10), hasAudio: true, isHdr: false);

  /// Thrown by the next calls of each method, when set.
  FilmkitException? imageError;
  FilmkitException? frameError;

  final imageCalls = <({String input, String output, EditSpec edit, int quality, bool keepLocation})>[];
  final videoCalls = <({String input, String output, EditSpec edit})>[];
  final frameCalls = <Duration>[];

  /// The running video export: the test drives its progress and end.
  StreamController<double>? videoProgress;
  Completer<ExportResult>? videoResult;
  bool videoCancelled = false;

  @override
  Future<ExportResult> exportImage({
    required String input,
    required String output,
    required EditSpec edit,
    required int quality,
    required bool keepLocation,
  }) async {
    imageCalls.add((input: input, output: output, edit: edit, quality: quality, keepLocation: keepLocation));
    if (imageError != null) throw imageError!;
    await File(output).writeAsBytes(preview);
    return ExportResult(path: output, width: 300, height: 200);
  }

  @override
  VideoExport exportVideo({required String input, required String output, required EditSpec edit}) {
    videoCalls.add((input: input, output: output, edit: edit));
    final progress = videoProgress = StreamController<double>.broadcast();
    final result = videoResult = Completer<ExportResult>();
    return VideoExport(
      progress: progress.stream,
      result: result.future,
      cancel: () async {
        videoCancelled = true;
        if (!result.isCompleted) result.completeError(const FilmkitException(FilmkitErrorCode.cancelled, 'Cancelled'));
        await progress.close();
      },
    );
  }

  @override
  Future<VideoInfo> getVideoInfo(String path) async => videoInfo;

  @override
  Future<ui.Image> getVideoFrame(String path, {Duration position = Duration.zero, int? maxDimension}) async {
    frameCalls.add(position);
    if (frameError != null) throw frameError!;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
    return recorder.endRecording().toImage(16, 9);
  }
}

/// A video player that reports [duration] and [size], and keeps its position where seeked.
class FakeVideoPlayer extends VideoPlayerPlatform {
  FakeVideoPlayer({this.duration = const Duration(seconds: 10), this.size = const Size(1920, 1080)});

  final Duration duration;
  final Size size;
  final _events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final playing = <int, bool>{};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _create();

  int _create() {
    final id = _next++;
    positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>(
      onListen: () => _events[id]!.add(VideoEvent(eventType: VideoEventType.initialized, duration: duration, size: size)),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events.remove(playerId)?.close();

  @override
  Future<void> play(int playerId) async => playing[playerId] = true;

  @override
  Future<void> pause(int playerId) async => playing[playerId] = false;

  @override
  Future<void> seekTo(int playerId, Duration position) async => positions[playerId] = position;

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}
