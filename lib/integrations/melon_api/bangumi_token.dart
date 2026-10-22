import '../../core/json.dart';
import '../../core/network.dart';
import 'source_rules.dart';

/// Bangumi's token endpoint, completed by Melon API with the application
/// secret that a desktop binary cannot keep.
Future<Json> requestBangumiToken(ApiClient api, Map<String, Object> grant) =>
    api.map(
      Uri.parse('$melonApiOrigin/v1/auth/bangumi/token'),
      method: 'POST',
      body: grant,
    );
