import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Route Command-Q, the Dock and the menu bar through Dart's playback and
    // download shutdown lifecycle, also while the window is hidden; Dart
    // allows the quit once it is done.
    if !MainFlutterWindow.quitAllowed, let channel = MainFlutterWindow.systemChannel {
      channel.invokeMethod("quit", arguments: nil) { reply in
        // Dart has not started listening yet; nothing to shut down.
        if reply as? NSObject === FlutterMethodNotImplemented {
          MainFlutterWindow.quitAllowed = true
          NSApp.terminate(nil)
        }
      }
      return .terminateCancel
    }
    return .terminateNow
  }

  /// Closing the window to the background hides it; Dart ends the app
  /// itself once it quits.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon brings back a window closed to the background.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { showMainWindow() }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func showMainWindow() {
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }

  /// Brings the window back on the downloads page, where the cached episode
  /// a notification is about can be played.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    showMainWindow()
    if let subject = response.notification.request.content.userInfo["subjectId"] as? Int {
      MainFlutterWindow.systemChannel?.invokeMethod("openNotification", arguments: subject)
    }
    completionHandler()
  }
}
