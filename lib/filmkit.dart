
import 'filmkit_platform_interface.dart';

class Filmkit {
  Future<String?> getPlatformVersion() {
    return FilmkitPlatform.instance.getPlatformVersion();
  }
}
