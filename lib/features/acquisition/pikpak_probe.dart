import '../../data/pikpak.dart';
import '../../domain/sources.dart';
import 'source_registry.dart';

/// Checks that the signed-in PikPak drive answers, for the Sources page.
Future<void> probePikPak(SourceRegistry registry, PikPakClient pikpak) =>
    registry.probe(
      'pikpak',
      url: 'https://api-drive.mypikpak.com/drive/v1/files',
      external: () async {
        if (!pikpak.isSignedIn || pikpak.needsAuthorization) {
          throw StateError('请在设置中登录 PikPak 后重试');
        }
        try {
          await pikpak.files('');
        } on PikPakCaptchaRequired catch (error) {
          throw SourceVerificationRequired(error.url.toString());
        }
      },
    );
