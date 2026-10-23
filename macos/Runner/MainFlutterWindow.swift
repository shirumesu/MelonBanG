import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMethodChannel(
      name: "org.melonbang/credentials",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      Self.handleCredentials(call, result: result)
    }
    FlutterMethodChannel(
      name: "org.melonbang/system",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      Self.handleSystem(call, result: result)
    }

    super.awakeFromNib()

    // AppKit puts the window buttons back after resizing, full screen and
    // style changes; centre them again each time.
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didBecomeMainNotification,
    ] {
      NotificationCenter.default.addObserver(
        forName: name, object: self, queue: .main
      ) { [weak self] _ in self?.centerWindowButtons() }
    }
    centerWindowButtons()
  }

  /// Flutter draws a 44-point title bar; AppKit centres the window buttons
  /// on its default 28-point one, which leaves them above the bar's other
  /// controls. Grow the button container to the bar and centre the buttons,
  /// spaced like a unified toolbar inside the 78 points Flutter leaves them.
  private func centerWindowButtons() {
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let titlebar = close.superview,
      let container = titlebar.superview
    else { return }
    let height: CGFloat = 44
    var frame = container.frame
    frame.size.height = height
    frame.origin.y = self.frame.height - height
    container.frame = frame
    titlebar.frame = container.bounds
    let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (index, type) in buttons.enumerated() {
      guard let button = standardWindowButton(type) else { continue }
      button.setFrameOrigin(NSPoint(
        x: 20 + CGFloat(index) * 20,
        y: ((height - button.frame.height) / 2).rounded()
      ))
    }
  }

  /// The accent colour and the manual proxy configuration of the system.
  private static func handleSystem(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "accentColor":
      guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
        result(nil)
        return
      }
      let channel = { (value: CGFloat) in Int((value * 255).rounded()) & 0xff }
      result(
        0xff00_0000 | channel(color.redComponent) << 16
          | channel(color.greenComponent) << 8 | channel(color.blueComponent))
    case "proxy":
      guard
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
          as? [String: Any]
      else {
        result(nil)
        return
      }
      func server(_ prefix: String) -> String? {
        guard (settings["\(prefix)Enable"] as? NSNumber)?.boolValue == true,
          let host = settings["\(prefix)Proxy"] as? String, !host.isEmpty
        else { return nil }
        guard let port = settings["\(prefix)Port"] as? NSNumber else { return host }
        return "\(host):\(port.intValue)"
      }
      var proxy: [String: Any] = ["exceptions": settings["ExceptionsList"] as? [String] ?? []]
      if let http = server("HTTP") { proxy["http"] = http }
      if let https = server("HTTPS") { proxy["https"] = https }
      result(proxy)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func handleCredentials(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let service = arguments["service"] as? String,
      let key = arguments["key"] as? String
    else {
      result(FlutterError(code: "arguments", message: "Missing credential identity", details: nil))
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    var status: OSStatus
    switch call.method {
    case "read":
      // Login keychain items use the file-based API; SecItem's authentication
      // context does not suppress its UI. Scope the legacy switch to this call.
      let quiet = arguments["allowInteraction"] as? Bool == false
      var previousInteraction: DarwinBoolean = true
      if quiet {
        status = LoginKeychainInteraction.get(&previousInteraction)
        if status == errSecSuccess { status = LoginKeychainInteraction.set(false) }
        if status != errSecSuccess {
          result(FlutterError(code: "keychain_\(status)", message: "Cannot read credentials without interaction", details: nil))
          return
        }
      }
      defer {
        if quiet { LoginKeychainInteraction.set(previousInteraction.boolValue) }
      }
      var lookup = query
      lookup[kSecReturnData as String] = true
      lookup[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      status = SecItemCopyMatching(lookup as CFDictionary, &item)
      if status == errSecItemNotFound {
        result(nil)
        return
      }
      if status == errSecSuccess, let data = item as? Data {
        result(String(data: data, encoding: .utf8))
        return
      }
    case "write":
      if let value = arguments["value"] as? String {
        let data = Data(value.utf8)
        status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
          var item = query
          item[kSecValueData as String] = data
          status = SecItemAdd(item as CFDictionary, nil)
        }
      } else {
        status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { status = errSecSuccess }
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    if status == errSecSuccess {
      result(nil)
    } else {
      result(FlutterError(
        code: "keychain_\(status)",
        message: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed",
        details: nil
      ))
    }
  }
}

// File-based login Keychain ACLs require this legacy switch for quiet reads.
// Keep the deprecation exception confined to the two audited compatibility calls.
#if compiler(>=6.4)
@diagnose(DeprecatedDeclaration, as: ignored, reason: "SecItem authentication flags do not suppress file-based Keychain ACL dialogs")
#endif
private enum LoginKeychainInteraction {
  static func get(_ allowed: UnsafeMutablePointer<DarwinBoolean>) -> OSStatus {
    SecKeychainGetUserInteractionAllowed(allowed)
  }

  @discardableResult
  static func set(_ allowed: Bool) -> OSStatus {
    SecKeychainSetUserInteractionAllowed(allowed)
  }
}
