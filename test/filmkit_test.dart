import 'package:flutter_test/flutter_test.dart';
import 'package:filmkit/filmkit.dart';
import 'package:filmkit/filmkit_platform_interface.dart';
import 'package:filmkit/filmkit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFilmkitPlatform
    with MockPlatformInterfaceMixin
    implements FilmkitPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FilmkitPlatform initialPlatform = FilmkitPlatform.instance;

  test('$MethodChannelFilmkit is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFilmkit>());
  });

  test('getPlatformVersion', () async {
    Filmkit filmkitPlugin = Filmkit();
    MockFilmkitPlatform fakePlatform = MockFilmkitPlatform();
    FilmkitPlatform.instance = fakePlatform;

    expect(await filmkitPlugin.getPlatformVersion(), '42');
  });
}
