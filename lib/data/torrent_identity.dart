import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String magnetInfoHash(Uri uri) {
  for (final topic in uri.queryParametersAll['xt'] ?? <String>[]) {
    final match = RegExp(r'^urn:btih:([a-fA-F0-9]{40}|[A-Z2-7a-z]{32})$')
        .firstMatch(topic);
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
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
  throw const FormatException('磁力链接缺少有效的 BT info hash');
}

/// Hash the original encoded info dictionary; trackers and comments do not
/// change torrent identity, and decoding/re-encoding may change its byte order.
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
