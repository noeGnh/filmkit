import 'dart:ui' as ui;

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'edit_spec.dart';
import 'method_channel_filmkit.dart';
import 'video_export.dart';
import 'video_info.dart';

/// The interface the native implementations provide.
abstract class FilmkitPlatform extends PlatformInterface {
  FilmkitPlatform() : super(token: _token);

  static final Object _token = Object();

  static FilmkitPlatform _instance = MethodChannelFilmkit();

  static FilmkitPlatform get instance => _instance;

  static set instance(FilmkitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  VideoExport exportVideo({required String input, required String output, required EditSpec edit}) {
    throw UnimplementedError('exportVideo() has not been implemented.');
  }

  Future<VideoInfo> getVideoInfo(String path) {
    throw UnimplementedError('getVideoInfo() has not been implemented.');
  }

  Future<ui.Image> getVideoFrame(String path, {Duration position = Duration.zero, int? maxDimension}) {
    throw UnimplementedError('getVideoFrame() has not been implemented.');
  }
}
