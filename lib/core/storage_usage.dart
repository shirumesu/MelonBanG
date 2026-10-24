import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

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

    data = canonical(data);
    media = canonical(media);
    var dataBytes = _directoryBytes(data);
    var mediaBytes = _directoryBytes(media);
    // Default media lives inside data; each category must count it only once.
    // Files can change between the two walks, so never go below zero.
    if (p.equals(data, media) || p.isWithin(data, media)) {
      dataBytes = max(0, dataBytes - mediaBytes);
    } else if (p.isWithin(media, data)) {
      mediaBytes = max(0, mediaBytes - dataBytes);
    }
    return StorageUsage(dataBytes: dataBytes, mediaBytes: mediaBytes);
  }
}

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

/// The volume a folder is on and the space left on it for this user.
class DiskSpace {
  const DiskSpace(this.volume, this.free);

  /// Where the volume is mounted, such as `D:\` or `/Volumes/Media`.
  final String volume;
  final int free;

  /// Whether this is the Windows system drive, which slows the whole system
  /// down once it fills up.
  bool get system =>
      Platform.isWindows &&
      p.equals(volume, '${Platform.environment['SystemDrive']}\\');

  /// The volume of [path], which need not exist yet.
  static Future<DiskSpace> of(String path) =>
      Isolate.run(() => _diskSpace(path));
}

DiskSpace _diskSpace(String path) {
  var existing = p.normalize(p.absolute(path));
  while (!Directory(existing).existsSync() && p.dirname(existing) != existing) {
    existing = p.dirname(existing);
  }
  if (Platform.isMacOS) {
    final result = Process.runSync('/bin/df', ['-kP', existing]);
    // "Filesystem 1024-blocks Used Available Capacity Mounted on".
    final match = RegExp(r'\s(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+(.+)$')
        .firstMatch('${result.stdout}'.trim().split('\n').last);
    if (result.exitCode != 0 || match == null) {
      throw FileSystemException('Cannot read free space', path);
    }
    return DiskSpace(match.group(4)!, int.parse(match.group(3)!) * 1024);
  }
  if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final volumePath = kernel
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('GetVolumePathNameW');
    final freeSpace = kernel
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW');
    return using((arena) {
      final name = existing.toNativeUtf16(allocator: arena);
      final volume = arena<Uint16>(261).cast<Utf16>();
      final free = arena<Uint64>();
      if (volumePath(name, volume, 261) == 0 ||
          freeSpace(name, free, nullptr, nullptr) == 0) {
        throw FileSystemException('Cannot read free space', path);
      }
      return DiskSpace(volume.toDartString(), free.value);
    });
  }
  throw UnsupportedError('Unsupported storage platform');
}
