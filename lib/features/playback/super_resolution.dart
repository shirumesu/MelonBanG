import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Anime4K 4.0.1 "Mode A" chains, for 720p–1080p anime shown on a larger
/// output, as its mpv instructions list them. `fast` suits integrated GPUs.
const _chains = {
  'fast': [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ],
  'quality': [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ],
};

/// Files of the shader chain for [mode], empty for `off`. mpv reads shaders
/// from disk, so the bundled assets are copied under application support
/// once per shader version.
Future<List<String>> superResolutionShaders(String mode) async {
  final names = _chains[mode];
  if (names == null) return const [];
  final folder = Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'shaders',
      'anime4k-4.0.1',
    ),
  );
  await folder.create(recursive: true);
  return [for (final name in names) await _copy(folder, name)];
}

Future<String> _copy(Directory folder, String name) async {
  final file = File(p.join(folder.path, name));
  if (!await file.exists()) {
    final data = await rootBundle.load('assets/shaders/$name');
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await partial.rename(file.path);
  }
  return file.path;
}

/// 4K, 2K, or the short side such as 1080P, by the long side of [size].
String resolutionLabel(Size size) {
  final long = math.max(size.width, size.height);
  if (long >= 3800) return '4K';
  if (long >= 2500) return '2K';
  return '${math.min(size.width, size.height).round()}P';
}
