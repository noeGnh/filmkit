import 'video_info.dart';

/// A running export, returned by `Filmkit.exportVideo`.
class VideoExport {
  VideoExport({required this.progress, required this.result, required this._cancel});

  /// Progress from 0 to 1. Broadcast stream, closed when the export ends.
  final Stream<double> progress;

  /// Completes with the written file, or with a `FilmkitException` (code `cancelled` after
  /// [cancel]).
  final Future<ExportResult> result;

  final Future<void> Function() _cancel;

  /// Stops the export and deletes the partial output. Does nothing if it already ended.
  Future<void> cancel() {
    // The cancellation error is expected: don't report it as uncaught if [result] is awaited
    // after this call, or never.
    result.ignore();
    return _cancel();
  }
}
