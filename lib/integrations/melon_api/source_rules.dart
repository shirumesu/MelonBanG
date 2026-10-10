import 'dart:convert';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';
import 'bundled_source_rules.dart';

const melonApiOrigin = 'https://melonapi.konataizumi.com';

/// Reads the maintained rule snapshot with conditional requests.
class SourceRulesClient implements SourceRules {
  SourceRulesClient(this.api, {this.origin = melonApiOrigin});
  final ApiClient api;
  final String origin;

  @override
  SourceSnapshot get bundled =>
      SourceSnapshot.fromJson(object(jsonDecode(bundledSourceRules)));

  @override
  Future<({SourceSnapshot snapshot, String? etag})?> fetch({
    String? etag,
  }) async {
    final response = await api.send(
      Uri.parse('$origin/sources/rules?engine=$sourceEngineVersion'),
      headers: {'If-None-Match': ?etag},
      acceptedStatuses: const {304},
    );
    if (response.statusCode == 304) return null;
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, Uri.parse(origin).host);
    }
    return (
      snapshot: SourceSnapshot.fromJson(
        object(jsonDecode(utf8.decode(response.bodyBytes))),
      ),
      etag: response.headers['etag'],
    );
  }
}
