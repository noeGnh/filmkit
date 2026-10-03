import 'package:flutter/services.dart';

/// Why an operation failed.
enum FilmkitErrorCode {
  /// The input or the LUT is missing or unreadable, the input has no video track, or the trim
  /// starts after its end.
  invalidInput,

  /// The export was cancelled with `VideoExport.cancel`.
  cancelled,

  /// The source is HDR and the device can't convert it to SDR.
  hdrUnsupported,

  /// The native exporter failed (decoder, encoder, muxer, disk…).
  exportFailed,

  /// An error the plugin doesn't know.
  unknown,
}

class FilmkitException implements Exception {
  const FilmkitException(this.code, this.message);

  factory FilmkitException.fromPlatform(PlatformException e) => FilmkitException(
    FilmkitErrorCode.values.firstWhere((c) => c.name == e.code, orElse: () => FilmkitErrorCode.unknown),
    e.message ?? e.code,
  );

  final FilmkitErrorCode code;
  final String message;

  @override
  String toString() => 'FilmkitException(${code.name}): $message';
}
