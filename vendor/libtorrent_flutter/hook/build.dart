import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Builds the bridge with libtorrent on macOS and Linux; the Windows plugin
/// builds it with CMake instead.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    if (code.targetOS != OS.macOS && code.targetOS != OS.linux) return;
    final macOS = code.targetOS == OS.macOS;

    final architecture = switch (code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      final value => throw UnsupportedError('Unsupported CPU: $value'),
    };
    final deploymentTarget = macOS ? '${code.macOS.targetVersion}.0' : null;
    final nativeDirectory = input.outputDirectoryShared.resolve(
      macOS ? 'macos-$architecture-$deploymentTarget/' : 'linux-$architecture/',
    );
    final library = nativeDirectory.resolve(
      macOS ? 'liblibtorrent_flutter.dylib' : 'liblibtorrent_flutter.so',
    );
    final script = macOS ? 'native/build-macos.sh' : 'native/build-linux.sh';
    final process = await Process.start('/bin/bash', [
      input.packageRoot.resolve(script).toFilePath(),
      nativeDirectory.toFilePath(),
      architecture,
      ?deploymentTarget,
    ]);
    await Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    if (await process.exitCode != 0) {
      throw StateError('Failed to build the libtorrent library.');
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
      script,
      'native/CMakeLists.txt',
      'native/exports.map',
      'native/native_library_path.c',
      'src/torrent_bridge.cpp',
      'src/torrent_bridge.h',
    ]) {
      output.dependencies.add(input.packageRoot.resolve(path));
    }
  });
}
