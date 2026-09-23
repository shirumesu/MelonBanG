import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '--help') {
    stdout.writeln(
      '''Usage:
  dart run scripts/flutter.dart dev [windows|macos] [Flutter arguments]
  dart run scripts/flutter.dart run [Flutter arguments]
  dart run scripts/flutter.dart build <windows|macos> [Flutter arguments]

Local run/build loads .env.service.json automatically.
Use MELONBANG_CONFIGURATION_FILE or --dart-define-from-file for another file.''',
    );
    exitCode = arguments.isEmpty ? 2 : 0;
    return;
  }

  final projectDirectory = File.fromUri(Platform.script).parent.parent;
  final flutterArguments = [...arguments];
  if (flutterArguments.first == 'dev') {
    flutterArguments.removeAt(0);
    final platform =
        flutterArguments.isNotEmpty && !flutterArguments.first.startsWith('-')
        ? flutterArguments.removeAt(0)
        : Platform.operatingSystem;
    if (!['windows', 'macos'].contains(platform)) {
      stderr.writeln('Development platform must be windows or macos.');
      exitCode = 2;
      return;
    }
    flutterArguments.insertAll(0, ['run', '-d', platform]);
  }
  if (!['run', 'build'].contains(flutterArguments.first)) {
    stderr.writeln('Expected dev, run or build. Use --help for examples.');
    exitCode = 2;
    return;
  }

  final explicitFile = flutterArguments.any(
    (argument) =>
        argument == '--dart-define-from-file' ||
        argument.startsWith('--dart-define-from-file='),
  );
  if (!explicitFile) {
    final configuration = Platform.environment['MELONBANG_CONFIGURATION_FILE'];
    final configurationPath = configuration == null || configuration.isEmpty
        ? '.env.service.json'
        : configuration;
    final configurationFile = File.fromUri(
      projectDirectory.uri.resolveUri(Uri.file(configurationPath)),
    );
    if (!configurationFile.existsSync()) {
      stderr.writeln(
        'Copy .env.service.example.json to .env.service.json and fill the '
        'service registrations, or pass --dart-define-from-file=<path>.',
      );
      exitCode = 1;
      return;
    }
    flutterArguments.add('--dart-define-from-file=${configurationFile.path}');
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final flutterCommand = flutterRoot == null || flutterRoot.isEmpty
      ? executable
      : '$flutterRoot/bin/$executable';
  final process = await Process.start(
    flutterCommand,
    flutterArguments,
    workingDirectory: projectDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
