import 'dart:convert';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';
import 'bundled_source_rules.dart';

const melonApiOrigin = 'https://melonapi.konataizumi.com';

/// Reads the maintained rule snapshot with conditional requests.
class SourceRulesClient implements SourceRules {
  SourceRulesClient(this.api);
  final ApiClient api;

  @override
  SourceSnapshot get bundled =>
      SourceSnapshot.fromJson(object(jsonDecode(bundledSourceRules)));

  @override
  Future<({SourceSnapshot snapshot, String? etag})?> fetch({
    String? etag,
  }) async {
    final response = await api.send(
      Uri.parse('$melonApiOrigin/sources/rules?engine=$sourceEngineVersion'),
      headers: {'If-None-Match': ?etag},
      acceptedStatuses: const {304},
    );
    if (response.statusCode == 304) return null;
    return (
      snapshot: SourceSnapshot.fromJson(
        object(jsonDecode(utf8.decode(response.bodyBytes))),
      ),
      etag: response.headers['etag'],
    );
  }
}
