/// Application registrations supplied by Flutter build definitions.
class ServiceConfiguration {
  const ServiceConfiguration({
    this.bangumiClientId = const String.fromEnvironment('BANGUMI_CLIENT_ID'),
    this.bangumiClientSecret = const String.fromEnvironment(
      'BANGUMI_CLIENT_SECRET',
    ),
    this.bangumiRedirectUri = const String.fromEnvironment(
      'BANGUMI_REDIRECT_URI',
      defaultValue: 'http://127.0.0.1:14567/callback',
    ),
    this.dandanplayAppId = const String.fromEnvironment('DANDANPLAY_APP_ID'),
    this.dandanplayAppSecret = const String.fromEnvironment(
      'DANDANPLAY_APP_SECRET',
    ),
  });

  final String bangumiClientId;
  final String bangumiClientSecret;
  final String bangumiRedirectUri;
  final String dandanplayAppId;
  final String dandanplayAppSecret;

  bool get hasBangumi =>
      bangumiClientId.trim().isNotEmpty &&
      bangumiClientSecret.trim().isNotEmpty;
  bool get hasDandanplay =>
      dandanplayAppId.trim().isNotEmpty &&
      dandanplayAppSecret.trim().isNotEmpty;
}
