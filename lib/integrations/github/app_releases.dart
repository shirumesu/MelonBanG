import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../../core/json.dart';
import '../../core/network.dart';

const releaseRepository = 'shirumesu/MelonBanG';
final releasePage = Uri.https('github.com', '/$releaseRepository/releases');

/// Public half of the P-256 key CI signs every release manifest with.
const _manifestKey =
    '04c9e5d6daccf8aa367d38e103c1f27dd70e8643c741f7f0aa49f0e9c9c7eae179'
    '4bc9445978d49ed1fd6adbdecc42bc41627b83d8a1360a1c818eb5eb24ee0b89';

/// One downloadable file of a release, as listed in its signed manifest.
class ReleaseFile {
  const ReleaseFile(this.urls, this.sha256, this.size);
  final List<Uri> urls;
  final String sha256;
  final int size;
}

class AppRelease {
  const AppRelease(this.version, this.notes, this.page, this.package);
  final String version, notes;
  final Uri page;

  /// The update package for this platform.
  final ReleaseFile package;
}

/// Published releases on GitHub. Each carries `manifest.json`, signed in
/// `manifest.json.sig`, naming every package with its digest; the app trusts
/// a package only through that signature.
class AppReleases {
  AppReleases(this.api);
  final ApiClient api;

  /// The newest release after [current] with a package for [platform];
  /// prereleases only with [prereleases].
  Future<AppRelease?> newerThan(
    String current,
    String platform, {
    required bool prereleases,
  }) async {
    final installed = SemanticVersion.parse(current);
    final listed = await api.json(
      Uri.https('api.github.com', '/repos/$releaseRepository/releases', {
        'per_page': '20',
      }),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    Json? newest;
    SemanticVersion? newestVersion;
    for (final release in objects(listed)) {
      final tag = '${release['tag_name']}';
      final version = SemanticVersion.tryParse(tag.replaceFirst('v', ''));
      if (release['draft'] == true ||
          version == null ||
          version.compareTo(installed) <= 0 ||
          (version.prerelease && !prereleases) ||
          (newestVersion != null && version.compareTo(newestVersion) <= 0)) {
        continue;
      }
      newest = release;
      newestVersion = version;
    }
    if (newest == null) return null;
    final latest = newestVersion!;
    final assets = {
      for (final asset in objects(newest['assets']))
        '${asset['name']}': Uri.parse('${asset['browser_download_url']}'),
    };
    final [manifestBytes, signature] = await Future.wait([
      _download(assets['manifest.json']),
      _download(assets['manifest.json.sig']),
    ]);
    if (!_verify(manifestBytes, signature)) {
      throw StateError('发行版 ${newest['tag_name']} 的更新清单签名无效');
    }
    final manifest = object(jsonDecode(utf8.decode(manifestBytes)));
    if (manifest['version'] != latest.toString()) {
      throw StateError('更新清单与发行版本不一致');
    }
    final package = object(object(manifest['platforms'])[platform]);
    return AppRelease(
      latest.toString(),
      _unseenNotes('${newest['body'] ?? ''}', installed, latest),
      Uri.parse('${newest['html_url']}'),
      ReleaseFile(
        [for (final url in package['urls'] as List) Uri.parse('$url')],
        '${package['sha256']}',
        number(package['size']).toInt(),
      ),
    );
  }

  Future<Uint8List> _download(Uri? uri) async {
    if (uri == null) throw StateError('发行版缺少更新清单');
    final response = await api.send(
      uri,
      headers: {'Accept': 'application/octet-stream'},
    );
    return response.bodyBytes;
  }
}

/// The part of [latest]'s notes that [installed] lacks. A prerelease's notes
/// have a `## <version>` section for each prerelease of its cycle, newest
/// first; those up to [installed] are dropped. A stable release sums up its
/// prereleases and ships the last one unchanged, so a copy running one of
/// them has it all.
String _unseenNotes(
  String notes,
  SemanticVersion installed,
  SemanticVersion latest,
) {
  if (installed.prerelease &&
      !latest.prerelease &&
      installed.core.join('.') == latest.core.join('.')) {
    return '$latest 是正式版，内容与正在使用的 $installed 相同。';
  }
  bool seen(String section) {
    final heading = RegExp(
      r'^## (\S+)\s*$',
      multiLine: true,
    ).matchAsPrefix(section);
    final version = SemanticVersion.tryParse(heading?[1] ?? '');
    return version != null && version.compareTo(installed) <= 0;
  }

  return notes
      .split(RegExp(r'^(?=## )', multiLine: true))
      .where((section) => !seen(section))
      .join()
      .trim();
}

bool _verify(Uint8List message, Uint8List signature) {
  final curve = ECCurve_prime256v1();
  final key = ECPublicKey(
    curve.curve.decodePoint([
      for (var i = 0; i < _manifestKey.length; i += 2)
        int.parse(_manifestKey.substring(i, i + 2), radix: 16),
    ]),
    curve,
  );
  // OpenSSL writes the signature as a DER sequence of r and s.
  final values = (ASN1Parser(signature).nextObject() as ASN1Sequence).elements!
      .cast<ASN1Integer>();
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(key));
  return verifier.verifySignature(
    message,
    ECSignature(values.first.integer!, values.last.integer!),
  );
}

/// `major.minor.patch[-prerelease]`, ordered by Semantic Versioning 2.0.
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion._(this.text, this.core, this.identifiers);
  final String text;
  final List<int> core;
  final List<String> identifiers;
  bool get prerelease => identifiers.isNotEmpty;

  static final _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  static SemanticVersion? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return SemanticVersion._(text.split('+').first, [
      for (var i = 1; i <= 3; i++) int.parse(match[i]!),
    ], match[4]?.split('.') ?? const []);
  }

  static SemanticVersion parse(String text) =>
      tryParse(text) ?? (throw FormatException('无效的版本号', text));

  @override
  int compareTo(SemanticVersion other) {
    for (var i = 0; i < 3; i++) {
      if (core[i] != other.core[i]) return core[i].compareTo(other.core[i]);
    }
    if (prerelease != other.prerelease) return prerelease ? -1 : 1;
    for (var i = 0; i < identifiers.length; i++) {
      if (i >= other.identifiers.length) return 1;
      final a = identifiers[i], b = other.identifiers[i];
      final x = int.tryParse(a), y = int.tryParse(b);
      final order = x != null && y != null
          ? x.compareTo(y)
          : x != null
          ? -1
          : y != null
          ? 1
          : a.compareTo(b);
      if (order != 0) return order;
    }
    return identifiers.length.compareTo(other.identifiers.length);
  }

  @override
  String toString() => text;
}
