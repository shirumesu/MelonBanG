import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets ||
        input.config.code.targetOS != OS.macOS) {
      return;
    }

    final architecture = switch (input.config.code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      final value => throw UnsupportedError('Unsupported macOS CPU: $value'),
    };
    final deploymentTarget = '${input.config.code.macOS.targetVersion}.0';
    final nativeDirectory = input.outputDirectoryShared.resolve(
      'macos-$architecture-$deploymentTarget/',
    );
    final library = nativeDirectory.resolve('liblibtorrent_flutter.dylib');
    final process = await Process.start('/bin/bash', [
      input.packageRoot.resolve('macos/build.sh').toFilePath(),
      nativeDirectory.toFilePath(),
      architecture,
      deploymentTarget,
    ]);
    await Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    if (await process.exitCode != 0) {
      throw StateError('Failed to build the macOS libtorrent library.');
    }
    output.assets.code.add(
      CodeAsset(
        package: 'libtorrent_flutter',
        name: 'src/ffi_bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
    for (final path in [
      'macos/build.sh',
      'macos/CMakeLists.txt',
      'macos/native_library_path.c',
      'src/torrent_bridge.cpp',
      'src/torrent_bridge.h',
    ]) {
      output.dependencies.add(input.packageRoot.resolve(path));
    }
  });
}
