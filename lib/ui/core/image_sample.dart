import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes [bytes] on the CPU in a background isolate, scales the first
/// frame to [width] pixels wide and hands its RGBA bytes to [read], which
/// runs in that isolate too.
///
/// Pixels are never read back with `ui.Image.toByteData`: Impeller on
/// Windows copies them off the GPU on the IO thread while holding ANGLE's
/// global lock, so frames stall behind every read, and that extra GPU work
/// made Flutter 3.50's race between the IO and raster threads
/// (flutter/flutter#196618) crash the GPU driver far more often.
Future<T> sampleImage<T>(
  Uint8List bytes,
  int width,
  FutureOr<T> Function(Uint8List rgba) read,
) async {
  await _slots.acquire();
  try {
    return await Isolate.run(() => read(_sample(bytes, width)));
  } finally {
    _slots.release();
  }
}

Uint8List _sample(Uint8List bytes, int width) {
  final image = _decode(bytes, width);
  if (image == null) throw const FormatException('无法解码图片');
  return img
      .copyResize(image, width: width, interpolation: img.Interpolation.average)
      .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
      .getBytes(order: img.ChannelOrder.rgba);
}

/// JPEGs, nearly every cover, decode straight at the smallest of 1/8, 1/4
/// or 1/2 size still at least [width] wide, several times faster than in
/// full.
img.Image? _decode(Uint8List bytes, int width) {
  if (!img.JpegDecoder().isValidFile(bytes)) {
    return img.decodeImage(bytes, frame: 0);
  }
  final full = img.JpegDecoder().startDecode(bytes)?.width;
  if (full == null) return null;
  final scale = [8, 4, 2].firstWhere(
    (scale) => (full + scale - 1) ~/ scale >= width,
    orElse: () => 1,
  );
  return img.JpegDecoder(scale: scale).decode(bytes);
}

// A screen of covers loads together; a few decodes at a time keep that
// from taking every core and holding dozens of full-size bitmaps at once.
final _slots = _Slots(4);

class _Slots {
  _Slots(this.limit);
  final int limit;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_active < limit) {
      _active++;
      return Future.value();
    }
    final slot = Completer<void>();
    _waiting.add(slot);
    return slot.future;
  }

  void release() {
    if (_waiting.isEmpty) {
      _active--;
    } else {
      _waiting.removeFirst().complete();
    }
  }
}
