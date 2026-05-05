import 'package:firecheck/core/drive/drive_filename_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPhotoFilename', () {
    test('preserves simple alphanumeric filename', () {
      expect(formatPhotoFilename('a1', 'photo1.jpg'), 'a1_photo1.jpg');
    });

    test('replaces spaces with underscores', () {
      expect(formatPhotoFilename('a1', 'My Photo 2026.jpg'), 'a1_My_Photo_2026.jpg');
    });

    test('strips special characters', () {
      expect(formatPhotoFilename('a1', 'IMG (1) copy.jpeg'), 'a1_IMG_1_copy.jpeg');
    });

    test('strips emoji leaving no trailing underscores', () {
      expect(formatPhotoFilename('a1', 'my selfie 😎.jpg'), 'a1_my_selfie.jpg');
    });

    test('emoji-only stem falls back to file', () {
      expect(formatPhotoFilename('a1', '😎.png'), 'a1_file.png');
    });

    test('handles filename with no extension', () {
      expect(formatPhotoFilename('a1', 'no_extension'), 'a1_no_extension');
    });

    test('lowercases the extension', () {
      expect(formatPhotoFilename('a1', 'PHOTO.JPG'), 'a1_PHOTO.jpg');
    });

    test('collapses consecutive underscores from multiple spaces', () {
      expect(formatPhotoFilename('a1', 'a  b.jpg'), 'a1_a_b.jpg');
    });
  });

  group('formatShapefileFilename', () {
    test('returns assignmentId.zip', () {
      expect(formatShapefileFilename('a1'), 'a1.zip');
    });

    test('works with UUID-style assignment IDs', () {
      expect(
        formatShapefileFilename('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400-e29b-41d4-a716-446655440000.zip',
      );
    });
  });
}
