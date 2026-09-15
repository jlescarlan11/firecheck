import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:native_exif/native_exif.dart';

class ImageProcessor {
  const ImageProcessor();

  /// Reads [sourcePath], resizes to 1600 px longest edge preserving aspect,
  /// re-encodes as JPEG quality 85, copies EXIF GPS tags from the source,
  /// writes to [destPath]. Returns the GPS lat/lng read from EXIF (null if
  /// the photo had no location tags or EXIF read failed on this platform).
  Future<({double? lat, double? lng})> resizeAndCopyExif({
    required String sourcePath,
    required String destPath,
  }) async {
    // Pass only paths so full-resolution pixels stay in the worker isolate.
    // Platform-channel EXIF operations remain on the main isolate.
    await compute(
      _resizePhoto,
      (sourcePath: sourcePath, destPath: destPath),
      debugLabel: 'resizePhoto',
    );
    return _copyExifAndReadGps(sourcePath, destPath);
  }

  /// Reads GPS from [sourcePath] via `native_exif` and writes it onto
  /// [destPath]. Because the plugin is platform-channel-backed, this will
  /// throw `MissingPluginException` when `flutter test` runs on the host
  /// VM — we swallow any error and return `(null, null)` in that case.
  Future<({double? lat, double? lng})> _copyExifAndReadGps(
    String sourcePath,
    String destPath,
  ) async {
    Exif? srcExif;
    Exif? dstExif;
    try {
      srcExif = await Exif.fromPath(sourcePath);
      final latLong = await srcExif.getLatLong();
      if (latLong == null) {
        return (lat: null, lng: null);
      }

      final lat = latLong.latitude;
      final lng = latLong.longitude;

      dstExif = await Exif.fromPath(destPath);
      // native_exif reads GPSLatitude/GPSLongitude as doubles in absolute
      // value alongside the ref tag, so write them back in the same shape.
      await dstExif.writeAttributes(<String, Object>{
        'GPSLatitude': lat.abs(),
        'GPSLongitude': lng.abs(),
        'GPSLatitudeRef': lat >= 0 ? 'N' : 'S',
        'GPSLongitudeRef': lng >= 0 ? 'E' : 'W',
      });
      return (lat: lat, lng: lng);
    } on Object {
      // Host VM (no platform plugin) or corrupt EXIF — degrade gracefully.
      return (lat: null, lng: null);
    } finally {
      try {
        await srcExif?.close();
      } on Object {
        // ignore
      }
      try {
        await dstExif?.close();
      } on Object {
        // ignore
      }
    }
  }
}

/// Runs file decoding, resizing, and JPEG encoding off the UI isolate.
Future<void> _resizePhoto(
  ({String sourcePath, String destPath}) paths,
) async {
  final srcBytes = await File(paths.sourcePath).readAsBytes();
  final decoded = img.decodeImage(srcBytes);
  if (decoded == null) {
    throw const ImageProcessingException('Could not decode source image');
  }
  const target = 1600;
  final img.Image resized;
  if (decoded.width <= target && decoded.height <= target) {
    resized = decoded;
  } else if (decoded.width >= decoded.height) {
    resized = img.copyResize(decoded, width: target);
  } else {
    resized = img.copyResize(decoded, height: target);
  }
  final outBytes = img.encodeJpg(resized, quality: 85);
  await File(paths.destPath).writeAsBytes(outBytes, flush: true);
}

class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);
  final String message;

  @override
  String toString() => 'ImageProcessingException: $message';
}
