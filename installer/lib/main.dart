import 'package:flutter/widgets.dart';

import 'install.dart';
import 'install_page.dart';
import 'shell.dart';
import 'uninstall.dart';
import 'uninstall_page.dart';

/// `--payload <zip>` installs, from the bootstrapper; `--uninstall <dir>`
/// removes that installation, from uninstall.exe.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--uninstall')) {
    final uninstaller = Uninstaller.fromArguments(arguments);
    await loadFonts(uninstaller.fonts);
    runApp(
      SetupApp(
        title: '卸载 MelonBanG',
        home: UninstallPage(uninstaller: uninstaller),
      ),
    );
  } else {
    final installer = Installer.fromArguments(arguments);
    await loadFonts(await installer.fonts());
    runApp(
      SetupApp(
        title: '安装 MelonBanG',
        home: InstallPage(installer: installer),
      ),
    );
  }
}
