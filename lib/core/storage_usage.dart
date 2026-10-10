import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

class StorageUsage {
  const StorageUsage({this.dataBytes, this.mediaBytes});

  final int? dataBytes, mediaBytes;

  static Future<StorageUsage> measure(String data, String media) =>
      Isolate.run(() => _measure(data, media));

  static StorageUsage _measure(String data, String media) {
    String canonical(String path) {
      final directory = Directory(path);
      return directory.existsSync()
          ? directory.resolveSymbolicLinksSync()
          : p.normalize(p.absolute(path));
    }

    try {
      data = canonical(data);
      media = canonical(media);
    } on FileSystemException {
      return const StorageUsage();
    }
    int? size(String path) {
      try {
        return _directoryBytes(path);
      } on FileSystemException {
        return null;
      } on ProcessException {
        return null;
      }
    }

    var dataBytes = size(data);
    var mediaBytes = size(media);
    // Default media lives inside data; each category must count it only once.
    if (p.equals(data, media) || p.isWithin(data, media)) {
      dataBytes = _subtract(dataBytes, mediaBytes);
    } else if (p.isWithin(media, data)) {
      mediaBytes = _subtract(mediaBytes, dataBytes);
    }
    return StorageUsage(dataBytes: dataBytes, mediaBytes: mediaBytes);
  }
}

int? _subtract(int? total, int? excluded) => total == null || excluded == null
    ? null
    : (total - excluded).clamp(0, total);

int _directoryBytes(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) return 0;
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('Storage location is not a directory', path);
  }
  if (Platform.isMacOS) {
    // du counts allocated blocks, including sparse downloads, without following
    // links inside the tree. Run off the UI isolate and never through a shell.
    final result = Process.runSync('/usr/bin/du', ['-skP', path]);
    final match = RegExp(r'^\s*(\d+)\s').firstMatch('${result.stdout}');
    if (result.exitCode != 0 || match == null) {
      throw FileSystemException('Cannot measure storage location', path);
    }
    return int.parse(match.group(1)!) * 1024;
  }
  if (Platform.isWindows) {
    final allocatedBytes = _WindowsAllocatedBytes();
    var total = 0;
    for (final entry in Directory(
      path,
    ).listSync(recursive: true, followLinks: false)) {
      if (entry is File) total += allocatedBytes.read(entry.path);
    }
    return total;
  }
  throw UnsupportedError('Unsupported storage platform');
}

class _WindowsAllocatedBytes {
  final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _size = _kernel
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Uint32>),
        int Function(Pointer<Utf16>, Pointer<Uint32>)
      >('GetCompressedFileSizeW');
  late final _error = _kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  late final _clearError = _kernel
      .lookupFunction<Void Function(Uint32), void Function(int)>(
        'SetLastError',
      );

  int read(String path) {
    final name = path.toNativeUtf16();
    final high = calloc<Uint32>();
    try {
      _clearError(0);
      final low = _size(name, high);
      if (low == 0xffffffff) {
        final error = _error();
        // Files can disappear while downloads are being removed.
        if (error == 2 || error == 3) return 0;
        if (error != 0) {
          throw FileSystemException(
            'Cannot measure file',
            path,
            OSError('GetCompressedFileSizeW failed', error),
          );
        }
      }
      return (high.value << 32) | low;
    } finally {
      calloc.free(name);
      calloc.free(high);
    }
  }
}
