import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if let window = sender.windows.first(where: { $0 is MainFlutterWindow }),
      window.isVisible || window.isMiniaturized {
      // Route Command-Q through Dart's playback and download shutdown lifecycle.
      window.performClose(nil)
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
