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

    super.awakeFromNib()
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
