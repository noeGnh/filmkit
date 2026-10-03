import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit/src/method_channel_filmkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the method channel by default', () {
    expect(FilmkitPlatform.instance, isA<MethodChannelFilmkit>());
  });

  test('forwards every call to the platform', () async {
    final fake = FilmkitPlatform.instance = FakeFilmkit(preview: await pngBytes(4, 4));
    const edit = EditSpec(maxDimension: 720);

    final image = await Filmkit.exportImage(
      input: 'in.jpg',
      output: '${Directory.systemTemp.path}/filmkit_test.jpg',
      edit: edit,
      quality: 80,
      keepLocation: true,
    );
    expect((fake.imageCalls.single.quality, fake.imageCalls.single.keepLocation, fake.imageCalls.single.edit), (80, true, edit));
    expect(image.width, 300);

    final defaults = await Filmkit.exportImage(input: 'in.jpg', output: '${Directory.systemTemp.path}/filmkit_test.jpg');
    expect((fake.imageCalls.last.quality, fake.imageCalls.last.keepLocation, fake.imageCalls.last.edit), (90, false, const EditSpec()));
    expect(defaults.path, endsWith('filmkit_test.jpg'));

    final export = Filmkit.exportVideo(input: 'in.mp4', output: 'out.mp4', edit: edit);
    expect(fake.videoCalls.single, (input: 'in.mp4', output: 'out.mp4', edit: edit));
    await export.cancel();
    expect(fake.videoCancelled, isTrue);

    expect((await Filmkit.getVideoInfo('in.mp4')).duration, const Duration(seconds: 10));
    final frame = await Filmkit.getVideoFrame('in.mp4', position: const Duration(seconds: 3));
    expect(fake.frameCalls.single, const Duration(seconds: 3));
    frame.dispose();
  });
}
