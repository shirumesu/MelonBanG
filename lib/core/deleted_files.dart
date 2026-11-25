import 'dart:io';

/// Whether every file at [paths], each a finished cache task's, was deleted
/// outside the app (neither it nor its `.part` copy is left), so the task can
/// go too. False while [directory] is missing, such as on an unplugged drive.
Future<bool> deletedOutside(Iterable<String> paths, String directory) async {
  if (paths.isEmpty || !await Directory(directory).exists()) return false;
  for (final path in paths) {
    if (await File(path).exists() || await File('$path.part').exists()) {
      return false;
    }
  }
  return true;
}
