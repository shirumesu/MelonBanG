#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// The message the shell sends about the notification icon.
constexpr UINT kNotificationMessage = WM_APP + 1;
constexpr UINT kNotificationIconId = 1;

// How long the session's end waits on Dart. Windows ends the process soon
// after WM_ENDSESSION returns, and shows its "this app is preventing
// shutdown" screen for apps that take more than about five seconds.
constexpr ULONGLONG kEndSessionTimeoutMs = 4000;

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), length);
  return result;
}

const flutter::EncodableValue* Argument(const flutter::EncodableMap& arguments,
                                        const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(std::string(key)));
  return found == arguments.end() ? nullptr : &found->second;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  system_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "org.melonbang/system",
          &flutter::StandardMethodCodec::GetInstance());
  system_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "quit") {
          result->Success();
          // Closed from the message loop, after this call returns: the
          // window's WM_CLOSE destroys the view and the engine, which cannot
          // happen while Dart is running, and then leaves the loop.
          ::PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else if (call.method_name() == "notify") {
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            ShowNotification(*arguments);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveNotificationIcon();
  system_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::EndSession() {
  if (!system_channel_) {
    return;
  }
  auto done = std::make_shared<bool>(false);
  system_channel_->InvokeMethod(
      "endSession", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [done](const flutter::EncodableValue*) { *done = true; },
          [done](const std::string&, const std::string&,
                 const flutter::EncodableValue*) { *done = true; },
          [done]() { *done = true; }));
  // Dart and the engine run on this thread's messages, so keep them flowing
  // until Dart answers.
  const ULONGLONG deadline = ::GetTickCount64() + kEndSessionTimeoutMs;
  while (!*done) {
    const ULONGLONG now = ::GetTickCount64();
    if (now >= deadline) {
      break;
    }
    ::MsgWaitForMultipleObjects(0, nullptr, FALSE,
                                static_cast<DWORD>(deadline - now),
                                QS_ALLINPUT);
    MSG message;
    while (!*done && ::PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        // Leave it for the main loop.
        ::PostQuitMessage(static_cast<int>(message.wParam));
        return;
      }
      ::TranslateMessage(&message);
      ::DispatchMessage(&message);
    }
  }
}

void FlutterWindow::ShowNotification(const flutter::EncodableMap& arguments) {
  const auto* title_value = Argument(arguments, "title");
  const auto* title =
      title_value ? std::get_if<std::string>(title_value) : nullptr;
  if (title == nullptr) {
    return;
  }
  const auto* body_value = Argument(arguments, "body");
  const auto* body = body_value ? std::get_if<std::string>(body_value) : nullptr;
  notification_subject_.reset();
  if (const auto* subject = Argument(arguments, "subjectId")) {
    if (const auto* value = std::get_if<int32_t>(subject)) {
      notification_subject_ = *value;
    } else if (const auto* value64 = std::get_if<int64_t>(subject)) {
      notification_subject_ = *value64;
    }
  }

  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kNotificationIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_INFO;
  data.uCallbackMessage = kNotificationMessage;
  data.hIcon = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_SHARED));
  wcsncpy_s(data.szTip, L"MelonBanG", _TRUNCATE);
  wcsncpy_s(data.szInfoTitle, Utf16FromUtf8(*title).c_str(), _TRUNCATE);
  // An empty text would take the balloon down instead of showing it.
  const std::wstring text = body && !body->empty() ? Utf16FromUtf8(*body)
                                                   : std::wstring(L" ");
  wcsncpy_s(data.szInfo, text.c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_NONE | NIIF_RESPECT_QUIET_TIME;
  if (notification_icon_) {
    ::Shell_NotifyIconW(NIM_MODIFY, &data);
    return;
  }
  if (!::Shell_NotifyIconW(NIM_ADD, &data)) {
    return;
  }
  notification_icon_ = true;
  // Click and balloon events then come as NIN_* codes in LOWORD(lparam).
  data.uVersion = NOTIFYICON_VERSION_4;
  ::Shell_NotifyIconW(NIM_SETVERSION, &data);
}

void FlutterWindow::RemoveNotificationIcon() {
  if (!notification_icon_) {
    return;
  }
  notification_icon_ = false;
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kNotificationIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_ENDSESSION:
      // Windows ends the process soon after this returns, without WM_CLOSE;
      // the Restart Manager instead waits for it to quit, so close once Dart
      // is done.
      if (wparam) {
        EndSession();
        ::PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
      return 0;
    case kNotificationMessage:
      switch (LOWORD(lparam)) {
        case NIN_BALLOONUSERCLICK:
        case NIN_SELECT:
        case NIN_KEYSELECT: {
          // Back on the downloads page, where the cached episode plays.
          const auto subject = notification_subject_;
          RemoveNotificationIcon();
          if (subject && system_channel_) {
            system_channel_->InvokeMethod(
                "openNotification",
                std::make_unique<flutter::EncodableValue>(*subject));
          } else {
            ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
            ::SetForegroundWindow(hwnd);
          }
          break;
        }
        case NIN_BALLOONTIMEOUT:
          RemoveNotificationIcon();
          break;
      }
      return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
