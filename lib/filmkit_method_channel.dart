import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filmkit_platform_interface.dart';

/// An implementation of [FilmkitPlatform] that uses method channels.
class MethodChannelFilmkit extends FilmkitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('filmkit');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
