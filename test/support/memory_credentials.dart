import 'package:melonbang/data/credentials.dart';

class MemoryCredentials implements Credentials {
  final values = <String, String>{};
  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async =>
      values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
