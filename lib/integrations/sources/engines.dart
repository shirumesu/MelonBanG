import '../../data/network.dart';
import '../../domain/sources.dart';
import 'bilibili.dart';
import 'maccms.dart';
import 'page_rules.dart';
import 'rss.dart';

/// Engines compiled into this client, keyed by the rule `engine` name. A new
/// site of a known kind needs only a rule; a new kind of site needs an entry
/// here and, for clients that predate it, a higher `minEngine` in its rule.
final sourceEngines =
    <String, SourceEngine Function(ApiClient, SourceInstance)>{
      'maccms-api': MaccmsApiEngine.new,
      'maccms-html': MaccmsHtmlEngine.new,
      'selector': SelectorEngine.new,
      'bilibili-web': BilibiliEngine.new,
      'rss': RssEngine.new,
    };
