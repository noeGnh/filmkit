import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' as editor;
import 'export_test.dart' as video_export;
import 'image_test.dart' as image;
import 'lut_test.dart' as lut;

/// Every integration test in one app launch, for CI: each test file is otherwise built and
/// launched separately, and an app launch on a CI simulator sometimes never connects.
void main() {
  group('export', video_export.main);
  group('lut', lut.main);
  group('image', image.main);
  group('editor', editor.main);
}
