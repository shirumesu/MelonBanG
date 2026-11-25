import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/hex.dart';

final _btih = RegExp(r'^urn:btih:([a-fA-F0-9]{40}|[A-Z2-7a-z]{32})$');

String magnetInfoHash(Uri uri) {
  for (final topic in uri.queryParametersAll['xt'] ?? <String>[]) {
    final match = _btih.firstMatch(topic);
    if (match == null) continue;
    final encoded = match[1]!;
    if (encoded.length == 40) return encoded.toLowerCase();
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0, bits = 0;
    final bytes = <int>[];
    for (final character in encoded.toUpperCase().split('')) {
      buffer = (buffer << 5) | alphabet.indexOf(character);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 255);
        buffer &= (1 << bits) - 1;
      }
    }
    return hexEncode(bytes);
  }
  throw const FormatException('磁力链接缺少有效的 BT info hash');
}

/// Deduplication key of a search result: its infohash when the locator has
/// one, else the locator. Kept, since every update of a search reads each
/// result's identity again and parsing a magnet with its trackers is slow.
String torrentIdentity(String locator) {
  if (_identities[locator] case final identity?) return identity;
  if (_identities.length >= 8192) _identities.clear();
  return _identities[locator] = _identity(locator);
}

final _identities = <String, String>{};

/// Identities of [locators], worked out off the UI isolate for that isolate
/// to [keepIdentities].
Map<String, String> torrentIdentities(Iterable<String> locators) => {
  for (final locator in locators) locator: torrentIdentity(locator),
};

void keepIdentities(Map<String, String> identities) {
  if (_identities.length + identities.length > 8192) _identities.clear();
  _identities.addAll(identities);
}

String _identity(String locator) {
  final uri = Uri.tryParse(locator);
  if (uri == null) return locator;
  if (uri.scheme == 'magnet') {
    try {
      return magnetInfoHash(uri);
    } on FormatException {
      // No BT info hash: keep the locator distinct below.
    } on ArgumentError {
      // Decoding a site's malformed percent-encoding.
      return locator;
    }
  }
  final String filename;
  try {
    filename = uri.pathSegments.lastOrNull ?? '';
  } on ArgumentError {
    return locator;
  }
  if (filename.endsWith('.torrent')) {
    final hash = filename.substring(0, filename.length - 8).toLowerCase();
    if (hash.length == 40 &&
        hash.codeUnits.every(
          (c) => c >= 48 && c <= 57 || c >= 97 && c <= 102,
        )) {
      return hash;
    }
  }
  return uri.toString();
}

/// The SHA-1 of the info dictionary's bytes as stored: trackers and comments
/// do not change a torrent's identity, and re-encoding could reorder it.
String torrentInfoHash(Uint8List bytes) {
  final reader = _BencodeReader(bytes);
  if (reader.take() != 100) throw const FormatException('种子文件格式无效');
  while (reader.peek != 101) {
    final key = ascii.decode(reader.string(), allowInvalid: true);
    final start = reader.offset;
    reader.skip();
    if (key == 'info') {
      if (bytes[start] != 100) throw const FormatException('种子缺少 info 字典');
      return sha1
          .convert(Uint8List.sublistView(bytes, start, reader.offset))
          .toString();
    }
  }
  throw const FormatException('种子缺少 info 字典');
}

/// The torrent's own name: its single file's name, or its root folder's.
String torrentName(Uint8List bytes) {
  final reader = _BencodeReader(bytes);
  if (reader.take() != 100) throw const FormatException('种子文件格式无效');
  while (reader.peek != 101) {
    final key = ascii.decode(reader.string(), allowInvalid: true);
    if (key != 'info') {
      reader.skip();
      continue;
    }
    if (reader.take() != 100) throw const FormatException('种子缺少 info 字典');
    String? name;
    while (reader.peek != 101) {
      final field = ascii.decode(reader.string(), allowInvalid: true);
      if (field == 'name.utf-8' || (field == 'name' && name == null)) {
        name = utf8.decode(reader.string(), allowMalformed: true);
      } else {
        reader.skip();
      }
    }
    if (name == null || name.isEmpty) break;
    return name;
  }
  throw const FormatException('种子缺少名称');
}

class _BencodeReader {
  _BencodeReader(this.data);
  final Uint8List data;
  int offset = 0;
  int get peek {
    if (offset >= data.length) throw const FormatException('种子文件不完整');
    return data[offset];
  }

  int take() {
    final value = peek;
    offset++;
    return value;
  }

  Uint8List string() {
    final start = offset;
    while (peek >= 48 && peek <= 57) {
      offset++;
    }
    final length = int.tryParse(ascii.decode(data.sublist(start, offset)));
    if (take() != 58 || length == null || offset + length > data.length) {
      throw const FormatException('种子字符串无效');
    }
    final value = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return value;
  }

  void skip() {
    if (peek == 100 || peek == 108) {
      take();
      while (peek != 101) {
        skip();
      }
      take();
    } else if (peek == 105) {
      take();
      while (take() != 101) {}
    } else {
      string();
    }
  }
}
