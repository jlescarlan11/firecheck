import 'dart:io';

import 'package:firecheck/core/photos/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('image_processor_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Already gone — fine.
    }
  });

  test('resizes large image to 1600 px longest edge', () async {
    final src = img.Image(width: 3000, height: 2000);
    img.fill(src, color: img.ColorRgb8(255, 0, 0));
    final srcPath = p.join(tempDir.path, 'src.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'dest.jpg');
    await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );

    final out = img.decodeImage(await File(destPath).readAsBytes())!;
    expect(out.width, 1600);
    expect(out.height, lessThanOrEqualTo(1600));
    expect(
      await File(destPath).length(),
      lessThan(await File(srcPath).length()),
    );
  });

  test('does not upscale a small image', () async {
    final src = img.Image(width: 800, height: 600);
    img.fill(src, color: img.ColorRgb8(0, 255, 0));
    final srcPath = p.join(tempDir.path, 'small.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'small_out.jpg');
    await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );

    final out = img.decodeImage(await File(destPath).readAsBytes())!;
    expect(out.width, 800);
    expect(out.height, 600);
  });

  test('returns null gps for image without EXIF', () async {
    final src = img.Image(width: 100, height: 100);
    img.fill(src, color: img.ColorRgb8(0, 0, 255));
    final srcPath = p.join(tempDir.path, 'no_exif.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'no_exif_out.jpg');
    final gps = await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );
    expect(gps.lat, isNull);
    expect(gps.lng, isNull);
  });
}
