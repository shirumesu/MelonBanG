import 'dart:io';

/// Whether every file at [paths], each a finished cache task's, was deleted
/// outside the app, so the task can go too: neither the file nor an
/// unfinished `.part` copy of it is left. A missing [directory], such as an
/// unplugged drive, deletes nothing.
Future<bool> deletedOutside(Iterable<String> paths, String directory) async {
  if (paths.isEmpty || !await Directory(directory).exists()) return false;
  for (final path in paths) {
    if (await File(path).exists() || await File('$path.part').exists()) {
      return false;
    }
  }
  return true;
}
