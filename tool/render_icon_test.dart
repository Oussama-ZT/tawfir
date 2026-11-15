// Renders the launcher icon source images from the same code the app uses
// to draw its logo. Run, then generate the platform icons:
//
//   flutter test tool/render_icon_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eco_budget/theme/app_theme.dart';
import 'package:eco_budget/widgets/brand.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(String path, {required bool background, required double coinRatio}) async {
  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const c = EcoColors.light;
  if (background) canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), ui.Paint()..color = c.blue);
  paintEcoMark(canvas, const ui.Offset(size / 2, size / 2), size * coinRatio, c.yellow, c.blue);
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render launcher icon sources', () async {
    // Full icon (iOS, legacy Android): blue square with the coin.
    await _render('assets/icon/icon.png', background: true, coinRatio: 0.6);
    // Adaptive icon foreground: transparent, coin inside the 66 % safe zone.
    await _render('assets/icon/icon_foreground.png', background: false, coinRatio: 0.46);
    expect(File('assets/icon/icon.png').existsSync(), isTrue);
  });
}
