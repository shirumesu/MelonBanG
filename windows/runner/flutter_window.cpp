#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// How long the session's end waits on Dart. Windows ends the process soon
// after WM_ENDSESSION returns, and shows its "this app is preventing
// shutdown" screen for apps that take more than about five seconds.
constexpr ULONGLONG kEndSessionTimeoutMs = 4000;

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
