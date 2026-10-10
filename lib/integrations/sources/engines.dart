import '../../core/network.dart';
import '../../domain/sources.dart';
import 'bilibili.dart';
import 'maccms.dart';
import 'page_rules.dart';
import 'rss.dart';

/// Engines compiled into this client, keyed by the rule `engine` name. A new
/// site of a known kind needs only a rule; a new kind of site needs an entry
/// here and, for clients that predate it, a higher `minEngine` in its rule.
Map<String, SourceEngineFactory> sourceEngines(ApiClient api) => {
  'maccms-api': (rule) => MaccmsApiEngine(api, rule),
  'maccms-html': (rule) => MaccmsHtmlEngine(api, rule),
  'selector': (rule) => SelectorEngine(api, rule),
  'bilibili-web': (rule) => BilibiliEngine(api, rule),
  'rss': (rule) => RssEngine(api, rule),
};
